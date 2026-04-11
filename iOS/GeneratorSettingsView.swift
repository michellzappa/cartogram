import SwiftUI
import Photos
import MapCore

private enum PaywallIntent: Identifiable {
    case theme(MapTheme)
    case hdr

    var id: String {
        switch self {
        case .theme(let theme):
            return "theme-\(theme.id)"
        case .hdr:
            return "hdr"
        }
    }
}

struct GeneratorSettingsView: View {
    @EnvironmentObject private var store: StoreManager
    @ObservedObject var viewModel: GeneratorViewModel
    let onDone: () -> Void

    @State private var paywallIntent: PaywallIntent?

    private var accent: Color {
        let mid = viewModel.selectedTheme.heatmap.mid
        return Color(red: Double(mid.r), green: Double(mid.g), blue: Double(mid.b))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ForEach(Themes.all, id: \.id) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            isSelected: theme.id == viewModel.selectedThemeId,
                            isLocked: theme.isPro && !store.isPro,
                            accent: accent
                        ) {
                            handleThemeSelection(theme)
                        }
                    }
                }

                Section("Map") {
                    Toggle("Heatmap", isOn: $viewModel.heatmapEnabled)
                        .tint(accent)

                    HDRSettingRow(
                        isEnabled: store.isPro,
                        isOn: viewModel.hdrEnabled,
                        accent: accent
                    ) {
                        handleHDRTap()
                    }
                }

                Section("Location") {
                    Picker("Source", selection: $viewModel.locationModeRaw) {
                        ForEach(LocationMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .tint(.secondary)

                    if viewModel.locationMode == .address {
                        TextField("Location", text: $viewModel.defaultAddress)
                            .textContentType(.fullStreetAddress)
                    }
                }

                Section("Photos") {
                    NavigationLink {
                        PhotoAlbumPickerView(selection: $viewModel.photoAlbumId)
                    } label: {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(viewModel.photoAlbumDisplayTitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Geotagged photos")
                        Spacer()
                        Text(viewModel.photoCount > 0 ? "\(viewModel.photoCount.formatted())" : "—")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    if store.isPro {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thank you for supporting Cartogram")
                                    .font(.subheadline.weight(.semibold))
                                Text("Pro features unlocked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Link(destination: URL(string: "https://michellzappa.com")!) {
                        HStack {
                            Text("Made by")
                                .foregroundStyle(.secondary)
                            Text("Michell Zappa")
                        }
                        .font(.caption)
                    }

                    Text("Map data © OpenStreetMap contributors · OpenFreeMap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                }
            }
            .sheet(item: $paywallIntent) { intent in
                PaywallView {
                    applyUnlockedIntent(intent)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func handleThemeSelection(_ theme: MapTheme) {
        guard !theme.isPro || store.isPro else {
            paywallIntent = .theme(theme)
            return
        }

        viewModel.selectedThemeId = theme.id
    }

    private func handleHDRTap() {
        guard store.isPro else {
            paywallIntent = .hdr
            return
        }

        viewModel.hdrEnabled.toggle()
    }

    private func applyUnlockedIntent(_ intent: PaywallIntent) {
        switch intent {
        case .theme(let theme):
            viewModel.selectedThemeId = theme.id
        case .hdr:
            viewModel.hdrEnabled = true
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: MapTheme
    let isSelected: Bool
    let isLocked: Bool
    let accent: Color
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

                if isLocked {
                    ProBadge(accent: accent)

                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HDRSettingRow: View {
    let isEnabled: Bool
    let isOn: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("HDR")
                    .foregroundStyle(.primary)

                Spacer()

                if !isEnabled {
                    ProBadge(accent: accent)
                }

                Toggle("", isOn: .constant(isEnabled && isOn))
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .tint(accent)

                if !isEnabled {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProBadge: View {
    let accent: Color

    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(accent.opacity(0.18))
            )
            .foregroundStyle(accent)
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

struct PhotoAlbumPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [PhotoAlbum] = []
    @State private var isLoading = true
    @State private var authDenied = false

    var body: some View {
        List {
            if authDenied {
                Section {
                    Text("Photos access is required to list albums. Enable it in Settings → Privacy & Security → Photos.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                AlbumRow(
                    title: "All Photos",
                    detail: nil,
                    isSelected: selection.isEmpty
                ) {
                    selection = ""
                    dismiss()
                }
            }

            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { album in
                        AlbumRow(
                            title: album.title,
                            detail: album.assetCount > 0 ? "\(album.assetCount.formatted())" : nil,
                            isSelected: album.id == selection
                        ) {
                            selection = album.id
                            dismiss()
                        }
                    }
                }
            } else if !isLoading && !authDenied {
                Section {
                    Text("No user albums found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Photo Source")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        let loaded: [PhotoAlbum] = await Task.detached(priority: .userInitiated) {
            fetchUserPhotoAlbums()
        }.value

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        await MainActor.run {
            albums = loaded
            authDenied = status == .denied || status == .restricted
            isLoading = false
        }
    }
}

private struct AlbumRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
