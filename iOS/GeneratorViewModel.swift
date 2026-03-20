import SwiftUI
import UIKit
import CoreImage
import CoreLocation
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

class GeneratorViewModel: ObservableObject {
    @AppStorage("defaultAddress") var defaultAddress: String = "" { didSet { clearCenter(); regenerateIfNeeded() } }
    @AppStorage("locationMode") var locationModeRaw: String = "auto" { didSet { clearCenter(); regenerateIfNeeded() } }
    @AppStorage("defaultZoom") var zoom: Int = 14 { didSet { regenerateIfNeeded() } }
    @AppStorage("heatmapEnabled") var heatmapEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    @AppStorage("selectedTheme") var selectedThemeId: String = "cyberpunk" { didSet { regenerateIfNeeded() } }
    var locationMode: LocationMode {
        get { LocationMode(rawValue: locationModeRaw) ?? .auto }
        set { locationModeRaw = newValue.rawValue }
    }

    @Published var isGenerating = false
    @Published var progress: String = ""
    @Published var generatedImage: UIImage?
    @Published var lastError: String?
    @Published var locationString: String = "Locating..."
    @Published var showShareSheet = false
    @Published var rotation: Double = 0 // radians
    @Published var generationId: Int = 0 // incremented on each new render
    @Published var photoCount: Int = 0
    @Published var locationDenied = false
    @Published var photosDenied = false

    // Map center (set after first generate, updated by pan)
    private var centerLat: Double?
    private var centerLon: Double?
    // Original resolved location (for recenter)
    private var originalLat: Double?
    private var originalLon: Double?
    // Queued regeneration (if generate() called while already generating)
    private var pendingGenerate = false
    // Last HDR CIImage for saving
    private var lastCIImage: CIImage?

    var selectedTheme: MapTheme { Themes.byId(selectedThemeId) }

    var isPanned: Bool {
        guard let cLat = centerLat, let oLat = originalLat,
              let cLon = centerLon, let oLon = originalLon else { return false }
        return abs(cLat - oLat) > 0.0001 || abs(cLon - oLon) > 0.0001 || abs(rotation) > 0.01
    }

    private func clearCenter() {
        centerLat = nil
        centerLon = nil
        originalLat = nil
        originalLon = nil
    }

    private func regenerateIfNeeded() {
        if generatedImage != nil { generate() }
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

    /// Apply a pan offset (in screen points) and regenerate.
    func applyPan(dx: Double, dy: Double) {
        guard let lat = centerLat, let lon = centerLon else { return }

        let scale = Double(UIScreen.main.scale)
        // Rotate drag vector by -rotation so pan direction is correct when map is rotated
        let angle = -rotation
        let rdx = dx * cos(angle) - dy * sin(angle)
        let rdy = dx * sin(angle) + dy * cos(angle)

        let mapDx = rdx * scale
        let mapDy = rdy * scale

        let (cpx, cpy) = latLonToPixel(lat: lat, lon: lon, zoom: zoom)
        // Subtract: dragging right = map center moves left
        let (newLat, newLon) = pixelToLatLon(px: cpx - mapDx, py: cpy - mapDy, zoom: zoom)

        centerLat = newLat
        centerLon = newLon
        generate()
    }

    func recenter() {
        centerLat = originalLat
        centerLon = originalLon
        rotation = 0
        generate()
    }

    func generate() {
        guard !isGenerating else { pendingGenerate = true; return }
        isGenerating = true
        lastError = nil
        progress = "Loading photos..."
        LocationService.shared.ensureAuthorized()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Check permission states
            let locStatus = CLLocationManager().authorizationStatus
            DispatchQueue.main.async {
                self.locationDenied = (locStatus == .denied || locStatus == .restricted)
            }

            let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            DispatchQueue.main.async {
                self.photosDenied = (photoStatus == .denied || photoStatus == .restricted)
            }

            // Load photos
            var heatmapPoints: [LocationPoint]?
            let points = fetchPhotoLocations()
            DispatchQueue.main.async { self.photoCount = points.count }
            if heatmapEnabled && !points.isEmpty {
                heatmapPoints = points
            }

            // Resolve location (use cached center if available from pan)
            var lat: Double
            var lon: Double

            if let cLat = centerLat, let cLon = centerLon {
                // Already have a center from previous generate or pan
                lat = cLat; lon = cLon
            } else {
                DispatchQueue.main.async { self.progress = "Resolving location..." }

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

                // Store as both original and current center
                originalLat = lat; originalLon = lon
                centerLat = lat; centerLon = lon
                reverseGeocode(lat: lat, lon: lon)
            }

            // Always render at exact screen pixel size (1:1)
            var screenW = 1170, screenH = 2532
            DispatchQueue.main.sync {
                let bounds = UIScreen.main.bounds
                let scale = UIScreen.main.scale
                screenW = Int(bounds.width * scale)
                screenH = Int(bounds.height * scale)
            }

            DispatchQueue.main.async { self.progress = "Rendering wallpaper..." }

            let theme = selectedTheme
            let rot = self.rotation

            // Always generate HDR — encoded as 10-bit PQ HEIF on save
            guard let ciImage = generateMapImageHDR(
                lat: lat, lon: lon, zoom: zoom,
                width: screenW, height: screenH,
                heatmapPoints: heatmapPoints,
                theme: theme,
                intensity: 1.5,
                rotation: rot
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
            let uiImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async {
                self.generatedImage = uiImage
                self.lastCIImage = ciImage
                self.generationId += 1
                self.progress = "Done!"
                self.isGenerating = false
                if self.pendingGenerate {
                    self.pendingGenerate = false
                    self.generate()
                }
            }
        }
    }

    func saveToPhotos() {
        guard let ciImage = lastCIImage else { return }

        // Write HDR HEIF (10-bit PQ) to temp file, then add to photo library
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartogram_hdr_\(Int(Date().timeIntervalSince1970)).heic")
        guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else { return }
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        ])
        do {
            try ctx.writeHEIF10Representation(of: ciImage, to: tempURL, colorSpace: colorSpace)
        } catch {
            DispatchQueue.main.async { self.lastError = "Failed to encode HDR image" }
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
        } completionHandler: { success, error in
            try? FileManager.default.removeItem(at: tempURL)
            DispatchQueue.main.async {
                if success {
                    self.progress = "Saved to Photos!"
                } else {
                    self.lastError = error?.localizedDescription ?? "Failed to save"
                }
            }
        }
    }
}
