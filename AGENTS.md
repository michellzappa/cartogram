# Working on Cartogram

Cartogram makes map wallpapers from the GPS data in your photo library. There
is a macOS menu bar app, an iOS app and a command-line tool. Bundle id
`com.centaur-labs.cartogram` on both platforms. Swift 5.9, macOS 13, iOS 16.

## Layout

- `Sources/MapCore/` is the shared library: the vector tile renderer
  (`VectorTile.swift`, a PBF/MVT parser with no dependencies), map generation
  and photo location fetching. `Package.swift` at the root builds it.
- `Sources/CLI/` is the `cartogram` command-line tool.
- `macOS/` and `iOS/` are the two apps. Both depend on MapCore through
  `packages: MapCore: path: .` in `project.yml`.
- No shared house package (HouseKit or TinyKit).

## Build

XcodeGen owns the project. Edit `project.yml`, then run `xcodegen generate`.
`Cartogram.xcodeproj` is not in git. Never hand-edit it.

```bash
xcodegen generate && xcodebuild build -project Cartogram.xcodeproj -scheme Cartogram -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
```

```bash
xcodegen generate && xcodebuild build -project Cartogram.xcodeproj -scheme CartogramIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet
```

Run them on mz-mini with `remote-build '<command>'` from inside the clone. Do
not build Swift on the laptop. There is no CI workflow and there are no tests.

## Release

- `scripts/appstore.sh vX.Y.Z` archives both apps and uploads them to App
  Store Connect. `--ios-only`, `--mac-only` and `--dry-run` narrow it. It reads
  the API key from `~/.cartogram-secrets` (not in git; StarPath uses the same
  file).
- `scripts/release.sh vX.Y.Z [--notarize]` builds a Developer ID copy of the
  Mac app and publishes a zip to GitHub Releases.

## Traps

- `appstore.sh` bumps the version in the generated `project.pbxproj` and in
  both `Info.plist` files, then runs `git add -A`, commits, tags and pushes
  `main` with tags. Start from a clean tree on `main`, or it commits stray
  files.
- The version numbers in `project.yml` (`MARKETING_VERSION: "1.0.0"`) are
  stale. The script overrides them, and the `Info.plist` files carry the real
  version.
- The App Store build `v1.1.0` (2026-03-28) is on branch
  `codex-ios-review-improvements`, not on `main`. `main` is still at 1.0.2.
  Merge or reconcile that branch before the next release.
- The iOS app has a welcome screen that asks for location access. All photo
  processing stays on the device. Keep it that way.

## Writing

Docs, comments and commit messages use Simplified Technical English: active
voice, short sentences, one word for one thing. No em dashes in UI copy.
