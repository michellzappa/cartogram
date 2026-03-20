import AppKit
import CoreImage
import ImageIO

enum WallpaperService {
    static func wallpaperDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cartogram")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    private static func cleanOldWallpapers(in dir: URL) {
        if let oldFiles = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in oldFiles where f.pathExtension == "png" || f.pathExtension == "heic" {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    /// Write HDR HEIF (10-bit PQ) and set as wallpaper.
    static func setWallpaperHDR(ciImage: CIImage) throws {
        let dir = wallpaperDirectory()
        cleanOldWallpapers(in: dir)

        let file = dir.appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970)).heic")
        guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else {
            throw WallpaperError.encodingFailed
        }
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        ])
        try ctx.writeHEIF10Representation(of: ciImage, to: file, colorSpace: colorSpace)

        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            try workspace.setDesktopImageURL(file, for: screen, options: [:])
        }
    }

    /// Write standard PNG and set as wallpaper.
    static func setWallpaperSDR(cgImage: CGImage) throws {
        let dir = wallpaperDirectory()
        cleanOldWallpapers(in: dir)

        let file = dir.appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970)).png")
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else {
            throw WallpaperError.encodingFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw WallpaperError.encodingFailed
        }

        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            try workspace.setDesktopImageURL(file, for: screen, options: [:])
        }
    }

    enum WallpaperError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode wallpaper image"
            }
        }
    }
}
