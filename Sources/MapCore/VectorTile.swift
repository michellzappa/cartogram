import Foundation
import CoreGraphics
import Compression

// MARK: - Minimal Protobuf Reader

struct PBReader {
    private let data: Data
    private var pos: Int = 0

    init(data: Data) { self.data = data }

    var hasMore: Bool { pos < data.count }

    mutating func readVarint() -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while pos < data.count {
            let byte = UInt64(data[pos])
            pos += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    mutating func readTag() -> (field: Int, wire: Int)? {
        guard hasMore else { return nil }
        let v = readVarint()
        return (Int(v >> 3), Int(v & 0x7))
    }

    mutating func readBytes() -> Data {
        let len = Int(readVarint())
        let end = min(pos + len, data.count)
        let result = data[pos..<end]
        pos = end
        return Data(result)
    }

    mutating func readString() -> String {
        String(data: readBytes(), encoding: .utf8) ?? ""
    }

    mutating func readPackedUInt32() -> [UInt32] {
        let bytes = readBytes()
        var sub = PBReader(data: bytes)
        var arr: [UInt32] = []
        while sub.hasMore { arr.append(UInt32(sub.readVarint())) }
        return arr
    }

    mutating func readFloat() -> Float {
        guard pos + 4 <= data.count else { return 0 }
        let val = data[pos..<pos+4].withUnsafeBytes { $0.load(as: Float.self) }
        pos += 4
        return val
    }

    mutating func readDouble() -> Double {
        guard pos + 8 <= data.count else { return 0 }
        let val = data[pos..<pos+8].withUnsafeBytes { $0.load(as: Double.self) }
        pos += 8
        return val
    }

    mutating func skip(wire: Int) {
        switch wire {
        case 0: _ = readVarint()
        case 1: pos += 8
        case 2: let len = Int(readVarint()); pos += len
        case 5: pos += 4
        default: break
        }
    }
}

// MARK: - MVT Types

enum GeomType: UInt32 { case unknown = 0, point = 1, linestring = 2, polygon = 3 }

struct VTFeature {
    let type: GeomType
    let tags: [UInt32]
    let geometry: [UInt32]
}

struct VTLayer {
    let name: String
    let extent: UInt32
    let features: [VTFeature]
    let keys: [String]
    let values: [VTValue]
}

enum VTValue {
    case string(String), float(Float), double(Double)
    case int(Int64), uint(UInt64), sint(Int64), bool(Bool)

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - MVT Parsing

func parseMVT(data: Data) -> [VTLayer] {
    var r = PBReader(data: data)
    var layers: [VTLayer] = []
    while let tag = r.readTag() {
        if tag.field == 3 && tag.wire == 2 {
            if let layer = parseLayer(data: r.readBytes()) { layers.append(layer) }
        } else { r.skip(wire: tag.wire) }
    }
    return layers
}

private func parseLayer(data: Data) -> VTLayer? {
    var r = PBReader(data: data)
    var name = ""; var extent: UInt32 = 4096
    var features: [VTFeature] = []; var keys: [String] = []; var values: [VTValue] = []

    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): name = r.readString()
        case (2, 2): if let f = parseFeature(data: r.readBytes()) { features.append(f) }
        case (3, 2): keys.append(r.readString())
        case (4, 2): values.append(parseValue(data: r.readBytes()))
        case (5, 0): extent = UInt32(r.readVarint())
        default: r.skip(wire: tag.wire)
        }
    }
    return VTLayer(name: name, extent: extent, features: features, keys: keys, values: values)
}

private func parseFeature(data: Data) -> VTFeature? {
    var r = PBReader(data: data)
    var type: GeomType = .unknown; var tags: [UInt32] = []; var geometry: [UInt32] = []

    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 0): _ = r.readVarint()  // id
        case (2, 2): tags = r.readPackedUInt32()
        case (3, 0): type = GeomType(rawValue: UInt32(r.readVarint())) ?? .unknown
        case (4, 2): geometry = r.readPackedUInt32()
        default: r.skip(wire: tag.wire)
        }
    }
    return VTFeature(type: type, tags: tags, geometry: geometry)
}

