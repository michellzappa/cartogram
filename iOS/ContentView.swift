import SwiftUI
import UIKit
import MapCore

struct ContentView: View {
    @ObservedObject var viewModel: GeneratorViewModel
    @State private var showControls = true
    @State private var showSettings = false
    @State private var dragOffset: CGSize = .zero
    @State private var currentRotation: Angle = .zero
    @State private var sharePayload: SharePayload?

    private var errorBannerTopPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 60
    }

    private var recenterButtonTopPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 56
    }

    var body: some View {
        ZStack {
            WallpaperBackgroundView(image: viewModel.generatedImage)
                .offset(dragOffset)
                .rotationEffect(currentRotation)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged(handlePanChanged)
                        .onEnded(handlePanEnded)
                )
                .simultaneousGesture(
                    RotationGesture()
                        .onChanged(handleRotationChanged)
                        .onEnded(handleRotationEnded)
                )
                .onTapGesture(perform: toggleControls)

            if showControls {
                VStack(spacing: 0) {
                    Spacer()
                    GeneratorControlsPanel(
                        locationString: viewModel.locationString,
                        isGenerating: viewModel.isGenerating,
                        canZoomOut: viewModel.zoom > 10,
                        canZoomIn: viewModel.zoom < 16,
                        canExport: viewModel.generatedImage != nil,
                        onOpenSettings: openSettings,
                        onZoomOut: zoomOut,
                        onZoomIn: zoomIn,
                        onGenerate: viewModel.generate,
                        onShare: queueShareSheet,
                        onSave: viewModel.saveToPhotos
                    )
                }
                .transition(.opacity)
            }

            if showControls && viewModel.isPanned {
                RecenterButtonOverlay(
                    topPadding: recenterButtonTopPadding,
                    onRecenter: viewModel.recenter
                )
                .transition(.opacity)
            }

            bannerOverlay
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            generateIfNeeded()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.image])
        }
        .sheet(isPresented: $showSettings) {
            GeneratorSettingsView(
                viewModel: viewModel,
                onDone: dismissSettings
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.generationId) { _ in
            resetTransientTransforms()
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if viewModel.locationDenied && viewModel.generatedImage == nil {
            PermissionBannerView(
                icon: "location.slash.fill",
                title: "Location Access Needed",
                message: "Cartogram needs your location to center the map. You can also set a manual address in Settings.",
                onOpenSettings: openAppSettings,
                onUseAddressInstead: useAddressMode
            )
        } else if let error = viewModel.lastError {
            VStack {
                ErrorBannerView(message: error)
                Spacer()
            }
            .padding(.top, errorBannerTopPadding)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func generateIfNeeded() {
        guard viewModel.generatedImage == nil, !viewModel.isGenerating else { return }
        viewModel.generate()
    }

    private func openSettings() {
        showSettings = true
    }

    private func dismissSettings() {
        showSettings = false
        viewModel.resolveLocation()
    }

    private func zoomOut() {
        guard viewModel.zoom > 10 else { return }
        viewModel.zoom -= 1
    }

    private func zoomIn() {
        guard viewModel.zoom < 16 else { return }
        viewModel.zoom += 1
    }

    private func queueShareSheet() {
        guard let image = viewModel.generatedImage else { return }
        sharePayload = SharePayload(image: image)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
    }

    private func useAddressMode() {
        viewModel.locationMode = .address
        showSettings = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func resetTransientTransforms() {
        dragOffset = .zero
        currentRotation = .zero
    }

    private func handlePanChanged(_ value: DragGesture.Value) {
        dragOffset = value.translation
    }

    private func handlePanEnded(_ value: DragGesture.Value) {
        viewModel.applyPan(
            dx: Double(value.translation.width),
            dy: Double(value.translation.height)
        )
    }

    private func handleRotationChanged(_ angle: Angle) {
        currentRotation = angle
    }

    private func handleRotationEnded(_ angle: Angle) {
        viewModel.rotation += angle.radians
        viewModel.generate()
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct WallpaperBackgroundView: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    WallpaperPlaceholderView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

private struct WallpaperPlaceholderView: View {
    var body: some View {
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
    }
}

private struct GeneratorControlsPanel: View {
    let locationString: String
    let isGenerating: Bool
    let canZoomOut: Bool
    let canZoomIn: Bool
    let canExport: Bool
    let onOpenSettings: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onGenerate: () -> Void
    let onShare: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(spacing: 14) {
                HStack {
                    Label(locationString, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption.weight(.medium))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 10) {
                    CircleIconButton(
                        systemName: "minus",
                        isEnabled: canZoomOut,
                        action: onZoomOut
                    )

                    CircleIconButton(
                        systemName: "plus",
                        isEnabled: canZoomIn,
                        action: onZoomIn
                    )

                    Spacer()

                    Button(action: onGenerate) {
                        HStack(spacing: 6) {
                            if isGenerating {
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
                                .fill(isGenerating ? .white.opacity(0.1) : .white.opacity(0.2))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(isGenerating)

                    if canExport {
                        CircleIconButton(
                            systemName: "square.and.arrow.up",
                            action: onShare
                        )

                        CircleIconButton(
                            systemName: "square.and.arrow.down",
                            action: onSave
                        )
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
}

private struct CircleIconButton: View {
    let systemName: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.medium))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(0.12)))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
        }
        .disabled(!isEnabled)
    }
}

private struct RecenterButtonOverlay: View {
    let topPadding: CGFloat
    let onRecenter: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: onRecenter) {
                    Image(systemName: "location.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                }
                .padding(.leading, 16)
                .padding(.top, topPadding)

                Spacer()
            }

            Spacer()
        }
    }
}

private struct PermissionBannerView: View {
    let icon: String
    let title: String
    let message: String
    let onOpenSettings: () -> Void
    let onUseAddressInstead: () -> Void

    var body: some View {
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

            HStack(spacing: 12) {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)

                Button("Use Address Instead", action: onUseAddressInstead)
                    .buttonStyle(.bordered)
                    .tint(.white)
            }

            Spacer()
        }
        .frame(maxWidth: 500)
    }
}

private struct ErrorBannerView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.red.opacity(0.7))
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )
            )
            .clipShape(Capsule())
            .padding(.horizontal, 40)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
