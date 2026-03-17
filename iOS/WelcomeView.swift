import SwiftUI
import CoreLocation
import Photos
import MapCore

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 8)

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
                    title: "Private by Design",
                    description: "All processing happens on your device. No data ever leaves your phone."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: requestPermissionsThenContinue) {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: 500)
        .preferredColorScheme(.dark)
    }

    private func requestPermissionsThenContinue() {
        // Trigger location prompt
        LocationService.shared.ensureAuthorized()

        // Trigger photos prompt, then continue regardless of result
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async { onContinue() }
            }
        } else {
            onContinue()
        }
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
}
