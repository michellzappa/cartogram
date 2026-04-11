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

final class GeneratorViewModel: ObservableObject {
    private static let freeZoomCap = 14

    @AppStorage("defaultAddress") var defaultAddress: String = "" { didSet { clearCenter(); regenerateIfNeeded() } }
    @AppStorage("locationMode") var locationModeRaw: String = "auto" { didSet { clearCenter(); regenerateIfNeeded() } }
    @AppStorage("defaultZoom") var zoom: Int = 14 { didSet { regenerateIfNeeded() } }
    @AppStorage("heatmapEnabled") var heatmapEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    @AppStorage("selectedTheme") var selectedThemeId: String = "cyberpunk" { didSet { regenerateIfNeeded() } }
    @AppStorage("hdrEnabled") var hdrEnabled: Bool = true { didSet { regenerateIfNeeded() } }
    @AppStorage("photoAlbumId") var photoAlbumId: String = "" {
        didSet {
            guard oldValue != photoAlbumId else { return }
            invalidatePhotoCache()
            cachedResolvedAlbumId = nil
            cachedResolvedAlbumTitle = nil
            clearCenter()
            regenerateIfNeeded()
        }
    }

    @Published var isGenerating = false
    @Published var progress: String = ""
    @Published var generatedImage: UIImage?
    @Published var lastError: String?
    @Published var locationString: String = "Locating..."
    @Published var rotation: Double = 0
    @Published var generationId: Int = 0
    @Published var photoCount: Int = 0
    @Published var locationDenied = false
    @Published var photosDenied = false

    var locationMode: LocationMode {
        get { LocationMode(rawValue: locationModeRaw) ?? .auto }
        set { locationModeRaw = newValue.rawValue }
    }

    var selectedTheme: MapTheme { Themes.byId(selectedThemeId) }

    var isPanned: Bool {
        guard let cLat = centerLat, let oLat = originalLat,
              let cLon = centerLon, let oLon = originalLon else { return false }
        return abs(cLat - oLat) > 0.0001 || abs(cLon - oLon) > 0.0001 || abs(rotation) > 0.01
    }

    private var centerLat: Double?
    private var centerLon: Double?
    private var originalLat: Double?
    private var originalLon: Double?
    private var pendingGenerate = false
    private var lastCIImage: CIImage?

    private let photoCacheLock = NSLock()
    private var cachedPhotoLocations: [LocationPoint]?
    private var cachedPhotoAuthorizationStatus: PHAuthorizationStatus?
    private var cachedPhotoAlbumId: String?

    private var cachedResolvedAlbumId: String?
    private var cachedResolvedAlbumTitle: String?

    var photoAlbumDisplayTitle: String {
        let id = photoAlbumId
        guard !id.isEmpty else { return "All Photos" }
        if let cachedId = cachedResolvedAlbumId, cachedId == id, let title = cachedResolvedAlbumTitle {
            return title
        }
        let title = photoAlbumTitle(forLocalIdentifier: id) ?? "All Photos"
        cachedResolvedAlbumId = id
        cachedResolvedAlbumTitle = title
        return title
    }

    private func invalidatePhotoCache() {
        photoCacheLock.lock()
        cachedPhotoLocations = nil
        cachedPhotoAuthorizationStatus = nil
        cachedPhotoAlbumId = nil
        photoCacheLock.unlock()
    }

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
        let rotation: Double
        let center: (lat: Double, lon: Double)?
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

    private func makeResolveSnapshot() -> ResolveSnapshot {
        ResolveSnapshot(
            defaultAddress: defaultAddress,
            locationMode: locationMode
        )
    }

    private func makeRenderSnapshot() -> RenderSnapshot {
        let isPro = StoreManager.cachedProStatus()
        let theme = selectedTheme.isPro && !isPro ? Themes.cyberpunk : selectedTheme

        return RenderSnapshot(
            defaultAddress: defaultAddress,
            locationMode: locationMode,
            zoom: isPro ? zoom : min(zoom, Self.freeZoomCap),
            heatmapEnabled: heatmapEnabled,
            selectedTheme: theme,
            hdrEnabled: isPro && hdrEnabled,
            rotation: rotation,
            center: centerLat.flatMap { lat in
                centerLon.map { lon in (lat: lat, lon: lon) }
            }
        )
    }

