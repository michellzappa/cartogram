import SwiftUI
import AppKit
import CoreImage
import CoreLocation
import ImageIO
import Photos
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

final class GeneratorViewModel: ObservableObject {
    @AppStorage("defaultAddress") var defaultAddress: String = "" { didSet { regenerateIfNeeded() } }
    @AppStorage("locationMode") var locationModeRaw: String = "auto" { didSet { regenerateIfNeeded() } }
    @AppStorage("defaultZoom") var zoom: Int = 14 { didSet { regenerateIfNeeded() } }
    @AppStorage("heatmapEnabled") var heatmapEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    @AppStorage("selectedTheme") var selectedThemeId: String = "cyberpunk" { didSet { regenerateIfNeeded() } }
    @AppStorage("hdrEnabled") var hdrEnabled: Bool = true { didSet { regenerateIfNeeded() } }

    @Published var isGenerating = false
    @Published var progress: String = ""
    @Published var previewImage: NSImage?
    @Published var lastError: String?
    @Published var locationString: String = "Locating..."
    @Published var photoCount: Int = 0

    var locationMode: LocationMode {
        get { LocationMode(rawValue: locationModeRaw) ?? .auto }
        set { locationModeRaw = newValue.rawValue }
    }

    var selectedTheme: MapTheme { Themes.byId(selectedThemeId) }
    var canSave: Bool { lastCIImage != nil || lastCGImage != nil }

    private(set) var lastCIImage: CIImage?
    private(set) var lastCGImage: CGImage?

    private var pendingGenerate = false
    private let photoCacheLock = NSLock()
    private var cachedPhotoLocations: [LocationPoint]?
    private var cachedPhotoAuthorizationStatus: PHAuthorizationStatus?

    private struct ResolveSnapshot {
        let defaultAddress: String
        let locationMode: LocationMode
    }

    private struct RenderSnapshot {
        let defaultAddress: String
        let locationMode: LocationMode
        let zoom: Int
        let heatmapEnabled: Bool
        let selectedTheme: MapTheme
        let hdrEnabled: Bool
    }

    private func regenerateIfNeeded() {
        if previewImage != nil { generate() }
    }

    private func makeResolveSnapshot() -> ResolveSnapshot {
        ResolveSnapshot(
            defaultAddress: defaultAddress,
            locationMode: locationMode
        )
    }

    private func makeRenderSnapshot() -> RenderSnapshot {
        RenderSnapshot(
            defaultAddress: defaultAddress,
            locationMode: locationMode,
            zoom: zoom,
            heatmapEnabled: heatmapEnabled,
            selectedTheme: selectedTheme,
            hdrEnabled: hdrEnabled
        )
    }

