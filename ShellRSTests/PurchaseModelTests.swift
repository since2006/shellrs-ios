import Foundation
import Testing
import ShellRSCore

@testable import ShellRS

@MainActor
final class MemoryPurchaseCache: PurchaseCacheStore {
    var saved: PurchaseCache?
    var damaged = false
    var failWrites = false
    func read() throws -> PurchaseCache? {
        if damaged { throw PurchaseStoreError.verification }
        return saved
    }
    func write(_ cache: PurchaseCache) throws {
        if failWrites { throw PurchaseStoreError.unavailable }
        saved = cache
    }
}

@MainActor
final class MockPurchaseStore: PurchaseStore {
    var records: [PurchaseRecord] = []
    var complete = true
    var unavailable = false
    var productsUnavailable = false
    var outcome: PurchaseOutcome = .cancelled
    var finished: [UInt64] = []
    var syncs = 0
    var snapshotHook: (() async -> Void)?
    let stream: AsyncStream<PurchaseUpdate>
    let continuation: AsyncStream<PurchaseUpdate>.Continuation
    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }
    func products() async throws -> [PurchaseProduct] {
        if productsUnavailable { throw PurchaseStoreError.unavailable }
        return [
            PurchaseProduct(id: purchaseTestConfiguration.trialID, displayPrice: "$0.00", isFree: true),
            PurchaseProduct(id: purchaseTestConfiguration.lifetimeID, displayPrice: "$9.99", isFree: false),
        ]
    }
    func entitlements() async throws -> PurchaseSnapshot {
        let snapshot = PurchaseSnapshot(records: records, complete: complete)
        if let snapshotHook { await snapshotHook() }
        if unavailable { throw PurchaseStoreError.unavailable }
        return snapshot
    }
    func purchase(_ id: String) async throws -> PurchaseOutcome {
        if unavailable { throw PurchaseStoreError.verification }
        return outcome
    }
    func sync() async throws {
        syncs += 1
        if unavailable { throw PurchaseStoreError.unavailable }
    }
    func updates() -> AsyncStream<PurchaseUpdate> { stream }
    func finish(_ id: UInt64) async { finished.append(id) }
}

let purchaseTestConfiguration = PurchaseConfiguration(trialID: "test.trial", lifetimeID: "test.lifetime")
let purchaseTestDate = Date(timeIntervalSince1970: 1_800_000_000)

func purchaseRecord(lifetime: Bool = false, revoked: Bool = false, signed: Date = purchaseTestDate) -> PurchaseRecord {
    PurchaseRecord(
        id: lifetime ? 2 : 1,
        productID: lifetime ? purchaseTestConfiguration.lifetimeID : purchaseTestConfiguration.trialID,
        originalPurchaseDate: purchaseTestDate, signedDate: signed, revoked: revoked)
}

@MainActor
final class PurchaseTestClock {
    var date = purchaseTestDate
    var uptime: TimeInterval = 100
    func advance(_ interval: TimeInterval) { date += interval; uptime += interval }
}

@MainActor
extension PurchaseModel {
    /// Used only by existing layout/network tests, with no production bypass.
    static func unlockedForTesting() -> PurchaseModel {
        let cache = MemoryPurchaseCache()
        cache.saved = PurchaseCache(
            configuration: purchaseTestConfiguration,
            records: [purchaseRecord(lifetime: true)], highWater: purchaseTestDate)
        return PurchaseModel(configuration: purchaseTestConfiguration, store: MockPurchaseStore(), cache: cache)
    }
}

@MainActor
struct PurchaseModelTests {
    let store = MockPurchaseStore()
    let cache = MemoryPurchaseCache()
    let clock = PurchaseTestClock()

    func make() -> PurchaseModel {
        PurchaseModel(configuration: purchaseTestConfiguration, store: store, cache: cache,
                      now: { clock.date }, uptime: { clock.uptime })
    }

    @Test func noPurchaseAndExplicitTrialClaim() async {
        let model = make()
        #expect(model.state == .loading)
        #expect(!model.canStartNewConnection)
        await model.refresh()
        #expect(model.state == .notStarted)
        #expect(!model.canStartNewConnection)
        store.outcome = .verified(purchaseRecord())
        await model.purchase(purchaseTestConfiguration.trialID)
        #expect(model.canStartNewConnection)
        #expect(store.finished == [1])
        #expect(cache.saved?.records == [purchaseRecord()])
    }