private func parseValue(data: Data) -> VTValue {
    var r = PBReader(data: data)
    var result: VTValue = .string("")
    while let tag = r.readTag() {
        switch (tag.field, tag.wire) {
        case (1, 2): result = .string(r.readString())
        case (2, 5): result = .float(r.readFloat())
        case (3, 1): result = .double(r.readDouble())
        case (4, 0): result = .int(Int64(bitPattern: r.readVarint()))
        case (5, 0): result = .uint(r.readVarint())
        case (6, 0):
            let v = r.readVarint()
            result = .sint(Int64(v >> 1) ^ -(Int64(v) & 1))
        case (7, 0): result = .bool(r.readVarint() != 0)
        default: r.skip(wire: tag.wire)
        }
    }
    return result
}

// MARK: - Geometry Decoding

private func zigzag(_ n: UInt32) -> Int32 {
    Int32(n >> 1) ^ -(Int32(n & 1))
}

func decodeGeometry(commands: [UInt32], extent: UInt32, tileSize: CGFloat) -> [[CGPoint]] {
    let scale = tileSize / CGFloat(extent)
    var rings: [[CGPoint]] = []
    var ring: [CGPoint] = []
    var cx: Int32 = 0, cy: Int32 = 0
    var i = 0

    while i < commands.count {
        let cmd = commands[i]; i += 1
        let id = cmd & 0x7, count = Int(cmd >> 3)

        switch id {
        case 1: // MoveTo
            if !ring.isEmpty { rings.append(ring); ring = [] }
            for _ in 0..<count {
                guard i + 1 < commands.count else { break }
                cx += zigzag(commands[i]); cy += zigzag(commands[i + 1]); i += 2
                ring.append(CGPoint(x: CGFloat(cx) * scale, y: CGFloat(cy) * scale))
            }
        case 2: // LineTo
            for _ in 0..<count {
                guard i + 1 < commands.count else { break }
                cx += zigzag(commands[i]); cy += zigzag(commands[i + 1]); i += 2
                ring.append(CGPoint(x: CGFloat(cx) * scale, y: CGFloat(cy) * scale))
            }
        case 7: // ClosePath
            if let first = ring.first { ring.append(first) }
            rings.append(ring); ring = []
        default: break
        }
    }
    if !ring.isEmpty { rings.append(ring) }
    return rings
}

// MARK: - Map Layer Style

public struct MapLayerStyle {
    public let background: (r: CGFloat, g: CGFloat, b: CGFloat)
    public let water: (r: CGFloat, g: CGFloat, b: CGFloat)
    public let waterway: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let land: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let park: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let building: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let roadMajor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let roadMinor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    public let roadMajorWidth: CGFloat
    public let roadMinorWidth: CGFloat

    public init(
        background: (r: CGFloat, g: CGFloat, b: CGFloat),
        water: (r: CGFloat, g: CGFloat, b: CGFloat),
        waterway: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        land: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        park: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        building: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        roadMajor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        roadMinor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        roadMajorWidth: CGFloat = 2.0,
        roadMinorWidth: CGFloat = 1.0
    ) {
        self.background = background; self.water = water; self.waterway = waterway
        self.land = land; self.park = park; self.building = building
        self.roadMajor = roadMajor; self.roadMinor = roadMinor
        self.roadMajorWidth = roadMajorWidth; self.roadMinorWidth = roadMinorWidth
    }
}

// MARK: - Gzip Decompression

