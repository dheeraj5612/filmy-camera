import Combine
import Foundation
import StoreKit

@MainActor
final class MembershipStore: ObservableObject {
    enum Access: Hashable {
        case checking
        case free
        case premium(until: Date, trial: Bool)
        case unavailable
    }

    struct CapturePermit: Equatable, Sendable {
        let id: UUID
        let chargedDay: Date?
    }

    static let shared = MembershipStore()
    @Published private(set) var access: Access = .checking
    @Published private(set) var remainingPhotos = MembershipPolicy.dailyPhotoLimit
    @Published private(set) var product: Product?
    @Published private(set) var eligibleForOneMonthTrial = false
    @Published private(set) var isWorking = false
    @Published private(set) var isLoadingProduct = false
    @Published var purchaseMessage: String?
    @Published var notice: String?

    private let persistence: any PhotoQuotaPersistence
    let monetizationEnabled: Bool
    private var quota: DailyPhotoQuota?
    private var permits: [UUID: CapturePermit] = [:]
    private var updates: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var productTask: Task<Void, Never>?
    private var testing = false
    private var started = false

    init(persistence: (any PhotoQuotaPersistence)? = nil, useStoreKitForTesting: Bool = false,
         monetizationEnabled: Bool = MonetizationConfiguration.isEnabled) {
        self.monetizationEnabled = monetizationEnabled
        self.persistence = persistence ?? (MonetizationConfiguration.isAutomatedTest
            ? MemoryPhotoQuotaPersistence() : KeychainPhotoQuotaPersistence())
        #if DEBUG
        if MonetizationConfiguration.isAutomatedTest && !useStoreKitForTesting {
            testing = true
            access = ProcessInfo.processInfo.arguments.contains("-ui-testing-monetization-free")
                ? .free : .premium(until: .distantFuture, trial: false)
        }
        #endif
        refreshQuota()
    }

    var isPremium: Bool {
        if case .premium(let expiry, _) = access { return expiry > Date() }
        return false
    }

    // Free releases grant features without inventing a paid entitlement.
    var hasFullAccess: Bool { !monetizationEnabled || isPremium }

    var isTrial: Bool {
        if case .premium(_, let trial) = access { return isPremium && trial }
        return false
    }

    var entitlementsResolved: Bool {
        if !monetizationEnabled { return true }
        switch access {
        case .free: return true
        case .premium(let expiry, _): return expiry > Date()
        case .checking, .unavailable: return false
        }
    }

    var mayShowAds: Bool { monetizationEnabled && access == .free && !testing }
    var canPurchase: Bool { monetizationEnabled && product != nil && entitlementsResolved && !isLoadingProduct && !isWorking && !isPremium && MonetizationConfiguration.legalLinksConfigured }

