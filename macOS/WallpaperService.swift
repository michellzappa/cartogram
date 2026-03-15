import AppKit
import ImageIO

enum WallpaperService {
    static func wallpaperDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cartogram")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    static func setWallpaper(cgImage: CGImage) throws {
        let fm = FileManager.default
        let dir = wallpaperDirectory()

        // Clean up old wallpapers
        if let oldFiles = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in oldFiles where f.pathExtension == "png" {
                try? fm.removeItem(at: f)
            }
        }

        // Write PNG
        let file = dir.appendingPathComponent("wallpaper-\(Int(Date().timeIntervalSince1970)).png")
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else {
            throw WallpaperError.encodingFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw WallpaperError.encodingFailed
        }

        // Set for all screens
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
