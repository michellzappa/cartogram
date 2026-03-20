import MapCore
#if canImport(AppKit)
import AppKit
#endif
import CoreImage
import Foundation

// MARK: - CLI Argument Parsing

func parseArgs() -> Config {
    var c = Config()
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        switch args[i] {
        case "--lat": i += 1; if i < args.count { c.lat = Double(args[i]) }
        case "--lon": i += 1; if i < args.count { c.lon = Double(args[i]) }
        case "--address", "-a":
            i += 1
            if i < args.count {
                var parts = [args[i]]
                while i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    i += 1; parts.append(args[i])
                }
                c.address = parts.joined(separator: " ")
            }
        case "--zoom", "-z": i += 1; if i < args.count { c.zoom = Int(args[i]) ?? 14 }
        case "--no-heatmap": c.heatmap = false
        case "--help", "-h": c.help = true
        default: break
        }
        i += 1
    }
    c.zoom = max(1, min(14, c.zoom))
    return c
}

// MARK: - macOS Wallpaper

#if canImport(AppKit)
func setWallpaper(ciImage: CIImage) throws {
    let fm = FileManager.default
    let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cartogram")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    // Clean up old wallpapers
    if let oldFiles = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
        for f in oldFiles { try? fm.removeItem(at: f) }
    }

    let file = dir.appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970)).heic")

    // Write HDR HEIF (10-bit PQ)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else {
        print("Error: Could not create HDR color space")
        exit(1)
    }
    let ctx = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    ])
    try ctx.writeHEIF10Representation(of: ciImage, to: file, colorSpace: colorSpace)
    print("Saved: \(file.path)")

    let workspace = NSWorkspace.shared
    for screen in NSScreen.screens {
        try workspace.setDesktopImageURL(file, for: screen, options: [:])
    }
    print("Wallpaper set!")
}

func screenPixelSize() -> (width: Int, height: Int)? {
    guard let screen = NSScreen.main else { return nil }
    let scale = screen.backingScaleFactor
    return (Int(screen.frame.width * scale), Int(screen.frame.height * scale))
}
#endif

// MARK: - Main

let config = parseArgs()

if config.help {
    print("""
    Cartogram - map wallpaper from your photo locations

    Usage: cartogram [options]

      --address, -a     Street address to geocode
      --lat <degrees>   Latitude (auto-detected if omitted)
      --lon <degrees>   Longitude (auto-detected if omitted)
      --zoom, -z <n>    Zoom level 1-18 (default: 14)
      --no-heatmap      Skip photo heatmap overlay
      -h, --help        Show this help

    Map data: © OpenStreetMap contributors
    Tiles: OpenFreeMap
    """)
    exit(0)
}

print("Cartogram - map wallpaper")
print()

// Resolve center location
var lat: Double, lon: Double

if let la = config.lat, let lo = config.lon {
    lat = la; lon = lo
    print("Location: \(lat), \(lon)")
} else if let addr = config.address {
    print("Geocoding: \(addr)")
    guard let loc = geocodeAddress(addr) else {
        print("Error: Could not geocode address.")
        exit(1)
    }
    lat = loc.0; lon = loc.1
    print("  Coordinates: \(lat), \(lon)")
} else {
    print("Detecting location...")
    guard let loc = getCoreLocation() else {
        print("Error: Could not detect location. Use --address or --lat/--lon.")
        exit(1)
    }
    lat = loc.0; lon = loc.1
    print("  CoreLocation: \(lat), \(lon)")
}

// Load heatmap data
var heatmapPoints: [LocationPoint]?
if config.heatmap {
    print("Loading photos via PhotoKit...")
    let points = fetchPhotoLocations()
    if !points.isEmpty { heatmapPoints = points }
}

// Auto-center on densest photo cluster if no explicit location given
if let points = heatmapPoints, config.lat == nil && config.lon == nil && config.address == nil {
    if let cluster = findDensestCluster(in: points) {
        lat = cluster.lat
        lon = cluster.lon
        print("  Centering on densest photo cluster: \(lat), \(lon) (\(cluster.count) photos)")
    }
}

// Determine output size
#if canImport(AppKit)
guard let size = screenPixelSize() else {
    print("Error: No screen found")
    exit(1)
}
#else
let size = (width: 2560, height: 1440) // sensible default for headless
#endif

print("  Screen: \(size.width)x\(size.height) px")
print("Generating HDR wallpaper (zoom \(config.zoom))...")

guard let ciImage = generateMapImageHDR(
    lat: lat, lon: lon, zoom: config.zoom,
    width: size.width, height: size.height,
    heatmapPoints: heatmapPoints
) else {
    print("Error: Failed to generate wallpaper")
    exit(1)
}

#if canImport(AppKit)
do {
    try setWallpaper(ciImage: ciImage)
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
#endif
