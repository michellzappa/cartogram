import Foundation
import StoreKit

/// Manages Pro unlock state via StoreKit 2 and legacy paid-app migration.
///
/// v1.2 (free + IAP): Checks the stored legacy flag, AppTransaction, and
/// current entitlements to grant or revoke Pro access.
@MainActor
public final class StoreManager: ObservableObject {

    public static let shared = StoreManager()

    /// The product ID for the single non-consumable Pro unlock.
    /// Register this in App Store Connect when preparing v1.2.
    public static let proProductID = "com.centaur-labs.cartogram.pro"

    /// First version distributed as free. Set this to the build number of v1.2
    /// so AppTransaction can distinguish paid-era users from free-era users.
    public static let firstFreeVersion = "5"

    // MARK: - Published State

    @Published public private(set) var isPro: Bool
    @Published public private(set) var isConfigured = false
    @Published public private(set) var proProduct: Product?

    // MARK: - Persistence

    /// Set to true in v1.1 while the app is still paid.
    /// Users who updated through that version keep Pro automatically in v1.2.
    private static let legacyKey = "paidV1User"
    private static let cachedProKey = "cachedProStatus"
    private static let selectedThemeKey = "selectedTheme"
    private static let hdrEnabledKey = "hdrEnabled"
    private static let defaultZoomKey = "defaultZoom"

    private var transactionUpdatesTask: Task<Void, Never>?

    public var isLegacyPaidUser: Bool {
        UserDefaults.standard.bool(forKey: Self.legacyKey)
    }

    nonisolated public static func cachedProStatus() -> Bool {
        UserDefaults.standard.bool(forKey: "cachedProStatus")
    }

    // MARK: - Init

    private init() {
        isPro = Self.cachedProStatus()
    }

    // MARK: - Public API

    /// Call once at app launch.
    public func configure() async {
        // Resolve Pro status from all sources now that the app is free.
        await refreshProStatus()
        isConfigured = true
        listenForTransactions()
    }

    /// Refresh Pro status by checking legacy flag, AppTransaction, and IAP entitlements.
    public func refreshProStatus() async {
        // Fast path: legacy paid user
        if isLegacyPaidUser {
            applyResolvedProStatus(true)
            return
        }

        // Check AppTransaction for users who paid but missed the v1.1 flag
        if await checkAppTransaction() {
            applyResolvedProStatus(true)
            return
        }

        // Check StoreKit 2 entitlements (IAP purchase or restore)
        if await checkIAPEntitlement() {
            applyResolvedProStatus(true)
            return
        }

        applyResolvedProStatus(false)
    }

    /// Load the Pro product from the App Store for display in the paywall.
    public func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            // Product fetch failed — paywall will show a fallback
        }
    }

    /// Purchase the Pro unlock. Returns true on success.
    @discardableResult
    public func purchasePro() async -> Bool {
        guard let product = proProduct else { return false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    applyResolvedProStatus(true)
                    return true
                }
                return false

            case .userCancelled, .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// Restore purchases. Returns true if Pro was restored.
    @discardableResult
    public func restorePurchases() async -> Bool {
        try? await AppStore.sync()
        await refreshProStatus()
        return isPro
    }

    // MARK: - Private

    private func applyResolvedProStatus(_ newValue: Bool) {
        isPro = newValue
        UserDefaults.standard.set(newValue, forKey: Self.cachedProKey)

        if !newValue {
            clampFreeUserDefaults()
        }
    }

    private func clampFreeUserDefaults() {
        let defaults = UserDefaults.standard
        let selectedThemeId = defaults.string(forKey: Self.selectedThemeKey) ?? Themes.cyberpunk.id

        if Themes.byId(selectedThemeId).isPro {
            defaults.set(Themes.cyberpunk.id, forKey: Self.selectedThemeKey)
        }

        if defaults.bool(forKey: Self.hdrEnabledKey) {
            defaults.set(false, forKey: Self.hdrEnabledKey)
        }

    }

    /// Check if the app was originally purchased (not downloaded for free).
    private func checkAppTransaction() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }

        if case .verified(let appTx) = result {
            // If the original app version is earlier than the first free version,
            // the user paid for the app.
            if let originalVersion = Int(appTx.originalAppVersion),
               let freeVersion = Int(Self.firstFreeVersion),
               originalVersion < freeVersion {
                // Persist the flag so future checks are instant
                UserDefaults.standard.set(true, forKey: Self.legacyKey)
                return true
            }
        }
        return false
    }

    /// Check StoreKit 2 current entitlements for the Pro IAP.
    private func checkIAPEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// Listen for real-time transaction updates.
    private func listenForTransactions() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshProStatus()
                }
            }
        }
    }
}
