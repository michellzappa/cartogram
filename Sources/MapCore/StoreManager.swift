import Foundation
import StoreKit

/// Manages Pro unlock state via StoreKit 2 and legacy paid-app migration.
///
/// v1.1 (paid app): Sets `paidV1User` flag on launch for all existing users.
/// v1.2 (free + IAP): Checks flag + AppTransaction + IAP entitlement to grant Pro.
@MainActor
public final class StoreManager: ObservableObject {

    public static let shared = StoreManager()

    /// The product ID for the single non-consumable Pro unlock.
    /// Register this in App Store Connect when preparing v1.2.
    public static let proProductID = "com.centaur-labs.cartogram.pro"

    /// First version distributed as free. Set this to the build number of v1.2
    /// so AppTransaction can distinguish paid-era users from free-era users.
    public static let firstFreeVersion = "2"

    // MARK: - Published State

    @Published public private(set) var isPro: Bool = false
    @Published public private(set) var proProduct: Product?

    // MARK: - Persistence

    /// Set to true in v1.1 while the app is still paid.
    /// Every user who runs v1.1 is a paid user by definition.
    private static let legacyKey = "paidV1User"

    public var isLegacyPaidUser: Bool {
        UserDefaults.standard.bool(forKey: Self.legacyKey)
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Call once at app launch.
    public func configure() async {
        // Step 1: Flag current user as legacy paid (v1.1 — while app is still paid).
        // This is a no-op if already set. Safe to leave in v1.2+.
        if !UserDefaults.standard.bool(forKey: Self.legacyKey) {
            UserDefaults.standard.set(true, forKey: Self.legacyKey)
        }

        // Step 2: Resolve Pro status from all sources.
        await refreshProStatus()

        // Step 3: Listen for StoreKit transaction updates (purchases, restores, revocations).
        listenForTransactions()
    }

    /// Refresh Pro status by checking legacy flag, AppTransaction, and IAP entitlements.
    public func refreshProStatus() async {
        // Fast path: legacy paid user
        if isLegacyPaidUser {
            isPro = true
            return
        }

        // Check AppTransaction for users who paid but missed the v1.1 flag
        if await checkAppTransaction() {
            isPro = true
            return
        }

        // Check StoreKit 2 entitlements (IAP purchase or restore)
        if await checkIAPEntitlement() {
            isPro = true
            return
        }

        isPro = false
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
                    isPro = true
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
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshProStatus()
                }
            }
        }
    }
}
