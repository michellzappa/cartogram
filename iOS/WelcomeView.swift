import SwiftUI
import CoreLocation
import Photos
import MapCore

struct WelcomeView: View {
    var onContinue: () -> Void

    @State private var page = 0
    @State private var locationGranted = false
    @State private var locationDenied = false
    @State private var photosGranted = false
    @State private var photosDenied = false

    var body: some View {
        ZStack {
            Color(white: 0.06)
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                locationPage.tag(1)
                photosPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
        .onChange(of: page) { newPage in
            if newPage >= 2 && !locationGranted && !locationDenied {
                withAnimation { page = 1 }
            }
        }
        .onAppear(perform: refreshPermissionStates)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshPermissionStates()
            if photosGranted && page == 2 {
                onContinue()
            }
        }
    }

    // MARK: - Page layout

    private func onboardingPage<Content: View, Buttons: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()
            content()
            Spacer()

            VStack(spacing: 14) {
                buttons()
            }
            .padding(.bottom, 80)
        }
        .frame(maxWidth: 500)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        onboardingPage {
            VStack(spacing: 8) {
                if let icon = UIImage(named: "AppIcon60x60") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.bottom, 8)
                }

                Text("Welcome to\nCartogram")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(height: 48)

            VStack(alignment: .leading, spacing: 28) {
                featureRow(
                    icon: "paintbrush.pointed.fill",
                    color: .purple,
                    title: "Map Wallpapers",
                    description: "Generate beautiful wallpapers from vector maps with monochromatic themes."
                )

                featureRow(
                    icon: "photo.on.rectangle.angled",
                    color: .orange,
                    title: "Photo Heatmaps",
                    description: "Visualize where your geotagged photos were taken as a heatmap overlay."
                )

                featureRow(
                    icon: "lock.shield.fill",
                    color: .green,
                    title: "Fully Private & Offline",
                    description: "Everything stays on your device. We'll ask for photo access — it's required to build your heatmap, but nothing ever leaves your phone."
                )
            }
            .padding(.horizontal, 32)
        } buttons: {
            pageButton("Next") {
                withAnimation { page = 1 }
            }
        }
    }

    // MARK: - Page 2: Location (optional)

    private var locationPage: some View {
        onboardingPage {
            VStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 4)

                Text("Location")
                    .font(.title.bold())

                Text("Cartogram can use your location to center the map on where you are. This is optional — you can always select a location manually instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 20) {
                privacyRow(
                    icon: "iphone",
                    text: "Processed on-device only"
                )
                privacyRow(
                    icon: "wifi.slash",
                    text: "Works fully offline"
                )
                privacyRow(
                    icon: "keyboard",
                    text: "Or just type any address"
                )
            }
            .padding(.horizontal, 40)
        } buttons: {
            if locationGranted || locationDenied {
                pageButton("Next") {
                    withAnimation { page = 2 }
                }
            } else {
                pageButton("Allow Location") {
                    requestLocation()
                }

                Button("Skip") {
                    withAnimation { page = 2 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Page 3: Photos (required)

    private var photosPage: some View {
        onboardingPage {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 4)

                Text("Photo Library Access")
                    .font(.title.bold())

                if photosDenied {
                    Text("Cartogram needs access to your photo library to work. Without it, there's no heatmap data to display.\n\nPlease enable photo access in Settings to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("This is the key permission — Cartogram reads the location metadata from your photos to build your heatmap. Your photos never leave your device, and we only look at where they were taken.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 20) {
                privacyRow(
                    icon: "eye.slash.fill",
                    text: "We never see your actual photos"
                )
                privacyRow(
                    icon: "mappin.and.ellipse",
                    text: "Only GPS coordinates are read"
                )
                privacyRow(
                    icon: "lock.shield.fill",
                    text: "Nothing is uploaded or shared"
                )
            }
            .padding(.horizontal, 40)
        } buttons: {
            if photosGranted {
                pageButton("Get Started") {
                    onContinue()
                }
            } else if photosDenied {
                pageButton("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                pageButton("Allow Photo Access") {
                    requestPhotos()
                }
            }
        }
    }

    // MARK: - Shared Components

    private func pageButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(.blue)
                )
        }
        .padding(.horizontal, 40)
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.green)
                .frame(width: 28, alignment: .center)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Permissions

    private func refreshPermissionStates() {
        let locStatus = CLLocationManager().authorizationStatus
        locationGranted = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways
        locationDenied = locStatus == .denied || locStatus == .restricted

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photosGranted = photoStatus == .authorized || photoStatus == .limited
        photosDenied = photoStatus == .denied || photoStatus == .restricted
    }

    private func requestLocation() {
        LocationService.shared.ensureAuthorized()
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = CLLocationManager().authorizationStatus
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    locationGranted = true
                    withAnimation { page = 2 }
                    return
                } else if status == .denied || status == .restricted {
                    locationDenied = true
                    return
                }
            }
        }
    }

    private func requestPhotos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        photosGranted = true
                        onContinue()
                    } else {
                        photosDenied = true
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            photosGranted = true
            onContinue()
        } else {
            photosDenied = true
        }
    }
}
