import SwiftUI
import MapCore

struct SettingsView: View {
    @ObservedObject var viewModel: GeneratorViewModel

    var body: some View {
        Form {
            Section("Location") {
                Picker("Source", selection: $viewModel.locationModeRaw) {
                    ForEach(LocationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }

                if viewModel.locationMode == .address {
                    TextField("Location", text: $viewModel.defaultAddress)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Theme") {
                ForEach(Themes.all, id: \.id) { theme in
                    HStack {
                        // Color swatch
                        HStack(spacing: 2) {
                            ThemeSwatchColor(r: theme.heatmap.dim.r, g: theme.heatmap.dim.g, b: theme.heatmap.dim.b)
                            ThemeSwatchColor(r: theme.heatmap.mid.r, g: theme.heatmap.mid.g, b: theme.heatmap.mid.b)
                            ThemeSwatchColor(r: theme.heatmap.bright.r, g: theme.heatmap.bright.g, b: theme.heatmap.bright.b)
                        }
                        .frame(width: 48, height: 16)
                        .cornerRadius(3)

                        Text(theme.name)

                        Spacer()

                        if theme.id == viewModel.selectedThemeId {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.selectedThemeId = theme.id }
                }
            }

            Section("Map") {
                Picker("Zoom level", selection: $viewModel.zoom) {
                    ForEach(10..<17) { z in
                        Text("\(z)").tag(z)
                    }
                }

                Toggle("Show photo heatmap", isOn: $viewModel.heatmapEnabled)
            }

            Section("Photos") {
                HStack {
                    Text("Geotagged photos")
                    Spacer()
                    Text(viewModel.photoCount > 0 ? "\(viewModel.photoCount.formatted())" : "—")
                        .foregroundColor(.secondary)
                }
            }

            Section("About") {
                Text("Map data © OpenStreetMap contributors · OpenFreeMap")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
    }
}

struct ThemeSwatchColor: View {
    let r: Float, g: Float, b: Float
    var body: some View {
        Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}
