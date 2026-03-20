import SwiftUI
import AppKit
import CoreImage
import CoreLocation
import ImageIO
import MapCore

enum LocationMode: String, CaseIterable {
    case auto = "auto"
    case address = "address"
    case photos = "photos"

    var label: String {
        switch self {
        case .auto: return "Current Location"
        case .address: return "Location"
        case .photos: return "Most Photographed"
        }
    }
}

class GeneratorViewModel: ObservableObject {
    @AppStorage("defaultAddress") var defaultAddress: String = ""
    @AppStorage("locationMode") var locationModeRaw: String = "auto" { didSet { regenerateIfNeeded() } }
    @AppStorage("defaultZoom") var zoom: Int = 14 { didSet { regenerateIfNeeded() } }
    @AppStorage("heatmapEnabled") var heatmapEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    @AppStorage("selectedTheme") var selectedThemeId: String = "cyberpunk" { didSet { regenerateIfNeeded() } }
    @AppStorage("hdrEnabled") var hdrEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    var locationMode: LocationMode {
        get { LocationMode(rawValue: locationModeRaw) ?? .auto }
        set { locationModeRaw = newValue.rawValue }
    }

    var selectedTheme: MapTheme { Themes.byId(selectedThemeId) }

    @Published var isGenerating = false
    @Published var progress: String = ""
    @Published var previewImage: NSImage?
    @Published var lastError: String?
    @Published var locationString: String = "Locating..."
    @Published var photoCount: Int = 0

    private func regenerateIfNeeded() {
        if previewImage != nil { generate() }
    }

    func resolveLocation() {
        LocationService.shared.ensureAuthorized()
        DispatchQueue.global(qos: .utility).async { [self] in
            switch locationMode {
            case .address:
                guard !defaultAddress.isEmpty else {
                    DispatchQueue.main.async { self.locationString = "No address set" }
                    return
                }
                DispatchQueue.main.async { self.locationString = self.defaultAddress }

            case .auto:
                guard let loc = getCoreLocation() else {
                    DispatchQueue.main.async { self.locationString = "Location unavailable" }
                    return
                }
                reverseGeocode(lat: loc.0, lon: loc.1)

            case .photos:
                let points = fetchPhotoLocations()
                guard let cluster = findDensestCluster(in: points) else {
                    DispatchQueue.main.async { self.locationString = "No geotagged photos" }
                    return
                }
                reverseGeocode(lat: cluster.lat, lon: cluster.lon)
            }
        }
    }

    private func reverseGeocode(lat: Double, lon: Double) {
        let location = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let p = placemarks?.first {
                let parts = [p.locality, p.country].compactMap { $0 }
                DispatchQueue.main.async {
                    self.locationString = parts.isEmpty
                        ? String(format: "%.4f, %.4f", lat, lon)
                        : parts.joined(separator: ", ")
                }
            } else {
                DispatchQueue.main.async {
                    self.locationString = String(format: "%.4f, %.4f", lat, lon)
                }
            }
        }
    }

    func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        lastError = nil
        progress = "Loading photos..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Load photos
            var heatmapPoints: [LocationPoint]?
            let points = fetchPhotoLocations()
            DispatchQueue.main.async { self.photoCount = points.count }
            if heatmapEnabled && !points.isEmpty {
                heatmapPoints = points
            }

            // Resolve location based on mode
            DispatchQueue.main.async { self.progress = "Resolving location..." }
            var lat: Double
            var lon: Double

            switch locationMode {
            case .address:
                guard !defaultAddress.isEmpty, let loc = geocodeAddress(defaultAddress) else {
                    DispatchQueue.main.async {
                        self.lastError = "Could not geocode address"
                        self.isGenerating = false
                    }
                    return
                }
                lat = loc.0; lon = loc.1

            case .auto:
                guard let loc = getCoreLocation() else {
                    DispatchQueue.main.async {
                        self.lastError = "Could not detect location. Grant access in System Settings → Privacy & Security → Location Services."
                        self.isGenerating = false
                    }
                    return
                }
                lat = loc.0; lon = loc.1

            case .photos:
                guard let cluster = findDensestCluster(in: points) else {
                    DispatchQueue.main.async {
                        self.lastError = "No geotagged photos found"
                        self.isGenerating = false
                    }
                    return
                }
                lat = cluster.lat; lon = cluster.lon
            }

            // Get screen size
            var screenW = 2560, screenH = 1440
            DispatchQueue.main.sync {
                if let screen = NSScreen.main {
                    let scale = screen.backingScaleFactor
                    screenW = Int(screen.frame.width * scale)
                    screenH = Int(screen.frame.height * scale)
                }
            }

            DispatchQueue.main.async { self.progress = "Rendering wallpaper..." }

            let theme = selectedTheme
            let useHDR = self.hdrEnabled

            if useHDR {
                guard let ciImage = generateMapImageHDR(
                    lat: lat, lon: lon, zoom: zoom,
                    width: screenW, height: screenH,
                    heatmapPoints: heatmapPoints,
                    theme: theme
                ) else {
                    DispatchQueue.main.async {
                        self.lastError = "Failed to generate wallpaper"
                        self.isGenerating = false
                    }
                    return
                }

                let ciCtx = CIContext()
                guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else {
                    DispatchQueue.main.async {
                        self.lastError = "Failed to create preview image"
                        self.isGenerating = false
                    }
                    return
                }
                let previewImg = NSImage(cgImage: cgImage, size: NSSize(width: screenW, height: screenH))

                DispatchQueue.main.async { self.progress = "Setting wallpaper..." }

                do {
                    try WallpaperService.setWallpaperHDR(ciImage: ciImage)
                    DispatchQueue.main.async {
                        self.previewImage = previewImg
                        self.lastCIImage = ciImage
                        self.lastCGImage = nil
                        self.progress = "Done!"
                        self.isGenerating = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        self.isGenerating = false
                    }
                }
            } else {
                guard let cgImage = generateMapImage(
                    lat: lat, lon: lon, zoom: zoom,
                    width: screenW, height: screenH,
                    heatmapPoints: heatmapPoints,
                    theme: theme
                ) else {
                    DispatchQueue.main.async {
                        self.lastError = "Failed to generate wallpaper"
                        self.isGenerating = false
                    }
                    return
                }

                let previewImg = NSImage(cgImage: cgImage, size: NSSize(width: screenW, height: screenH))

                DispatchQueue.main.async { self.progress = "Setting wallpaper..." }

                do {
                    try WallpaperService.setWallpaperSDR(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.previewImage = previewImg
                        self.lastCIImage = nil
                        self.lastCGImage = cgImage
                        self.progress = "Done!"
                        self.isGenerating = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        self.isGenerating = false
                    }
                }
            }
        }
    }

    private(set) var lastCIImage: CIImage?
    private(set) var lastCGImage: CGImage?

    var canSave: Bool { lastCIImage != nil || lastCGImage != nil }

    func saveImage() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.level = .floating

        if let ciImage = lastCIImage {
            panel.allowedContentTypes = [.heic]
            panel.nameFieldStringValue = "Cartogram Wallpaper.heic"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else { return }
            let ctx = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            ])
            try? ctx.writeHEIF10Representation(of: ciImage, to: url, colorSpace: colorSpace)
        } else if let cgImage = lastCGImage {
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "Cartogram Wallpaper.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, cgImage, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
