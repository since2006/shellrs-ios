import Foundation
import Observation

/// Cached only after verification, in this app's device-only keychain.
struct PurchaseCache: Codable {
    let configuration: PurchaseConfiguration
    let records: [PurchaseRecord]
    let highWater: Date
}

@MainActor
protocol PurchaseCacheStore {
    func read() throws -> PurchaseCache?
    func write(_ cache: PurchaseCache) throws
}

struct KeychainPurchaseCache: PurchaseCacheStore {
    private let keychain = AppKeychain(service: "com.shellrs.ios.purchases")
    func read() throws -> PurchaseCache? {
        guard let text = try keychain.get(account: "verified-v1") else { return nil }
        return try JSONDecoder().decode(PurchaseCache.self, from: Data(text.utf8))
    }
    func write(_ cache: PurchaseCache) throws {
        try keychain.set(account: "verified-v1", value: String(decoding: JSONEncoder().encode(cache), as: UTF8.self))
    }
}

enum PurchaseState: Equatable {
    case loading
    case notStarted
    case trialActive(startDate: Date, expiresAt: Date, remainingTime: TimeInterval)
    case trialExpired
    case lifetime
    case verificationUnavailable
}

struct PurchaseAccessError: LocalizedError {
    var errorDescription: String? { String(localized: "请领取免费试用或永久解锁后再建立连接") }
}

@MainActor
@Observable
final class PurchaseModel {
    static let trialDuration: TimeInterval = 30 * 24 * 60 * 60
    let configuration: PurchaseConfiguration
    private(set) var state = PurchaseState.loading
    private(set) var products: [PurchaseProduct] = []
    private(set) var working = false
    private(set) var loadingProducts = false
    private(set) var productFailure: String?
    private(set) var usingOfflineCache = false
    var notice: String?
    var presentationRequested = false

    @ObservationIgnored private let store: any PurchaseStore
    @ObservationIgnored private let cache: any PurchaseCacheStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private var records: [PurchaseRecord] = []
    @ObservationIgnored private var highWater: Date
    @ObservationIgnored private var anchorUptime: TimeInterval
    @ObservationIgnored private var known = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastPersisted: Date

    init(
        configuration: PurchaseConfiguration = .bundled,
        store: (any PurchaseStore)? = nil,
        cache: any PurchaseCacheStore = KeychainPurchaseCache(),
        now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.configuration = configuration
        self.store = store ?? StoreKitPurchaseStore(configuration: configuration)
        self.cache = cache
        self.now = now
        self.uptime = uptime
        let saved = try? cache.read()
        let matching = saved?.configuration == configuration ? saved : nil
        records = matching?.records ?? []
        // Invalid cache never grants an entitlement. Successful empty snapshots are cached too.
        known = matching != nil
        highWater = max(now(), matching?.highWater ?? .distantPast)
        anchorUptime = uptime()
        lastPersisted = highWater
        if known {
            usingOfflineCache = true
            evaluate()
            _ = persist()
        }
    }

    deinit { listener?.cancel(); ticker?.cancel(); refreshTask?.cancel() }

    var trialProduct: PurchaseProduct? {
        products.first { $0.id == configuration.trialID && $0.isFree }
    }
    var lifetimeProduct: PurchaseProduct? { products.first { $0.id == configuration.lifetimeID } }

    /// The sole policy entry point. It evaluates the clock at the actual operation,
    /// so a suspended UI or a delayed foreground refresh cannot extend the trial.
    var canStartNewConnection: Bool {
        evaluate()
        switch state {
        case .lifetime, .trialActive: return true
        default: return false
        }
    }

    @discardableResult
    func authorizeConnection() -> Bool {
        guard canStartNewConnection else {
            presentationRequested = true
            return false
        }
        return true
    }

