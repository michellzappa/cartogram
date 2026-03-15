import Foundation
import CoreGraphics
import CoreLocation
import ImageIO
import Photos

// MARK: - Configuration

public struct Config {
    public var lat: Double?
    public var lon: Double?
    public var address: String?
    public var zoom: Int = 14
    public var heatmap: Bool = true
    public var help: Bool = false

    public static let tileSize = 512 // rendered tile size
    public static let maxTileZoom = 14 // OpenFreeMap max zoom
    private static let tileJSONURL = "https://tiles.openfreemap.org/planet"

    /// Resolved tile URL template from OpenFreeMap TileJSON (cached after first fetch)
    private static var _resolvedTileURL: String?
    private static let tileURLLock = NSLock()

    public static var vectorTileURL: String {
        tileURLLock.lock()
        defer { tileURLLock.unlock() }
        if let cached = _resolvedTileURL { return cached }

        // Fetch TileJSON to get versioned tile URL
        if let url = URL(string: tileJSONURL) {
            let sem = DispatchSemaphore(value: 0)
            var template: String?
            URLSession.shared.dataTask(with: url) { data, _, _ in
                defer { sem.signal() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tiles = json["tiles"] as? [String],
                      let first = tiles.first else { return }
                // Convert {z}/{x}/{y} to %d/%d/%d for String(format:)
                template = first
                    .replacingOccurrences(of: "{z}", with: "%d")
                    .replacingOccurrences(of: "{x}", with: "%d")
                    .replacingOccurrences(of: "{y}", with: "%d")
            }.resume()
            _ = sem.wait(timeout: .now() + 10)
            if let t = template {
                _resolvedTileURL = t
                #if DEBUG
                print("  Tile URL: \(t)")
                #endif
                return t
            }
        }

        // Fallback
        let fallback = "https://tiles.openfreemap.org/planet/20260311_001001_pt/%d/%d/%d.pbf"
        _resolvedTileURL = fallback
        return fallback
    }

    public init() {}
}

// MARK: - Data

public struct LocationPoint {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

// MARK: - Location

/// Retained singleton so macOS remembers location authorization across launches.
public class LocationService: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationService()

    private let mgr = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    private var fetching = false

    private override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Pre-request authorization so the OS prompt appears early.
    public func ensureAuthorized() {
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        }
    }

    public func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard fetching, let loc = l.last else { return }
        fetching = false
        m.stopUpdatingLocation()
        completion?(loc)
        completion = nil
    }

    public func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        guard fetching else { return }
        fputs("  CoreLocation error: \(e.localizedDescription)\n", stderr)
        fetching = false
        mgr.stopUpdatingLocation()
        completion?(nil)
        completion = nil
    }

    public func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        // Only act on auth changes during an active fetch
        guard fetching else { return }
        let s = m.authorizationStatus
        if s == .denied || s == .restricted {
            fetching = false
            completion?(nil)
            completion = nil
        } else if s != .notDetermined {
            m.startUpdatingLocation()
        }
    }

    /// Request a single location fix. Must be called from the main thread.
    private func requestLocation(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        self.fetching = true

        let status = mgr.authorizationStatus
        if status == .notDetermined {
            mgr.requestWhenInUseAuthorization()
            // locationManagerDidChangeAuthorization will call startUpdatingLocation
        } else if status != .denied && status != .restricted {
            mgr.startUpdatingLocation()
        } else {
            fputs("  Location access denied (status: \(status.rawValue)).\n", stderr)
            self.fetching = false
            completion(nil)
            self.completion = nil
        }

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.fetching else { return }
            self.fetching = false
            self.mgr.stopUpdatingLocation()
            self.completion?(nil)
            self.completion = nil
        }
    }

    /// Synchronous wrapper for use from background threads.
    func fetch() -> (Double, Double)? {
        if Thread.isMainThread {
            // CLI path: spin RunLoop
            var loc: CLLocation?
            var finished = false
            requestLocation { result in
                loc = result
                finished = true
            }
            let deadline = Date(timeIntervalSinceNow: 15)
            while !finished && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
            guard let l = loc else { return nil }
            return (l.coordinate.latitude, l.coordinate.longitude)
        } else {
            // GUI path: dispatch to main, block on semaphore
            let sem = DispatchSemaphore(value: 0)
            var loc: CLLocation?

            DispatchQueue.main.async { [self] in
                requestLocation { result in
                    loc = result
                    sem.signal()
                }
            }

            _ = sem.wait(timeout: .now() + 15)
            guard let l = loc else { return nil }
            return (l.coordinate.latitude, l.coordinate.longitude)
        }
    }
}

