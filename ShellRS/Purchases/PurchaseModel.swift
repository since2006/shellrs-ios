import Foundation
import Observation

/// Whether the ads have been bought away. Everything else in the app is free.
enum AdRemoval: Equatable {
    /// StoreKit has not answered yet: no ads, so that whoever bought the
    /// removal never sees one flash by at launch.
    case unknown
    case notPurchased
    case purchased
}

/// The one in-app purchase: a non-consumable that removes the ads.
@MainActor
@Observable
final class PurchaseModel {
    let configuration: PurchaseConfiguration
    private(set) var adRemoval = AdRemoval.unknown
    private(set) var product: PurchaseProduct?
    private(set) var working = false
    var notice: String?

    @ObservationIgnored private let store: any PurchaseStore
    @ObservationIgnored private var records: [UInt64: PurchaseRecord] = [:]
    /// Bumped by every purchase or update, so that an entitlement query
    /// started before one does not overwrite it.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(configuration: PurchaseConfiguration = .bundled, store: (any PurchaseStore)? = nil) {
        self.configuration = configuration
        self.store = store ?? StoreKitPurchaseStore(configuration: configuration)
    }

    deinit { listener?.cancel(); refreshTask?.cancel() }

    var adsRemoved: Bool { adRemoval == .purchased }

    func start() async {
        guard !started else { return }
        started = true
        guard configuration.isConfigured else {
            // Nothing to buy: a build without the product shows its ads, if any.
            adRemoval = .notPurchased
            return
        }
        let updates = store.updates()  // Subscribe before the first query or purchase.
        listener = Task { [weak self, store] in
            for await update in updates {
                guard let self else { break }
                if case .verified(let record) = update {
                    self.apply(record)
                    await store.finish(record.id)
                }
            }
        }
        await refresh()
        await loadProduct()
    }

    /// Asks StoreKit again, as at launch: on coming back to the foreground
    /// a refund may have arrived.
    func refresh() async {
        guard configuration.isConfigured else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let version = revision
            let snapshot = try? await store.entitlements()
            // A purchase or update delivered during this query is newer than its snapshot.
            guard version == revision else { return }
            if let snapshot, snapshot.complete {
                let previous = records
                records = [:]
                for record in snapshot.records where record.productID == configuration.removeAdsID {
                    // An update that revoked it is newer than a stale entitlement.
                    if let old = previous[record.id], old.revoked, old.signedDate >= record.signedDate {
                        records[record.id] = old
                    } else {
                        records[record.id] = record
                    }
                }
                for old in previous.values where old.revoked && records[old.id] == nil {
                    records[old.id] = old
                }
            } else {
                // An unverified entitlement never removes the ads, nor erases one that verified.
                for record in snapshot?.records ?? [] { merge(record) }
            }
            evaluate()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func loadProduct() async {
        guard configuration.isConfigured, product == nil else { return }
        product = try? await store.product()
    }

    func purchase() async {
        guard !working else { return }
        working = true
        notice = nil
        defer { working = false }
        await loadProduct()
        guard let product else {
            notice = String(localized: "暂时无法连接 App Store，请稍后重试")
            return
        }
        do {
            switch try await store.purchase(product.id) {
            case .verified(let record):
                apply(record)
                await store.finish(record.id)
                notice = record.revoked
                    ? String(localized: "这笔购买已撤销")
                    : String(localized: "广告已去除，谢谢支持")
            case .cancelled:
                notice = String(localized: "购买已取消")
            case .pending:
                notice = String(localized: "购买待批准，批准后会自动去除广告")
            }
        } catch {
            notice = String(localized: "购买未完成或未能验证，请稍后重试或恢复购买")
        }
    }

    func restore() async {
        guard !working else { return }
        working = true
        notice = nil
        defer { working = false }
        do {
            try await store.sync()
            await refresh()
            notice = adsRemoved
                ? String(localized: "购买已恢复") : String(localized: "没有可恢复的购买")
        } catch {
            notice = String(localized: "恢复购买失败，请检查网络后重试")
        }
    }

    private func apply(_ record: PurchaseRecord) {
        guard merge(record) else { return }
        revision += 1
        evaluate()
    }

    /// Stable transaction IDs and signed dates make duplicates and older
    /// updates harmless.
    @discardableResult
    private func merge(_ record: PurchaseRecord) -> Bool {
        guard record.productID == configuration.removeAdsID else { return false }
        if let old = records[record.id],
            old.signedDate > record.signedDate || (old.revoked && old.signedDate == record.signedDate)
        {
            return false
        }
        records[record.id] = record
        return true
    }

    private func evaluate() {
        adRemoval = records.values.contains { !$0.revoked } ? .purchased : .notPurchased
    }
}