    func start() async {
        guard !started else { return }
        started = true
        let updates = store.updates() // Subscribe before the first query/purchase.
        listener = Task { [weak self, store] in
            for await update in updates {
                guard let self else { break }
                switch update {
                case .verified(let record):
                    self.apply(record)
                    if self.persist() { await store.finish(record.id) }
                case .unverified:
                    self.usingOfflineCache = true
                    self.notice = String(localized: "暂时无法验证购买，请稍后恢复购买")
                    self.evaluate()
                }
            }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                self.tick()
            }
        }
        await refresh()
        await loadProducts()
    }

    func tick() {
        evaluate()
        if case .trialActive = state, highWater.timeIntervalSince(lastPersisted) >= 60 {
            _ = persist()
        }
    }

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            let version = revision
            do {
                let fetched = try await store.entitlements()
                // A purchase/update delivered during this query is newer than its snapshot.
                if version == revision {
                    if fetched.complete {
                        let previous = records
                        records = fetched.records.map { incoming in
                            if let revoked = previous.first(where: { $0.id == incoming.id && $0.revoked && $0.signedDate >= incoming.signedDate }) {
                                return revoked
                            }
                            return incoming
                        }
                        records += previous.filter { old in
                            old.revoked && !records.contains(where: { $0.id == old.id })
                        }
                        known = true
                    } else {
                        for record in fetched.records { apply(record) }
                    }
                    usingOfflineCache = !fetched.complete
                    evaluate(signedDate: fetched.records.map(\.signedDate).max())
                    _ = persist()
                }
            } catch {
                usingOfflineCache = true
                evaluate()
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        tick()
    }

    func loadProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            products = try await store.products()
            productFailure = trialProduct == nil || lifetimeProduct == nil
                ? String(localized: "部分商品暂不可用，请稍后重试") : nil
        } catch {
            products = []
            productFailure = configuration.isConfigured
                ? String(localized: "无法加载 App Store 商品，请检查网络后重试")
                : String(localized: "购买商品尚未配置，请稍后重试")
        }
    }

    func purchase(_ id: String) async {
        guard !working else { return }
        working = true
        notice = nil
        defer { working = false }
        do {
            switch try await store.purchase(id) {
            case .verified(let record):
                apply(record)
                if persist() { await store.finish(record.id) }
                notice = record.revoked
                    ? String(localized: "这笔购买已撤销")
                    : String(localized: "购买已处理，授权状态已更新")
            case .cancelled: notice = String(localized: "购买已取消")
            case .pending: notice = String(localized: "购买待批准，批准后会自动更新授权")
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
            if usingOfflineCache {
                notice = String(localized: "暂时无法验证购买，请稍后恢复购买")
            } else {
                switch state {
                case .lifetime, .trialActive: notice = String(localized: "购买已恢复")
                case .trialExpired: notice = String(localized: "已恢复试用记录，30 天试用已到期")
                default: notice = String(localized: "没有可恢复的购买")
                }
            }
        } catch {
            notice = String(localized: "恢复购买失败，请检查网络后重试")
        }
    }

    private func apply(_ record: PurchaseRecord) {
        guard configuration.ids.contains(record.productID) else { return }
        // Stable transaction ID and signedDate make duplicates and older updates harmless.
        if let old = records.first(where: { $0.id == record.id }),
            old.signedDate > record.signedDate || (old.revoked && old.signedDate == record.signedDate) { return }
        records.removeAll { $0.id == record.id }
        records.append(record)
        revision += 1
        known = true
        usingOfflineCache = false
        evaluate(signedDate: record.signedDate)
    }

    private func evaluate(signedDate: Date? = nil) {
        let currentUptime = uptime()
        highWater = max(highWater.addingTimeInterval(max(0, currentUptime - anchorUptime)), now(), signedDate ?? .distantPast)
        anchorUptime = currentUptime
        let old = state
        let valid = records.filter { !$0.revoked }
        if valid.contains(where: { $0.productID == configuration.lifetimeID }) {
            state = .lifetime
        } else if let start = valid.filter({ $0.productID == configuration.trialID }).map(\.originalPurchaseDate).min() {
            let expires = start.addingTimeInterval(Self.trialDuration)
            state = highWater < expires
                ? .trialActive(startDate: start, expiresAt: expires, remainingTime: expires.timeIntervalSince(highWater))
                : .trialExpired
        } else {
            state = known && !usingOfflineCache ? .notStarted : (usingOfflineCache ? .verificationUnavailable : .loading)
        }
        if case .trialActive = old, state == .trialExpired {
            _ = persist()
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard known else { return false }
        do {
            try cache.write(PurchaseCache(configuration: configuration, records: records, highWater: highWater))
            lastPersisted = highWater
            return true
        } catch {
            // Leave the transaction unfinished: StoreKit will deliver it again.
            return false
        }
    }
}