    func start() async {
        guard !started else { return }
        started = true
        guard monetizationEnabled, !testing else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                if case .verified(let transaction) = result,
                   transaction.productID == MonetizationConfiguration.monthlyProductID {
                    await self.refresh()
                    await transaction.finish()
                } else if case .unverified(let transaction, _) = result,
                          transaction.productID == MonetizationConfiguration.monthlyProductID {
                    // Never grant access, finish, or replace a good entitlement
                    // with an unverified update. Reconcile Apple's signed state.
                    await self.refresh()
                }
            }
        }
        await refresh()
        // Resolve trial labeling without delaying the initial paid unlock.
        if isPremium { await loadProduct(); await refresh() }
    }

    func refresh() async {
        guard monetizationEnabled else { return }
        refreshQuota()
        guard !testing else { return }
        if let refreshTask { await refreshTask.value; return }
        let task = Task<Void, Never> { [weak self] in
            await self?.readEntitlements()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func readEntitlements() async {
        var bestExpiry: Date?
        var bestIsTrial = false
        var sawUnverified = false
        var needsGraceCheck = false
        let now = Date()
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == MonetizationConfiguration.monthlyProductID,
                      transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
                if MembershipPolicy.grantsAccess(verified: true, revoked: transaction.revocationDate != nil,
                    upgraded: transaction.isUpgraded, expiresAt: transaction.expirationDate, now: now),
                   let expiry = transaction.expirationDate {
                    if bestExpiry == nil || expiry > bestExpiry! {
                        bestExpiry = expiry
                        bestIsTrial = transaction.offerType == .introductory && isConfiguredFreeTrial
                    }
                } else {
                    needsGraceCheck = true
                }
            case .unverified(let transaction, _):
                if transaction.productID == MonetizationConfiguration.monthlyProductID { sawUnverified = true }
            }
        }
        // Grace is not inferred from a local boolean or an expired receipt.
        // Both the transaction and renewal info must be verified.
        if needsGraceCheck && bestExpiry == nil {
            if product == nil { await loadProduct() }
            do {
                if let subscription = product?.subscription {
                    for status in try await subscription.status where status.state == .inGracePeriod {
                        guard case .verified(let transaction) = status.transaction,
                              case .verified(let renewal) = status.renewalInfo,
                              transaction.productID == MonetizationConfiguration.monthlyProductID,
                              transaction.revocationDate == nil, !transaction.isUpgraded,
                              let expiry = renewal.gracePeriodExpirationDate, expiry > now else { continue }
                        bestExpiry = max(bestExpiry ?? .distantPast, expiry)
                    }
                } else { sawUnverified = true }
            } catch { sawUnverified = true }
        }
        expiryTask?.cancel()
        if let bestExpiry {
            access = .premium(until: bestExpiry, trial: bestIsTrial)
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(1, bestExpiry.timeIntervalSinceNow))) }
                catch { return }
                await self?.refresh()
            }
        } else {
            access = sawUnverified ? .unavailable : .free
        }
    }

    private var isConfiguredFreeTrial: Bool {
        guard let offer = product?.subscription?.introductoryOffer else { return false }
        return offer.paymentMode == .freeTrial && offer.period.unit == .month
            && offer.period.value == 1 && offer.periodCount == 1
    }

    func loadProduct() async {
        guard monetizationEnabled, !testing else { return }
        if let productTask { await productTask.value; return }
        let task = Task<Void, Never> { [weak self] in await self?.fetchProduct() }
        productTask = task
        await task.value
        productTask = nil
    }

    private func fetchProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [MonetizationConfiguration.monthlyProductID])
            guard let monthly = products.first,
                  monthly.type == .autoRenewable,
                  let subscription = monthly.subscription,
                  subscription.subscriptionPeriod.unit == .month,
                  subscription.subscriptionPeriod.value == 1 else {
                product = nil
                eligibleForOneMonthTrial = false
                purchaseMessage = "Subscriptions are unavailable right now. You can keep using the free camera."
                return
            }
            product = monthly
            let eligible = await subscription.isEligibleForIntroOffer
            eligibleForOneMonthTrial = isConfiguredFreeTrial && eligible
            purchaseMessage = nil
        } catch {
            product = nil
            eligibleForOneMonthTrial = false
            purchaseMessage = "Could not load the App Store price. Check your connection and try again."
        }
    }

    func purchase() async {
        guard monetizationEnabled, !isWorking, !isPremium else { return }
        guard MonetizationConfiguration.legalLinksConfigured else {
            purchaseMessage = "Subscription terms are not available yet. Please try again later."
            return
        }
        if product == nil { await loadProduct() }
        guard let product else { return }
        isWorking = true
        purchaseMessage = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == MonetizationConfiguration.monthlyProductID else {
                    purchaseMessage = "The App Store purchase could not be verified. Try Restore Purchases."
                    return
                }
                await refresh()
                await transaction.finish()
                if !isPremium { purchaseMessage = "The purchase has no active access yet. Try Restore Purchases." }
            case .pending:
                purchaseMessage = "Your purchase is awaiting approval. Premium unlocks after the App Store confirms it."
            case .userCancelled:
                break
            @unknown default:
                purchaseMessage = "The App Store could not complete this purchase. Please try again."
            }
        } catch {
            purchaseMessage = "The purchase did not complete. Check your connection and try again."
        }
    }

    func restore() async {
        guard monetizationEnabled, !isWorking, !testing else { return }
        isWorking = true
        purchaseMessage = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refresh()
            purchaseMessage = isPremium ? "Your subscription is restored." : "No active subscription was found for this Apple Account."
        } catch { purchaseMessage = "Purchases could not be restored. Check your Apple Account and connection, then try again." }
    }

    func allowsRecipe(_ id: String) -> Bool { MembershipPolicy.allowsRecipe(id, premium: hasFullAccess) }

    @discardableResult
    func require(_ feature: PremiumFeature) -> Bool {
        guard !hasFullAccess else { return true }
        if !entitlementsResolved {
            notice = "Your App Store access is being checked. Try again shortly or use Restore Purchases in Account."
        } else {
            MembershipPresentation.showPaywall(feature: feature)
        }
        return false
    }

    @discardableResult
    func requireRecipe(_ id: String) -> Bool {
        allowsRecipe(id) || require(.allRecipes)
    }

    func reserveCapture() -> CapturePermit? {
        guard entitlementsResolved else {
            notice = "Your App Store access is being checked. Please try again shortly."
            return nil
        }
        if hasFullAccess {
            let permit = CapturePermit(id: UUID(), chargedDay: nil)
            permits[permit.id] = permit
            return permit
        }
        refreshQuota()
        guard var next = quota else {
            notice = "The daily photo allowance could not be read. Unlock your device and try again."
            return nil
        }
        guard let day = next.reserve(at: Date()) else {
            MembershipPresentation.showPaywall(feature: .unlimitedPhotos)
            return nil
        }
        do { try persistence.save(next) }
        catch {
            notice = "The daily photo allowance could not be saved. Please try again."
            return nil
        }
        quota = next
        remainingPhotos = next.remaining
        let permit = CapturePermit(id: UUID(), chargedDay: day)
        permits[permit.id] = permit
        return permit
    }

    func finishCapture(_ permit: CapturePermit, succeeded: Bool) {
        guard let existing = permits.removeValue(forKey: permit.id), existing == permit,
              !succeeded, let day = permit.chargedDay, var next = quota else { return }
        next.refund(reservedDay: day)
        do {
            try persistence.save(next)
            quota = next
            remainingPhotos = next.remaining
        } catch { notice = "A failed capture could not be refunded because secure storage is unavailable. Your allowance resets on the next day." }
    }

    func refreshQuota() {
        do {
            var next = try persistence.load() ?? DailyPhotoQuota(now: Date())
            next.advance(to: Date())
            try persistence.save(next)
            quota = next
            remainingPhotos = next.remaining
        } catch {
            quota = nil
            remainingPhotos = 0
        }
    }

    #if DEBUG
    func setAccessForTesting(_ access: Access) {
        testing = true
        self.access = access
    }
    #endif
}