func decompressIfNeeded(_ data: Data) -> Data {
    guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else { return data }

    // Strip gzip header to get raw deflate stream
    var offset = 10
    guard data.count > 18 else { return data }
    let flags = data[3]
    if flags & 0x04 != 0 { // FEXTRA
        guard offset + 2 <= data.count else { return data }
        let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
        offset += 2 + xlen
    }
    if flags & 0x08 != 0 { while offset < data.count && data[offset] != 0 { offset += 1 }; offset += 1 }
    if flags & 0x10 != 0 { while offset < data.count && data[offset] != 0 { offset += 1 }; offset += 1 }
    if flags & 0x02 != 0 { offset += 2 }

    let compressed = data.subdata(in: offset..<(data.count - 8))
    let bufSize = max(compressed.count * 20, 512 * 1024)
    var buf = [UInt8](repeating: 0, count: bufSize)

    let result = compressed.withUnsafeBytes { ptr -> Int in
        guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        return compression_decode_buffer(&buf, bufSize, base, compressed.count, nil, COMPRESSION_ZLIB)
    }

    guard result > 0 else { return data }
    return Data(buf.prefix(result))
}

// MARK: - Vector Tile Renderer

private func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

public func renderVectorTile(data: Data, tileSize: Int, style: MapLayerStyle, zoom: Int) -> CGImage? {
    let raw = decompressIfNeeded(data)
    #if DEBUG
    if raw.count < 10 {
        print("  [VT] Decompressed data too small: \(raw.count) bytes (input: \(data.count) bytes)")
    }
    #endif
    let layers = parseMVT(data: raw)
    #if DEBUG
    if layers.isEmpty {
        print("  [VT] No layers parsed from \(raw.count) bytes")
    }
    #endif
    let ts = CGFloat(tileSize)

    guard let ctx = CGContext(
        data: nil, width: tileSize, height: tileSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Flip y-axis so MVT coordinates (y-down) match
    ctx.translateBy(x: 0, y: ts)
    ctx.scaleBy(x: 1, y: -1)

    // Background
    let bg = style.background
    ctx.setFillColor(cgColor(bg.r, bg.g, bg.b))
    ctx.fill(CGRect(x: 0, y: 0, width: ts, height: ts))

    let layerMap = Dictionary(layers.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    // Water polygons
    if let layer = layerMap["water"] {
        let c = style.water
        ctx.setFillColor(cgColor(c.r, c.g, c.b))
        drawPolygons(ctx: ctx, layer: layer, tileSize: ts)
    }

    // Waterway lines
    if let layer = layerMap["waterway"] {
        let c = style.waterway
        ctx.setStrokeColor(cgColor(c.r, c.g, c.b, c.a))
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        drawLines(ctx: ctx, layer: layer, tileSize: ts)
    }

    // Landcover
    if let layer = layerMap["landcover"] {
        let c = style.land
        ctx.setFillColor(cgColor(c.r, c.g, c.b, c.a))
        drawPolygons(ctx: ctx, layer: layer, tileSize: ts)
    }

    // Landuse (parks get special color)
    if let layer = layerMap["landuse"] {
        drawLanduse(ctx: ctx, layer: layer, tileSize: ts, style: style)
    }

    // Park
    if let layer = layerMap["park"] {
        let c = style.park
        ctx.setFillColor(cgColor(c.r, c.g, c.b, c.a))
        drawPolygons(ctx: ctx, layer: layer, tileSize: ts)
    }

    // Buildings
    if let layer = layerMap["building"] {
        let c = style.building
        ctx.setFillColor(cgColor(c.r, c.g, c.b, c.a))
        drawPolygons(ctx: ctx, layer: layer, tileSize: ts)
    }

    // Transportation (roads)
    if let layer = layerMap["transportation"] {
        drawRoads(ctx: ctx, layer: layer, tileSize: ts, style: style, zoom: zoom)
    }

    return ctx.makeImage()
}

// MARK: - Drawing Helpers

private func drawPolygons(ctx: CGContext, layer: VTLayer, tileSize: CGFloat) {
    for feature in layer.features where feature.type == .polygon {
        let rings = decodeGeometry(commands: feature.geometry, extent: layer.extent, tileSize: tileSize)
        for ring in rings where ring.count >= 3 {
            ctx.beginPath()
            ctx.move(to: ring[0])
            for i in 1..<ring.count { ctx.addLine(to: ring[i]) }
            ctx.closePath()
            ctx.fillPath()
        }
    }
}

private func drawLines(ctx: CGContext, layer: VTLayer, tileSize: CGFloat) {
    ctx.setLineJoin(.round)
    for feature in layer.features where feature.type == .linestring {
        let paths = decodeGeometry(commands: feature.geometry, extent: layer.extent, tileSize: tileSize)
        for path in paths where path.count >= 2 {
            ctx.beginPath()
            ctx.move(to: path[0])
            for i in 1..<path.count { ctx.addLine(to: path[i]) }
            ctx.strokePath()
        }
    }
}

private let parkClasses: Set<String> = [
    "park", "garden", "cemetery", "grass", "playground",
    "recreation_ground", "nature_reserve", "forest"
]

private func drawLanduse(ctx: CGContext, layer: VTLayer, tileSize: CGFloat, style: MapLayerStyle) {
    let classIdx = layer.keys.firstIndex(of: "class")

    for feature in layer.features where feature.type == .polygon {
        var isPark = false
        if let ki = classIdx {
            for j in stride(from: 0, to: feature.tags.count - 1, by: 2) {
                if feature.tags[j] == UInt32(ki) {
                    let vi = Int(feature.tags[j + 1])
                    if vi < layer.values.count, let cls = layer.values[vi].stringValue {
                        isPark = parkClasses.contains(cls)
                    }
                }
            }
        }

        let c = isPark ? style.park : style.land
        ctx.setFillColor(cgColor(c.r, c.g, c.b, c.a))

        let rings = decodeGeometry(commands: feature.geometry, extent: layer.extent, tileSize: tileSize)
        for ring in rings where ring.count >= 3 {
            ctx.beginPath()
            ctx.move(to: ring[0])
            for i in 1..<ring.count { ctx.addLine(to: ring[i]) }
            ctx.closePath()
            ctx.fillPath()
        }
    }
}

private let majorRoadClasses: Set<String> = ["motorway", "trunk", "primary", "secondary"]

private func drawRoads(ctx: CGContext, layer: VTLayer, tileSize: CGFloat, style: MapLayerStyle, zoom: Int) {
    let classIdx = layer.keys.firstIndex(of: "class")

    // Zoom-based width scaling: thinner at low zoom, thicker at high zoom
    let zoomScale = max(0.5, min(2.0, CGFloat(zoom - 10) / 6.0))

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Two passes: minor first, then major on top
    for pass in 0...1 {
        let drawMajor = pass == 1

        for feature in layer.features where feature.type == .linestring {
            var isMajor = false
            if let ki = classIdx {
                for j in stride(from: 0, to: feature.tags.count - 1, by: 2) {
                    if feature.tags[j] == UInt32(ki) {
                        let vi = Int(feature.tags[j + 1])
                        if vi < layer.values.count, let cls = layer.values[vi].stringValue {
                            isMajor = majorRoadClasses.contains(cls)
                        }
                    }
                }
            }

            guard isMajor == drawMajor else { continue }

            let c = isMajor ? style.roadMajor : style.roadMinor
            let w = (isMajor ? style.roadMajorWidth : style.roadMinorWidth) * zoomScale
            ctx.setStrokeColor(cgColor(c.r, c.g, c.b, c.a))
            ctx.setLineWidth(w)

            let paths = decodeGeometry(commands: feature.geometry, extent: layer.extent, tileSize: tileSize)
            for path in paths where path.count >= 2 {
                ctx.beginPath()
                ctx.move(to: path[0])
                for i in 1..<path.count { ctx.addLine(to: path[i]) }
                ctx.strokePath()
            }
        }
    }
}