    @Test(arguments: [false, true])
    func presentsOnlyWhenANewConnectionIsDenied(expired: Bool) async {
        if expired {
            store.records = [purchaseRecord()]
            clock.advance(PurchaseModel.trialDuration)
        }
        let model = make()
        await model.start()
        #expect(model.state == (expired ? .trialExpired : .notStarted))
        #expect(!model.presentationRequested)
        await model.refresh()
        #expect(!model.presentationRequested)
        #expect(!model.authorizeConnection())
        #expect(model.presentationRequested)
        model.presentationRequested = false
        model.tick()
        await model.refresh()
        #expect(!model.presentationRequested)
        store.continuation.finish()
    }

    @Test func trialExpiresAtExactlyThirtyDays() async {
        store.records = [purchaseRecord()]
        let model = make()
        await model.refresh()
        clock.advance(29 * 86400)
        #expect(model.canStartNewConnection)
        clock.advance(86400 - 1)
        #expect(model.canStartNewConnection)
        clock.advance(1)
        #expect(!model.canStartNewConnection)
        #expect(model.state == .trialExpired)
        model.tick()
        #expect(!model.presentationRequested)
        #expect(!model.authorizeConnection())
        #expect(model.presentationRequested)
    }

    @Test(arguments: [0.0, 31.0 * 86400])
    func permanentPurchaseOverridesTrial(age: TimeInterval) async {
        store.records = [purchaseRecord()]
        clock.advance(age)
        let model = make()
        await model.refresh()
        store.outcome = .verified(purchaseRecord(lifetime: true))
        await model.purchase(purchaseTestConfiguration.lifetimeID)
        #expect(model.state == .lifetime)
        clock.advance(365 * 86400)
        #expect(model.canStartNewConnection)
    }

    @Test func cancelledPendingAndUnverifiedDoNotGrantAccess() async {
        let model = make()
        await model.refresh()
        await model.purchase(purchaseTestConfiguration.trialID)
        #expect(!model.canStartNewConnection)
        store.outcome = .pending
        await model.purchase(purchaseTestConfiguration.trialID)
        #expect(!model.canStartNewConnection)
        store.unavailable = true
        await model.purchase(purchaseTestConfiguration.lifetimeID)
        #expect(!model.canStartNewConnection)
        #expect(store.finished.isEmpty)
    }

    @Test func restoreUsesOriginalTrialDateOnAnotherDevice() async {
        clock.advance(29 * 86400)
        store.records = [purchaseRecord()]
        let model = make()
        await model.restore()
        #expect(model.canStartNewConnection)
        clock.advance(86400)
        #expect(!model.canStartNewConnection)
        // A clean installation obtains the same original date from StoreKit.
        let reinstalled = PurchaseModel(
            configuration: purchaseTestConfiguration, store: store, cache: MemoryPurchaseCache(),
            now: { clock.date }, uptime: { clock.uptime })
        await reinstalled.restore()
        #expect(reinstalled.state == .trialExpired)
        #expect(store.syncs == 2)
    }

    @Test func restoreLifetimeAndReportNoPurchasesOrFailure() async {
        let model = make()
        await model.restore()
        #expect(model.notice == String(localized: "没有可恢复的购买"))
        store.records = [purchaseRecord(lifetime: true)]
        await model.restore()
        #expect(model.state == .lifetime)
        #expect(model.notice == String(localized: "购买已恢复"))
        store.unavailable = true
        await model.restore()
        #expect(model.state == .lifetime)
        #expect(model.notice == String(localized: "恢复购买失败，请检查网络后重试"))
    }

    @Test func refundsAndEmptyAuthoritativeSnapshotRemoveEntitlements() async {
        store.records = [purchaseRecord(), purchaseRecord(lifetime: true)]
        let model = make()
        await model.refresh()
        store.records = [purchaseRecord(), purchaseRecord(lifetime: true, revoked: true)]
        await model.refresh()
        #expect(model.canStartNewConnection)
        #expect(model.state != .lifetime)
        store.records = [purchaseRecord(revoked: true)]
        await model.refresh()
        #expect(!model.canStartNewConnection)
        store.records = []
        await model.refresh()
        #expect(model.state == .notStarted)
    }

    @Test func verifiedLifetimeSurvivesOfflineRelaunch() async {
        store.records = [purchaseRecord(lifetime: true)]
        await make().refresh()
        store.unavailable = true
        let model = make()
        await model.refresh()
        #expect(model.canStartNewConnection)
        #expect(model.state == .lifetime)
        #expect(model.usingOfflineCache)
    }