    func resolveLocation() {
        let snapshot = makeResolveSnapshot()

        LocationService.shared.ensureAuthorized()
        updatePermissionStates()

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

    func applyPan(dx: Double, dy: Double) {
        guard let lat = centerLat, let lon = centerLon else { return }

        let scale = Double(UIScreen.main.scale)
        let angle = -rotation
        let rotatedDx = dx * cos(angle) - dy * sin(angle)
        let rotatedDy = dx * sin(angle) + dy * cos(angle)

        let mapDx = rotatedDx * scale
        let mapDy = rotatedDy * scale

        let (currentPx, currentPy) = latLonToPixel(lat: lat, lon: lon, zoom: zoom)
        let (newLat, newLon) = pixelToLatLon(px: currentPx - mapDx, py: currentPy - mapDy, zoom: zoom)

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
        guard !isGenerating else {
            pendingGenerate = true
            return
        }

        let snapshot = makeRenderSnapshot()

        isGenerating = true
        lastError = nil
        progress = "Loading photos..."

        LocationService.shared.ensureAuthorized()
        updatePermissionStates()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let points = photoLocations()
            let heatmapPoints = snapshot.heatmapEnabled && !points.isEmpty ? points : nil

            var lat: Double
            var lon: Double

            if let center = snapshot.center {
                lat = center.lat
                lon = center.lon
            } else {
                DispatchQueue.main.async { self.progress = "Resolving location..." }

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
                            self.locationDenied = true
                            self.isGenerating = false
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

                DispatchQueue.main.async {
                    self.storeResolvedCenter(lat: lat, lon: lon)
                }
                reverseGeocode(lat: lat, lon: lon)
            }

            var screenWidth = 1170
            var screenHeight = 2532
            DispatchQueue.main.sync {
                let bounds = UIScreen.main.bounds
                let scale = UIScreen.main.scale
                screenWidth = Int(bounds.width * scale)
                screenHeight = Int(bounds.height * scale)
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
                    theme: snapshot.selectedTheme,
                    intensity: 1.5,
                    rotation: snapshot.rotation
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

                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.finishGeneration(image: image, ciImage: ciImage)
                }
            } else {
                guard let cgImage = generateMapImage(
                    lat: lat,
                    lon: lon,
                    zoom: snapshot.zoom,
                    width: screenWidth,
                    height: screenHeight,
                    heatmapPoints: heatmapPoints,
                    theme: snapshot.selectedTheme,
                    intensity: 1.5,
                    rotation: snapshot.rotation
                ) else {
                    DispatchQueue.main.async {
                        self.failGeneration("Failed to generate wallpaper")
                    }
                    return
                }

                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.finishGeneration(image: image, ciImage: nil)
                }
            }
        }
    }

    func saveToPhotos() {
        if StoreManager.cachedProStatus(), hdrEnabled, let ciImage = lastCIImage {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cartogram_hdr_\(Int(Date().timeIntervalSince1970)).heic")

            guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else { return }

            let context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            ])

            do {
                try context.writeHEIF10Representation(of: ciImage, to: tempURL, colorSpace: colorSpace)
            } catch {
                lastError = "Failed to encode HDR image"
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
        } else if let image = generatedImage {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
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

    private func storeResolvedCenter(lat: Double, lon: Double) {
        originalLat = lat
        originalLon = lon
        centerLat = lat
        centerLon = lon
    }

    private func finishGeneration(image: UIImage, ciImage: CIImage?) {
        generatedImage = image
        lastCIImage = ciImage
        generationId += 1
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

    private func updatePermissionStates() {
        let locationStatus = CLLocationManager().authorizationStatus
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        locationDenied = locationStatus == .denied || locationStatus == .restricted
        photosDenied = photoStatus == .denied || photoStatus == .restricted
    }

    private func photoLocations(forceRefresh: Bool = false) -> [LocationPoint] {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let albumId = photoAlbumId

        photoCacheLock.lock()
        if !forceRefresh,
           let cachedPhotoLocations,
           cachedPhotoAuthorizationStatus == currentStatus,
           cachedPhotoAlbumId == albumId {
            photoCacheLock.unlock()
            DispatchQueue.main.async {
                self.photoCount = cachedPhotoLocations.count
                self.photosDenied = currentStatus == .denied || currentStatus == .restricted
            }
            return cachedPhotoLocations
        }
        photoCacheLock.unlock()

        let points = fetchPhotoLocations(albumLocalIdentifier: albumId.isEmpty ? nil : albumId)
        let resolvedStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        photoCacheLock.lock()
        cachedPhotoLocations = points
        cachedPhotoAuthorizationStatus = resolvedStatus
        cachedPhotoAlbumId = albumId
        photoCacheLock.unlock()

        DispatchQueue.main.async {
            self.photoCount = points.count
            self.photosDenied = resolvedStatus == .denied || resolvedStatus == .restricted
        }

        return points
    }
}
