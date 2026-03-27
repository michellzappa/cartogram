import SwiftUI
import MapCore

struct GeneratorSettingsView: View {
    @ObservedObject var viewModel: GeneratorViewModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ForEach(Themes.all, id: \.id) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            isSelected: theme.id == viewModel.selectedThemeId
                        ) {
                            viewModel.selectedThemeId = theme.id
                        }
                    }
                }

                Section("Map") {
                    Toggle("Heatmap", isOn: $viewModel.heatmapEnabled)
                    Toggle("HDR", isOn: $viewModel.hdrEnabled)
                }

                Section("Location") {
                    Picker("Source", selection: $viewModel.locationModeRaw) {
                        ForEach(LocationMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }

                    if viewModel.locationMode == .address {
                        TextField("Location", text: $viewModel.defaultAddress)
                            .textContentType(.fullStreetAddress)
                    }
                }

                Section("Photos") {
                    HStack {
                        Text("Geotagged photos")
                        Spacer()
                        Text(viewModel.photoCount > 0 ? "\(viewModel.photoCount.formatted())" : "—")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    Text("Map data © OpenStreetMap contributors · OpenFreeMap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: MapTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ThemeSwatchColor(
                        red: Double(theme.heatmap.dim.r),
                        green: Double(theme.heatmap.dim.g),
                        blue: Double(theme.heatmap.dim.b)
                    )
                    ThemeSwatchColor(
                        red: Double(theme.heatmap.mid.r),
                        green: Double(theme.heatmap.mid.g),
                        blue: Double(theme.heatmap.mid.b)
                    )
                    ThemeSwatchColor(
                        red: Double(theme.heatmap.bright.r),
                        green: Double(theme.heatmap.bright.g),
                        blue: Double(theme.heatmap.bright.b)
                    )
                }
                .frame(width: 32, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(theme.name)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSwatchColor: View {
    let red: Double
    let green: Double
    let blue: Double

    var body: some View {
        Color(red: red, green: green, blue: blue)
    }
}