public func getCoreLocation() -> (Double, Double)? {
    LocationService.shared.fetch()
}

public func geocodeAddress(_ address: String) -> (Double, Double)? {
    let sem = DispatchSemaphore(value: 0)
    var result: (Double, Double)?

    CLGeocoder().geocodeAddressString(address) { placemarks, error in
        if let loc = placemarks?.first?.location {
            if let name = placemarks?.first?.name {
                #if DEBUG
                print("  Resolved: \(name)")
                #endif
            }
            result = (loc.coordinate.latitude, loc.coordinate.longitude)
        } else if let error = error {
            #if DEBUG
            print("  Geocoding error: \(error.localizedDescription)")
            #endif
        }
        sem.signal()
    }

    _ = sem.wait(timeout: .now() + 10)
    return result
}

// MARK: - Tile Math

public func tileCoords(lat: Double, lon: Double, zoom: Int) -> (tx: Int, ty: Int, fx: Double, fy: Double) {
    let n = pow(2.0, Double(zoom))
    let x = (lon + 180.0) / 360.0 * n
    let r = lat * .pi / 180.0
    let y = (1.0 - log(tan(r) + 1.0 / cos(r)) / .pi) / 2.0 * n
    return (Int(floor(x)), Int(floor(y)), x - floor(x), y - floor(y))
}

public func latLonToPixel(lat: Double, lon: Double, zoom: Int) -> (Double, Double) {
    let n = pow(2.0, Double(zoom))
    let ts = Double(Config.tileSize)
    let px = (lon + 180.0) / 360.0 * n * ts
    let r = lat * .pi / 180.0
    let py = (1.0 - log(tan(r) + 1.0 / cos(r)) / .pi) / 2.0 * n * ts
    return (px, py)
}

public func pixelToLatLon(px: Double, py: Double, zoom: Int) -> (lat: Double, lon: Double) {
    let n = pow(2.0, Double(zoom))
    let ts = Double(Config.tileSize)
    let lon = px / (n * ts) * 360.0 - 180.0
    let latRad = atan(sinh(.pi * (1.0 - 2.0 * py / (n * ts))))
    let lat = latRad * 180.0 / .pi
    return (lat, lon)
}

// MARK: - Tile Fetching

public func tileCacheDir() -> URL {
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("com.centaur-labs.cartogram")
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    return cache
}

/// Fetch a PBF vector tile from disk cache or network.
func fetchPBF(x: Int, y: Int, zoom: Int) -> Data? {
    let urlStr = String(format: Config.vectorTileURL, zoom, x, y)
    guard let url = URL(string: urlStr) else {
        #if DEBUG
        print("  [PBF] Bad URL: \(urlStr)")
        #endif
        return nil
    }

    let cacheFile = tileCacheDir().appendingPathComponent("pbf_\(zoom)_\(x)_\(y).pbf")
    if let cached = try? Data(contentsOf: cacheFile), !cached.isEmpty {
        return cached
    }

    var req = URLRequest(url: url)
    req.setValue("Cartogram/1.0", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 15

    var result: Data?
    let sem = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: req) { data, response, error in
        defer { sem.signal() }
        if let error = error {
            #if DEBUG
            print("  [PBF] Fetch error \(x),\(y): \(error.localizedDescription)")
            #endif
            return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            #if DEBUG
            print("  [PBF] HTTP \(http.statusCode) for \(x),\(y)")
            #endif
            return
        }
        guard let data = data, !data.isEmpty else {
            #if DEBUG
            print("  [PBF] Empty data for \(x),\(y)")
            #endif
            return
        }
        try? data.write(to: cacheFile)
        result = data
    }.resume()

    _ = sem.wait(timeout: .now() + 20)
    return result
}