    @Test func failedOrUnverifiedQueryIsNotAnEmptyPurchaseHistory() async {
        let model = make()
        store.unavailable = true
        await model.refresh()
        #expect(model.state == .verificationUnavailable)
        #expect(!model.canStartNewConnection)
        store.unavailable = false
        store.complete = false
        store.records = [purchaseRecord(lifetime: true)]
        await model.refresh()
        #expect(model.state == .lifetime)
        #expect(model.usingOfflineCache)
    }

    @Test func clockRollbackCannotRestartOrFreezeAnActiveTrial() async {
        store.records = [purchaseRecord()]
        let model = make()
        await model.refresh()
        clock.advance(29 * 86400)
        model.tick()
        clock.date -= 60 * 86400
        clock.uptime += 86400
        #expect(!model.canStartNewConnection)
        model.tick()
        let relaunched = make()
        #expect(!relaunched.canStartNewConnection)
        await relaunched.refresh()
        #expect(relaunched.state == .trialExpired)
    }

    @Test func corruptOrMismatchingCacheAndMissingProductsDoNotUnlock() async {
        cache.damaged = true
        let model = make()
        #expect(!model.canStartNewConnection)
        store.productsUnavailable = true
        await model.loadProducts()
        #expect(model.products.isEmpty)
        #expect(model.productFailure != nil)
        cache.damaged = false
        cache.saved = PurchaseCache(configuration: .bundled,
                                    records: [purchaseRecord(lifetime: true)], highWater: clock.date)
        #expect(!make().canStartNewConnection)
    }

    @Test func failedPersistenceDoesNotFinishTransaction() async {
        cache.failWrites = true
        store.outcome = .verified(purchaseRecord(lifetime: true))
        let model = make()
        await model.purchase(purchaseTestConfiguration.lifetimeID)
        #expect(model.state == .lifetime)
        #expect(store.finished.isEmpty)
    }

    @Test func updatesHandleRefundDuplicatesAndIgnoreStaleSnapshot() async throws {
        store.records = [purchaseRecord(lifetime: true)]
        let model = make()
        await model.start()
        let refund = purchaseRecord(lifetime: true, revoked: true, signed: purchaseTestDate + 10)
        store.snapshotHook = {
            store.continuation.yield(.verified(refund))
            await Task.yield()
            await Task.yield()
        }
        await model.refresh()
        try await waitUntil("refund update") { model.state != .lifetime }
        #expect(!model.canStartNewConnection)
        store.continuation.yield(.verified(refund))
        store.continuation.yield(.verified(purchaseRecord(lifetime: true)))
        try await waitUntil("duplicate update") { store.finished.count >= 3 }
        #expect(model.state != .lifetime)
        store.continuation.finish()
    }

    @Test func staleSnapshotCannotReinstateAVerifiedRefund() async {
        let model = make()
        store.outcome = .verified(purchaseRecord(lifetime: true, revoked: true, signed: purchaseTestDate + 10))
        await model.purchase(purchaseTestConfiguration.lifetimeID)
        store.records = [purchaseRecord(lifetime: true)]
        await model.refresh()
        #expect(!model.canStartNewConnection)
        #expect(model.state != .lifetime)
    }

    @Test func gateBlocksSSHAndSFTPWithoutDiscardingConfiguration() async throws {
        let core = try TestCore()
        let model = make()
        store.records = [purchaseRecord()]
        await model.refresh()
        let app = AppModel(core: core.core, deviceName: "Test", purchases: model)
        let port = try closedPort()
        let id = try await core.core.store().addHost(draft: draft(port: port, auth: .noPassword), password: .keep, proxyPassword: .keep)
        let host = try #require(core.core.store().host(id: id))
        let terminal = TerminalSession(host: host, core: core.core, purchases: model)
        terminal.start()
        try await waitUntil("initial test connection closes") { terminal.isClosed }
        // No automatic disconnection or configuration changes occur just because time passes.
        let state = terminal.state
        clock.advance(30 * 86400)
        model.tick()
        #expect(terminal.state == state)
        #expect(core.core.store().host(id: id) == host)
        try app.connect(host)
        #expect(app.sessions.isEmpty)
        // Existing workspaces may reconnect under the simplified product policy.
        model.presentationRequested = false
        terminal.start()
        #expect(terminal.state == .connecting)
        #expect(!model.presentationRequested)
        try await waitUntil("test connection closes") { terminal.isClosed }
        let files = terminal.openFiles()
        files.open()
        try await waitUntil("SFTP blocked") { files.state != .connecting }
        #expect(files.state != .connected)
        #expect(model.presentationRequested)
        try core.core.store().deleteHost(id: id)
        #expect(core.core.store().host(id: id) == nil)
    }
}
