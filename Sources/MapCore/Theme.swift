import Foundation
import CoreGraphics

// MARK: - Heatmap Color Palette

public struct HeatmapPalette {
    public let dim: (r: Float, g: Float, b: Float, a: Float)
    public let mid: (r: Float, g: Float, b: Float, a: Float)
    public let bright: (r: Float, g: Float, b: Float, a: Float)

    public init(
        dim: (r: Float, g: Float, b: Float, a: Float),
        mid: (r: Float, g: Float, b: Float, a: Float),
        bright: (r: Float, g: Float, b: Float, a: Float)
    ) {
        self.dim = dim; self.mid = mid; self.bright = bright
    }
}

// MARK: - Heatmap Blend Mode

public enum HeatmapBlend {
    case screen   // additive — good on dark backgrounds
    case multiply // subtractive — good on light backgrounds
    case normal   // standard alpha composite — good on mid-tone backgrounds

    public var cgBlendMode: CGBlendMode {
        switch self {
        case .screen: return .screen
        case .multiply: return .multiply
        case .normal: return .normal
        }
    }
}

// MARK: - Map Theme

public struct MapTheme {
    public let id: String
    public let name: String
    public let mapStyle: MapLayerStyle
    public let bgColor: (r: Double, g: Double, b: Double)
    public let heatmap: HeatmapPalette
    public let blend: HeatmapBlend

    public init(id: String, name: String,
                mapStyle: MapLayerStyle,
                bgColor: (r: Double, g: Double, b: Double),
                heatmap: HeatmapPalette,
                blend: HeatmapBlend = .screen) {
        self.id = id; self.name = name
        self.mapStyle = mapStyle
        self.bgColor = bgColor; self.heatmap = heatmap; self.blend = blend
    }
}

// MARK: - Monochrome Map Style Generator

/// Generate a full MapLayerStyle from a single base color and brightness level.
/// All map features use tonal variations of the same hue.
private func monoStyle(
    r: CGFloat, g: CGFloat, b: CGFloat,
    base: CGFloat = 0.11
) -> MapLayerStyle {
    // Tonal variations of one hue with strong contrast
    // Water much darker, roads much brighter, clear hierarchy
    func c(_ v: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        (r: r * v, g: g * v, b: b * v)
    }
    let bg   = c(1.0)
    let wat  = c(0.15)       // very dark — clear water bodies
    let wway = c(0.25)
    let lnd  = c(0.85)       // slightly darker than bg
    let prk  = c(0.55)       // noticeably darker
    let bld  = c(1.8)        // brighter than bg
    let rdMj = c(3.0)        // strong bright lines
    let rdMn = c(2.0)

    return MapLayerStyle(
        background: bg,
        water:      wat,
        waterway:   (r: wway.r, g: wway.g, b: wway.b, a: 0.8),
        land:       (r: lnd.r,  g: lnd.g,  b: lnd.b,  a: 0.5),
        park:       (r: prk.r,  g: prk.g,  b: prk.b,  a: 0.6),
        building:   (r: bld.r,  g: bld.g,  b: bld.b,  a: 0.7),
        roadMajor:  (r: rdMj.r, g: rdMj.g, b: rdMj.b, a: 0.9),
        roadMinor:  (r: rdMn.r, g: rdMn.g, b: rdMn.b, a: 0.7),
        roadMajorWidth: 2.5,
        roadMinorWidth: 1.0
    )
}

/// Light variant: water/parks are darker shades, roads are lighter
private func monoStyleLight(
    r: CGFloat, g: CGFloat, b: CGFloat,
    base: CGFloat = 0.90
) -> MapLayerStyle {
    let scale: CGFloat = 1.0 / max(base, 0.01)
    func c(_ factor: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        (r: r * factor, g: g * factor, b: b * factor)
    }
    let bg   = c(base * scale)
    let wat  = c(base * 0.82 * scale)
    let wway = c(base * 0.80 * scale)
    let lnd  = c(base * 0.95 * scale)
    let prk  = c(base * 0.88 * scale)
    let bld  = c(base * 0.87 * scale)
    let rdMj = c(base * 1.10 * scale)
    let rdMn = c(base * 1.05 * scale)

    return MapLayerStyle(
        background: bg,
        water:      wat,
        waterway:   (r: wway.r, g: wway.g, b: wway.b, a: 0.8),
        land:       (r: lnd.r,  g: lnd.g,  b: lnd.b,  a: 0.6),
        park:       (r: prk.r,  g: prk.g,  b: prk.b,  a: 0.6),
        building:   (r: bld.r,  g: bld.g,  b: bld.b,  a: 0.7),
        roadMajor:  (r: rdMj.r, g: rdMj.g, b: rdMj.b, a: 1.0),
        roadMinor:  (r: rdMn.r, g: rdMn.g, b: rdMn.b, a: 0.8),
        roadMajorWidth: 2.5,
        roadMinorWidth: 1.0
    )
}

