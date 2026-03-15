// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "photo-atlas",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "MapCore", targets: ["MapCore"]),
        .executable(name: "photo-atlas", targets: ["CLI"]),
    ],
    targets: [
        .target(name: "MapCore", path: "Sources/MapCore"),
        .executableTarget(
            name: "CLI",
            dependencies: ["MapCore"],
            path: "Sources/CLI",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CLI/Info.plist"
                ])
            ]
        )
    ]
)