/// Fetch a vector tile, render it with the given style, and return as CGImage.
/// Supports overzooming: for zoom > maxTileZoom, fetches the parent tile at
/// maxTileZoom and crops/scales the relevant quadrant.
public func fetchTile(x: Int, y: Int, zoom: Int, style: MapLayerStyle) -> CGImage? {
    let maxZ = Config.maxTileZoom
    if zoom <= maxZ {
        guard let pbf = fetchPBF(x: x, y: y, zoom: zoom) else { return nil }
        return renderVectorTile(data: pbf, tileSize: Config.tileSize, style: style, zoom: zoom)
    }

    // Overzoom: find the ancestor tile at maxTileZoom
    let dz = zoom - maxZ
    let scale = 1 << dz  // 2^dz
    let parentX = x / scale
    let parentY = y / scale

    // Render parent tile at scale * tileSize for detail
    let renderSize = Config.tileSize * scale
    guard let pbf = fetchPBF(x: parentX, y: parentY, zoom: maxZ) else { return nil }
    guard let big = renderVectorTile(data: pbf, tileSize: renderSize, style: style, zoom: maxZ) else { return nil }

    // Crop the sub-tile region
    let subX = x % scale
    let subY = y % scale
    let ts = Config.tileSize
    let cropRect = CGRect(x: subX * ts, y: subY * ts, width: ts, height: ts)
    return big.cropping(to: cropRect)
}

// MARK: - Debug Log

private func debugLog(_ msg: String) {
    #if DEBUG
    print("  [Cartogram] \(msg)")
    #endif
}

// MARK: - PhotoKit

public func fetchPhotoLocations() -> [LocationPoint] {
    let sem = DispatchSemaphore(value: 0)

    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    debugLog("Photos auth status: \(status.rawValue)")
    if status == .notDetermined {
        debugLog("Requesting Photos authorization...")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
            debugLog("Authorization callback: \(newStatus.rawValue)")
            sem.signal()
        }
        sem.wait()
    }

    let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    debugLog("Final Photos auth status: \(authStatus.rawValue)")
    guard authStatus == .authorized || authStatus == .limited else {
        debugLog("Photos access DENIED")
        #if DEBUG
        print("  Photos access denied (status=\(authStatus.rawValue)). Grant access in System Settings → Privacy & Security → Photos")
        #endif
        return []
    }

    let opts = PHFetchOptions()
    opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    let assets = PHAsset.fetchAssets(with: .image, options: opts)
    var points: [LocationPoint] = []

    assets.enumerateObjects { asset, _, _ in
        guard let loc = asset.location else { return }
        let coord = loc.coordinate
        guard coord.latitude != 0 || coord.longitude != 0 else { return }
        guard abs(coord.latitude) <= 90 && abs(coord.longitude) <= 180 else { return }
        points.append(LocationPoint(lat: coord.latitude, lon: coord.longitude))
    }

    #if DEBUG
    print("  Found \(points.count) geotagged photos via PhotoKit")
    #endif
    return points
}

// MARK: - Heatmap Rendering

