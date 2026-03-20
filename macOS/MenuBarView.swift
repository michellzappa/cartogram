import SwiftUI
import AppKit
import MapCore

struct MenuBarMenu: View {
    @ObservedObject var viewModel: GeneratorViewModel

    var body: some View {
        Button(viewModel.isGenerating ? "Generating..." : "Generate Wallpaper") {
            viewModel.generate()
        }
        .keyboardShortcut("g")
        .disabled(viewModel.isGenerating)

        Divider()

        // Location
        Text("📍 \(viewModel.locationString)")

        // Zoom submenu
        Menu("Zoom: \(viewModel.zoom)") {
            ForEach(10..<17) { z in
                Button(z == viewModel.zoom ? "✓ \(z)" : "  \(z)") {
                    viewModel.zoom = z
                }
            }
        }

        // Theme submenu
        Menu("Theme: \(viewModel.selectedTheme.name)") {
            ForEach(Themes.all, id: \.id) { theme in
                Button(theme.id == viewModel.selectedThemeId ? "✓ \(theme.name)" : "  \(theme.name)") {
                    viewModel.selectedThemeId = theme.id
                }
            }
        }

        Toggle("Photo Heatmap", isOn: $viewModel.heatmapEnabled)

        Divider()

        Button("Save as Image...") {
            viewModel.saveImage()
        }
        .keyboardShortcut("s")
        .disabled(viewModel.lastCIImage == nil)

        Divider()

        if let error = viewModel.lastError {
            Text("⚠ \(error)")
                .disabled(true)
            Divider()
        }

        Button("Settings...") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Cartogram") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// Standalone settings window for LSUIElement apps
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var viewModel: GeneratorViewModel?

    func configure(viewModel: GeneratorViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let viewModel = viewModel else { return }

        let settingsView = SettingsView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: settingsView)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Cartogram Settings"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}
