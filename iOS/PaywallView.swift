import SwiftUI
import MapCore

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    let onUnlocked: () -> Void

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var message: String?

    private var isWorking: Bool {
        isPurchasing || isRestoring
    }

    private var priceText: String {
        store.proProduct?.displayPrice ?? "€2.99"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                if let icon = UIImage(named: "AppIcon60x60") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                }

                VStack(spacing: 8) {
                    Text("Support Cartogram")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Cartogram is made by one person. Your purchase keeps it alive and unlocks everything below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    PaywallFeatureRow(text: "Seven hand-crafted map themes")
                    PaywallFeatureRow(text: "HDR wallpaper export")
                    PaywallFeatureRow(text: "Support independent development")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.3, green: 0.15, blue: 0.5).opacity(0.15))
                )

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button(action: purchasePro) {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text("Unlock Pro for \(priceText)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.25, blue: 0.85))
                    .disabled(isWorking)

                    Button(action: restorePurchases) {
                        HStack {
                            if isRestoring {
                                ProgressView()
                            }

                            Text("Restore Purchases")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                Text("One-time purchase. Existing paid users keep Pro automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Cartogram Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
        }
        .task {
            guard store.proProduct == nil else { return }
            await store.loadProduct()
        }
    }

    private func purchasePro() {
        message = nil
        isPurchasing = true

        Task {
            if store.proProduct == nil {
                await store.loadProduct()
            }

            guard store.proProduct != nil else {
                await MainActor.run {
                    isPurchasing = false
                    message = "Couldn't load the App Store price right now."
                }
                return
            }

            let success = await store.purchasePro()

            await MainActor.run {
                isPurchasing = false

                guard success else { return }
                onUnlocked()
                dismiss()
            }
        }
    }

    private func restorePurchases() {
        message = nil
        isRestoring = true

        Task {
            let restored = await store.restorePurchases()

            await MainActor.run {
                isRestoring = false

                if restored {
                    onUnlocked()
                    dismiss()
                } else {
                    message = "No previous Cartogram Pro purchase was found to restore."
                }
            }
        }
    }
}

private struct PaywallFeatureRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.85))

            Text(text)
                .foregroundStyle(.primary)
        }
    }
}