public func drawHeatmap(on ctx: CGContext, points: [LocationPoint],
                        zoom: Int, ox: Double, oy: Double, w: Int, h: Int,
                        palette: HeatmapPalette = Themes.cyberpunk.heatmap,
                        blend: HeatmapBlend = .screen,
                        intensity: Float = 1.0,
                        rotation: Double = 0,
                        centerPx: Double = 0, centerPy: Double = 0) {
    var pixelPoints: [(x: Double, y: Double)] = []
    if rotation != 0 {
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        let hw = Double(w) / 2.0
        let hh = Double(h) / 2.0
        for p in points {
            let (px, py) = latLonToPixel(lat: p.lat, lon: p.lon, zoom: zoom)
            let dx = px - centerPx
            let dy = py - centerPy
            let x = dx * cosR - dy * sinR + hw
            let y = dx * sinR + dy * cosR + hh
            if x >= 0 && x < Double(w) && y >= 0 && y < Double(h) {
                pixelPoints.append((x, y))
            }
        }
    } else {
        for p in points {
            let (px, py) = latLonToPixel(lat: p.lat, lon: p.lon, zoom: zoom)
            let x = px - ox
            let y = py - oy
            if x >= 0 && x < Double(w) && y >= 0 && y < Double(h) {
                pixelPoints.append((x, y))
            }
        }
    }

    #if DEBUG
    print("  \(pixelPoints.count) points visible in viewport")
    #endif
    if pixelPoints.isEmpty { return }

    let cellSize = max(4, min(12, 10 - (zoom - 14)))
    let gw = (w + cellSize - 1) / cellSize
    let gh = (h + cellSize - 1) / cellSize
    var grid = [Int](repeating: 0, count: gw * gh)

    for p in pixelPoints {
        let gx = Int(p.x) / cellSize
        let gy = Int(p.y) / cellSize
        guard gx >= 0 && gx < gw && gy >= 0 && gy < gh else { continue }
        grid[gy * gw + gx] += 1
    }

    let maxCount = grid.max() ?? 1
    guard maxCount > 0 else { return }
    let logMax = log(Float(maxCount) + 1)

    var heatBuf = [UInt8](repeating: 0, count: w * h * 4)

    for gy in 0..<gh {
        for gx in 0..<gw {
            let count = grid[gy * gw + gx]
            guard count > 0 else { continue }

            let t = log(Float(count) + 1) / logMax

            // Interpolate across three palette stops: dim → mid → bright
            let r: Float, g: Float, b: Float, a: Float
            let d = palette.dim, m = palette.mid, br = palette.bright

            if t < 0.5 {
                let s = t / 0.5
                r = d.r + (m.r - d.r) * s
                g = d.g + (m.g - d.g) * s
                b = d.b + (m.b - d.b) * s
                a = d.a + (m.a - d.a) * s
            } else {
                let s = (t - 0.5) / 0.5
                r = m.r + (br.r - m.r) * s
                g = m.g + (br.g - m.g) * s
                b = m.b + (br.b - m.b) * s
                a = m.a + (br.a - m.a) * s
            }

            let ai = min(a * intensity, 1.0)

            let x0 = gx * cellSize
            let y0 = gy * cellSize
            let x1 = min(x0 + cellSize - 1, w)
            let y1 = min(y0 + cellSize - 1, h)

            for py in y0..<y1 {
                for px in x0..<x1 {
                    let pidx = (py * w + px) * 4
                    heatBuf[pidx + 0] = UInt8(min(255, r * ai * 255))
                    heatBuf[pidx + 1] = UInt8(min(255, g * ai * 255))
                    heatBuf[pidx + 2] = UInt8(min(255, b * ai * 255))
                    heatBuf[pidx + 3] = UInt8(min(255, ai * 255))
                }
            }
        }
    }

    heatBuf.withUnsafeMutableBytes { ptr in
        guard let baseAddr = ptr.baseAddress else { return }
        if let heatCtx = CGContext(
            data: baseAddr, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let heatImg = heatCtx.makeImage() {
            ctx.saveGState()
            ctx.setBlendMode(blend.cgBlendMode)
            ctx.draw(heatImg, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
        }
    }
}

// MARK: - Wallpaper Generation (cross-platform core)

public func generateMapImage(lat: Double, lon: Double, zoom: Int,
                             width w: Int, height h: Int,
                             heatmapPoints: [LocationPoint]?,
                             theme: MapTheme = Themes.cyberpunk,
                             intensity: Float = 1.0,
                             rotation: Double = 0) -> CGImage? {
    let ts = Config.tileSize

    let (tx, ty, fx, fy) = tileCoords(lat: lat, lon: lon, zoom: zoom)

    // Center pixel in world coordinates
    let cx = (Double(tx) + fx) * Double(ts)
    let cy = (Double(ty) + fy) * Double(ts)

    // When rotated, we need a larger area of tiles to fill the screen
    let diag = sqrt(Double(w * w + h * h))
    let renderW = rotation == 0 ? w : Int(ceil(diag))
    let renderH = rotation == 0 ? h : Int(ceil(diag))

    let ox = cx - Double(renderW) / 2.0
    let oy = cy - Double(renderH) / 2.0

    let sx = Int(floor(ox / Double(ts)))
    let sy = Int(floor(oy / Double(ts)))
    let ex = Int(floor((ox + Double(renderW) - 1) / Double(ts)))
    let ey = Int(floor((oy + Double(renderH) - 1) / Double(ts)))
    let total = (ex - sx + 1) * (ey - sy + 1)

    #if DEBUG
    print("  Fetching \(total) tiles...")
    #endif

    var tiles: [String: CGImage] = [:]
    let lock = NSLock()
    let group = DispatchGroup()

    for y in sy...ey {
        for x in sx...ex {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                if let img = fetchTile(x: x, y: y, zoom: zoom, style: theme.mapStyle) {
                    lock.lock()
                    tiles["\(x),\(y)"] = img
                    lock.unlock()
                }
            }
        }
    }
    group.wait()

    if tiles.count < total {
        #if DEBUG
        print("  Warning: \(total - tiles.count) tiles failed to download")
        #endif
    }
    #if DEBUG
    print("  Got \(tiles.count)/\(total) tiles")
    #endif

    // Render tiles (possibly oversized if rotated)
    guard let tileCtx = CGContext(
        data: nil, width: renderW, height: renderH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        #if DEBUG
        print("Error: Failed to create graphics context")
        #endif
        return nil
    }

    tileCtx.setFillColor(CGColor(red: theme.bgColor.r, green: theme.bgColor.g, blue: theme.bgColor.b, alpha: 1))
    tileCtx.fill(CGRect(x: 0, y: 0, width: renderW, height: renderH))

    for y in sy...ey {
        for x in sx...ex {
            guard let tile = tiles["\(x),\(y)"] else { continue }
            let dx = floor(Double(x * ts) - ox)
            let dy = floor(Double(renderH) - (Double(y * ts) - oy) - Double(ts))
            tileCtx.draw(tile, in: CGRect(x: dx, y: dy, width: Double(ts) + 1, height: Double(ts) + 1))
        }
    }

    if rotation == 0 {
        // No rotation: draw heatmap directly and return
        if let points = heatmapPoints, !points.isEmpty {
            #if DEBUG
            print("  Rendering heatmap...")
            #endif
            drawHeatmap(on: tileCtx, points: points, zoom: zoom, ox: ox, oy: oy, w: w, h: h, palette: theme.heatmap, blend: theme.blend, intensity: intensity)
        }
        return tileCtx.makeImage()
    }

    // Rotated path: compose rotated tiles into screen-size context
    guard let tileImage = tileCtx.makeImage() else { return nil }

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(red: theme.bgColor.r, green: theme.bgColor.g, blue: theme.bgColor.b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Rotate tiles around screen center
    // CGContext y-axis is flipped (up), so negate rotation for clockwise screen rotation
    ctx.saveGState()
    ctx.translateBy(x: Double(w) / 2.0, y: Double(h) / 2.0)
    ctx.rotate(by: -rotation)
    ctx.translateBy(x: -Double(renderW) / 2.0, y: -Double(renderH) / 2.0)
    ctx.draw(tileImage, in: CGRect(x: 0, y: 0, width: renderW, height: renderH))
    ctx.restoreGState()

    // Heatmap at 1:1 screen pixels with rotation-aware coordinates
    if let points = heatmapPoints, !points.isEmpty {
        #if DEBUG
        print("  Rendering heatmap...")
        #endif
        drawHeatmap(on: ctx, points: points, zoom: zoom, ox: ox, oy: oy, w: w, h: h,
                    palette: theme.heatmap, blend: theme.blend, intensity: intensity,
                    rotation: rotation, centerPx: cx, centerPy: cy)
    }

    return ctx.makeImage()
}

// MARK: - Auto-center

public func findDensestCluster(in points: [LocationPoint]) -> (lat: Double, lon: Double, count: Int)? {
    let gridRes = 0.002  // ~200m cells
    var cells: [String: (count: Int, latSum: Double, lonSum: Double)] = [:]
    for p in points {
        let key = "\(Int(p.lat / gridRes)),\(Int(p.lon / gridRes))"
        var cell = cells[key] ?? (0, 0, 0)
        cell.count += 1
        cell.latSum += p.lat
        cell.lonSum += p.lon
        cells[key] = cell
    }
    guard let best = cells.values.max(by: { $0.count < $1.count }) else { return nil }
    return (best.latSum / Double(best.count), best.lonSum / Double(best.count), best.count)
}