    func resolveLocation() {
        let snapshot = makeResolveSnapshot()

        LocationService.shared.ensureAuthorized()

        DispatchQueue.global(qos: .utility).async { [self] in
            switch snapshot.locationMode {
            case .address:
                guard !snapshot.defaultAddress.isEmpty else {
                    DispatchQueue.main.async { self.locationString = "No address set" }
                    return
                }
                DispatchQueue.main.async { self.locationString = snapshot.defaultAddress }

            case .auto:
                guard let loc = getCoreLocation() else {
                    DispatchQueue.main.async { self.locationString = "Location unavailable" }
                    return
                }
                reverseGeocode(lat: loc.0, lon: loc.1)

            case .photos:
                let points = photoLocations()
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
            if let placemark = placemarks?.first {
                let parts = [placemark.locality, placemark.country].compactMap { $0 }
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
        guard !isGenerating else {
            pendingGenerate = true
            return
        }

        let snapshot = makeRenderSnapshot()

        isGenerating = true
        lastError = nil
        progress = "Loading photos..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let points = photoLocations()
            let heatmapPoints = snapshot.heatmapEnabled && !points.isEmpty ? points : nil

            DispatchQueue.main.async { self.progress = "Resolving location..." }

            let lat: Double
            let lon: Double

            switch snapshot.locationMode {
            case .address:
                guard !snapshot.defaultAddress.isEmpty,
                      let loc = geocodeAddress(snapshot.defaultAddress) else {
                    DispatchQueue.main.async {
                        self.failGeneration("Could not geocode address")
                    }
                    return
                }
                lat = loc.0
                lon = loc.1

            case .auto:
                guard let loc = getCoreLocation() else {
                    DispatchQueue.main.async {
                        self.failGeneration("Could not detect location. Grant access in System Settings → Privacy & Security → Location Services.")
                    }
                    return
                }
                lat = loc.0
                lon = loc.1

            case .photos:
                guard let cluster = findDensestCluster(in: points) else {
                    DispatchQueue.main.async {
                        self.failGeneration("No geotagged photos found")
                    }
                    return
                }
                lat = cluster.lat
                lon = cluster.lon
            }

            reverseGeocode(lat: lat, lon: lon)

            var screenWidth = 2560
            var screenHeight = 1440
            DispatchQueue.main.sync {
                if let screen = NSScreen.main {
                    let scale = screen.backingScaleFactor
                    screenWidth = Int(screen.frame.width * scale)
                    screenHeight = Int(screen.frame.height * scale)
                }
            }

            DispatchQueue.main.async { self.progress = "Rendering wallpaper..." }

            if snapshot.hdrEnabled {
                guard let ciImage = generateMapImageHDR(
                    lat: lat,
                    lon: lon,
                    zoom: snapshot.zoom,
                    width: screenWidth,
                    height: screenHeight,
                    heatmapPoints: heatmapPoints,
                    theme: snapshot.selectedTheme
                ) else {
                    DispatchQueue.main.async {
                        self.failGeneration("Failed to generate wallpaper")
                    }
                    return
                }

                let ciContext = CIContext()
                guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    DispatchQueue.main.async {
                        self.failGeneration("Failed to create preview image")
                    }
                    return
                }

                let previewImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: screenWidth, height: screenHeight)
                )

                DispatchQueue.main.async { self.progress = "Setting wallpaper..." }

                do {
                    try WallpaperService.setWallpaperHDR(ciImage: ciImage)
                    DispatchQueue.main.async {
                        self.finishGeneration(previewImage: previewImage, ciImage: ciImage, cgImage: nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.failGeneration(error.localizedDescription)
                    }
                }
            } else {
                guard let cgImage = generateMapImage(
                    lat: lat,
                    lon: lon,
                    zoom: snapshot.zoom,
                    width: screenWidth,
                    height: screenHeight,
                    heatmapPoints: heatmapPoints,
                    theme: snapshot.selectedTheme
                ) else {
                    DispatchQueue.main.async {
                        self.failGeneration("Failed to generate wallpaper")
                    }
                    return
                }

                let previewImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: screenWidth, height: screenHeight)
                )

                DispatchQueue.main.async { self.progress = "Setting wallpaper..." }

                do {
                    try WallpaperService.setWallpaperSDR(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.finishGeneration(previewImage: previewImage, ciImage: nil, cgImage: cgImage)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.failGeneration(error.localizedDescription)
                    }
                }
            }
        }
    }

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

            let context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            ])

            try? context.writeHEIF10Representation(of: ciImage, to: url, colorSpace: colorSpace)
        } else if let cgImage = lastCGImage {
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "Cartogram Wallpaper.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private func finishGeneration(previewImage: NSImage, ciImage: CIImage?, cgImage: CGImage?) {
        self.previewImage = previewImage
        lastCIImage = ciImage
        lastCGImage = cgImage
        progress = "Done!"
        isGenerating = false
        restartQueuedGenerationIfNeeded()
    }

    private func failGeneration(_ message: String) {
        lastError = message
        isGenerating = false
        restartQueuedGenerationIfNeeded()
    }

    private func restartQueuedGenerationIfNeeded() {
        guard pendingGenerate else { return }
        pendingGenerate = false
        generate()
    }

    private func photoLocations(forceRefresh: Bool = false) -> [LocationPoint] {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        photoCacheLock.lock()
        if !forceRefresh,
           let cachedPhotoLocations,
           cachedPhotoAuthorizationStatus == currentStatus {
            photoCacheLock.unlock()
            DispatchQueue.main.async {
                self.photoCount = cachedPhotoLocations.count
            }
            return cachedPhotoLocations
        }
        photoCacheLock.unlock()

        let points = fetchPhotoLocations()
        let resolvedStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        photoCacheLock.lock()
        cachedPhotoLocations = points
        cachedPhotoAuthorizationStatus = resolvedStatus
        photoCacheLock.unlock()

        DispatchQueue.main.async {
            self.photoCount = points.count
        }

        return points
    }
}
