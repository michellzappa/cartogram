# Cartogram

Map wallpapers generated from your photo locations. macOS menu bar app + iOS app.

Reads GPS metadata from your photo library, renders a heatmap overlay on vector map tiles, and sets it as your wallpaper.

## Features

- Vector map rendering from OpenFreeMap tiles (no API key needed)
- Five monochromatic themes with matching heatmap accents
- Adjustable zoom (10-16, with overzooming)
- Auto-detect current location or set manually
- macOS: lives in menu bar, sets wallpaper directly
- iOS: full-screen preview with pan, zoom, rotation
- All processing on-device, no data leaves your device

## Building

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Cartogram.xcodeproj
```

Set your development team in Xcode before building.

## Architecture

- `Sources/MapCore/` - shared library: vector tile renderer, map generation, photo location fetching
- `Sources/CLI/` - command-line tool
- `macOS/` - macOS menu bar app
- `iOS/` - iOS app

The vector tile renderer (`VectorTile.swift`) is a from-scratch PBF/MVT parser and CGContext renderer with no external dependencies.

## Attribution

Map data &copy; [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors. Tiles from [OpenFreeMap](https://openfreemap.org).

## License

MIT
