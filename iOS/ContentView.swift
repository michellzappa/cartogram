import SwiftUI
import MapCore

struct ContentView: View {
    @ObservedObject var viewModel: GeneratorViewModel
    @State private var showControls = true
    @State private var showSettings = false
    @State private var dragOffset: CGSize = .zero
    @State private var currentRotation: Angle = .zero

    var body: some View {
        ZStack {
            wallpaperBackground
                .offset(dragOffset)
                .rotationEffect(currentRotation)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            viewModel.applyPan(
                                dx: Double(value.translation.width),
                                dy: Double(value.translation.height)
                            )
                            // Don't reset dragOffset yet — keep old image shifted
                            // until the new render arrives
                        }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .onChanged { angle in
                            currentRotation = angle
                        }
                        .onEnded { angle in
                            viewModel.rotation += angle.radians
                            // Don't reset currentRotation — cleared when new image arrives
                            viewModel.generate()
                        }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { showControls.toggle() }
                }

            if showControls {
                VStack(spacing: 0) {
                    Spacer()
                    controlsPanel
                }
                .transition(.opacity)
            }

            // Recenter button (top-left, only when panned/rotated)
            if showControls && viewModel.isPanned {
                VStack {
                    HStack {
                        Button { viewModel.recenter() } label: {
                            Image(systemName: "location.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                        }
                        .padding(.leading, 16)
                        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 56)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            if viewModel.locationDenied && viewModel.generatedImage == nil {
                permissionBanner(
                    icon: "location.slash.fill",
                    title: "Location Access Needed",
                    message: "Cartogram needs your location to center the map. You can also set a manual address in Settings.",
                    showSettings: true
                )
            } else if let error = viewModel.lastError {
                VStack {
                    errorBanner(error)
                    Spacer()
                }
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.generate()
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let image = viewModel.generatedImage {
                ShareSheet(items: [image])
            }
        }
        .onChange(of: viewModel.generationId) { _ in
            dragOffset = .zero
            currentRotation = .zero
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // MARK: - Wallpaper Background

    @ViewBuilder
    private var wallpaperBackground: some View {
        GeometryReader { geo in
            if let image = viewModel.generatedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                ZStack {
                    Color(white: 0.06)
                    VStack(spacing: 10) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("Cartogram")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(spacing: 14) {
                HStack {
                    Label(viewModel.locationString, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption.weight(.medium))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 10) {
                    Button { if viewModel.zoom > 10 { viewModel.zoom -= 1 } } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.medium))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(0.1)))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Button { if viewModel.zoom < 16 { viewModel.zoom += 1 } } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.medium))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(0.1)))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: { viewModel.generate() }) {
                        HStack(spacing: 6) {
                            if viewModel.isGenerating {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "paintbrush.fill")
                                    .font(.subheadline)
                            }
                            Text("Generate")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(width: 140)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(viewModel.isGenerating ? .white.opacity(0.1) : .white.opacity(0.2))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(viewModel.isGenerating)

                    if viewModel.generatedImage != nil {
                        Button(action: { viewModel.showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption.weight(.medium))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(.white.opacity(0.12)))
                                .foregroundStyle(.white)
                        }

                        Button(action: { viewModel.saveToPhotos() }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.medium))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(.white.opacity(0.12)))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 500)
        .padding(.horizontal, 12)
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ForEach(Themes.all, id: \.id) { theme in
                        Button {
                            viewModel.selectedThemeId = theme.id
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 0) {
                                    Color(red: Double(theme.heatmap.dim.r), green: Double(theme.heatmap.dim.g), blue: Double(theme.heatmap.dim.b))
                                    Color(red: Double(theme.heatmap.mid.r), green: Double(theme.heatmap.mid.g), blue: Double(theme.heatmap.mid.b))
                                    Color(red: Double(theme.heatmap.bright.r), green: Double(theme.heatmap.bright.g), blue: Double(theme.heatmap.bright.b))
                                }
                                .frame(width: 32, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                                Text(theme.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if theme.id == viewModel.selectedThemeId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
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
                    Button("Done") {
                        showSettings = false
                        viewModel.resolveLocation()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Error Banner

    private func permissionBanner(icon: String, title: String, message: String, showSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.6))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            if showSettings {
                HStack(spacing: 12) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Use Address Instead") {
                        viewModel.locationMode = .address
                        self.showSettings = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }

            Spacer()
        }
        .frame(maxWidth: 500)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.red.opacity(0.7))
                    .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
            )
            .clipShape(Capsule())
            .padding(.horizontal, 40)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