// MARK: - Built-in Themes

public enum Themes {

    // Deep navy map + magenta/pink heatmap
    public static let cyberpunk = MapTheme(
        id: "cyberpunk",
        name: "Cyberpunk",
        mapStyle: monoStyle(r: 0.09, g: 0.09, b: 0.14, base: 0.11),
        bgColor: (0.06, 0.06, 0.10),
        heatmap: HeatmapPalette(
            dim:    (r: 0.45, g: 0.05, b: 0.40, a: 0.40),
            mid:    (r: 0.75, g: 0.15, b: 0.45, a: 0.65),
            bright: (r: 1.00, g: 0.75, b: 0.80, a: 0.90)
        )
    )

    // Near-black charcoal map + cyan/ice heatmap
    public static let midnight = MapTheme(
        id: "midnight",
        name: "Midnight",
        mapStyle: monoStyle(r: 0.10, g: 0.10, b: 0.12, base: 0.09),
        bgColor: (0.05, 0.05, 0.07),
        heatmap: HeatmapPalette(
            dim:    (r: 0.05, g: 0.30, b: 0.45, a: 0.40),
            mid:    (r: 0.10, g: 0.55, b: 0.75, a: 0.65),
            bright: (r: 0.55, g: 0.95, b: 1.00, a: 0.90)
        )
    )

    // Dark warm brown map + orange/amber heatmap
    public static let ember = MapTheme(
        id: "ember",
        name: "Ember",
        mapStyle: monoStyle(r: 0.14, g: 0.11, b: 0.09, base: 0.11),
        bgColor: (0.10, 0.08, 0.06),
        heatmap: HeatmapPalette(
            dim:    (r: 0.50, g: 0.15, b: 0.05, a: 0.45),
            mid:    (r: 0.85, g: 0.35, b: 0.05, a: 0.70),
            bright: (r: 1.00, g: 0.85, b: 0.30, a: 0.90)
        ),
        blend: .normal
    )

    // Cool light grey map + deep indigo heatmap
    public static let ghost = MapTheme(
        id: "ghost",
        name: "Ghost",
        mapStyle: monoStyleLight(r: 0.91, g: 0.91, b: 0.93, base: 0.92),
        bgColor: (0.91, 0.91, 0.93),
        heatmap: HeatmapPalette(
            dim:    (r: 0.50, g: 0.40, b: 0.65, a: 0.50),
            mid:    (r: 0.30, g: 0.20, b: 0.55, a: 0.75),
            bright: (r: 0.15, g: 0.08, b: 0.40, a: 0.95)
        ),
        blend: .multiply
    )

    // Dark olive map + bright green heatmap
    public static let moss = MapTheme(
        id: "moss",
        name: "Moss",
        mapStyle: monoStyle(r: 0.10, g: 0.13, b: 0.09, base: 0.11),
        bgColor: (0.07, 0.09, 0.06),
        heatmap: HeatmapPalette(
            dim:    (r: 0.10, g: 0.40, b: 0.15, a: 0.40),
            mid:    (r: 0.20, g: 0.70, b: 0.30, a: 0.65),
            bright: (r: 0.55, g: 1.00, b: 0.60, a: 0.90)
        ),
        blend: .normal
    )

    public static let all: [MapTheme] = [cyberpunk, midnight, ember, ghost, moss]

    public static func byId(_ id: String) -> MapTheme {
        all.first { $0.id == id } ?? cyberpunk
    }
}
