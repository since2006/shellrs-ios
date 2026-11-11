import Foundation
import Testing

@testable import ShellRS

@MainActor
final class MockPurchaseStore: PurchaseStore {
    var records: [PurchaseRecord] = []
    var complete = true
    var unavailable = false
    var productUnavailable = false
    var outcome: PurchaseOutcome = .cancelled
    var purchased: [String] = []
    var finished: [UInt64] = []
    var syncs = 0
    var snapshotHook: (() async -> Void)?
    let stream: AsyncStream<PurchaseUpdate>
    let continuation: AsyncStream<PurchaseUpdate>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func product() async throws -> PurchaseProduct? {
        if productUnavailable { throw PurchaseStoreError.unavailable }
        return PurchaseProduct(id: purchaseTestConfiguration.removeAdsID, displayPrice: "$2.99")
    }

    func entitlements() async throws -> PurchaseSnapshot {
        let snapshot = PurchaseSnapshot(records: records, complete: complete)
        if let snapshotHook { await snapshotHook() }
        if unavailable { throw PurchaseStoreError.unavailable }
        return snapshot
    }

    func purchase(_ id: String) async throws -> PurchaseOutcome {
        purchased.append(id)
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

let purchaseTestConfiguration = PurchaseConfiguration(removeAdsID: "test.removeads")
let purchaseTestDate = Date(timeIntervalSince1970: 1_800_000_000)

func purchaseRecord(
    id: UInt64 = 1, productID: String = purchaseTestConfiguration.removeAdsID, revoked: Bool = false,
    signed: Date = purchaseTestDate
) -> PurchaseRecord {
    PurchaseRecord(id: id, productID: productID, signedDate: signed, revoked: revoked)
}

/// The one purchase removes the ads; nothing in the app waits for it.
@MainActor
struct PurchaseModelTests {
    let store = MockPurchaseStore()

    func make() -> PurchaseModel {
        PurchaseModel(configuration: purchaseTestConfiguration, store: store)
    }

    @Test func unknownUntilStoreKitAnswersThenNotPurchased() async {
        let model = make()
        #expect(model.adRemoval == .unknown)
        await model.start()
        #expect(model.adRemoval == .notPurchased)
        #expect(model.product?.displayPrice == "$2.99")
        store.continuation.finish()
    }

    @Test func anEntitlementAtLaunchRemovesTheAds() async {
        store.records = [purchaseRecord()]
        let model = make()
        await model.start()
        #expect(model.adRemoval == .purchased)
        #expect(model.adsRemoved)
        store.continuation.finish()
    }

    @Test func buyingRemovesTheAdsAndFinishesTheTransaction() async {
        let model = make()
        await model.start()
        store.outcome = .verified(purchaseRecord(id: 7))
        await model.purchase()
        #expect(store.purchased == [purchaseTestConfiguration.removeAdsID])
        #expect(model.adRemoval == .purchased)
        #expect(store.finished == [7])
        #expect(model.notice == String(localized: "广告已去除，谢谢支持"))
        store.continuation.finish()
    }

    @Test func cancelledPendingAndFailedPurchasesChangeNothing() async {
        let model = make()
        await model.start()
        store.outcome = .cancelled
        await model.purchase()
        #expect(model.adRemoval == .notPurchased)
        #expect(model.notice == String(localized: "购买已取消"))
        store.outcome = .pending
        await model.purchase()
        #expect(model.adRemoval == .notPurchased)
        #expect(model.notice == String(localized: "购买待批准，批准后会自动去除广告"))
        store.unavailable = true
        await model.purchase()
        #expect(model.adRemoval == .notPurchased)
        #expect(model.notice == String(localized: "购买未完成或未能验证，请稍后重试或恢复购买"))
        #expect(store.finished.isEmpty)
        store.continuation.finish()
    }

    @Test func withoutTheProductThePurchaseSaysSo() async {
        store.productUnavailable = true
        let model = make()
        await model.start()
        await model.purchase()
        #expect(store.purchased.isEmpty)
        #expect(model.notice == String(localized: "暂时无法连接 App Store，请稍后重试"))
        store.continuation.finish()
    }

    @Test func restoreFindsThePurchaseOrSaysThereIsNone() async {
        let model = make()
        await model.start()
        await model.restore()
        #expect(store.syncs == 1)
        #expect(model.notice == String(localized: "没有可恢复的购买"))
        store.records = [purchaseRecord()]
        await model.restore()
        #expect(model.adRemoval == .purchased)
        #expect(model.notice == String(localized: "购买已恢复"))
        store.unavailable = true
        await model.restore()
        #expect(model.notice == String(localized: "恢复购买失败，请检查网络后重试"))
        store.continuation.finish()
    }

    @Test func aRefundBringsTheAdsBackAndAStaleSnapshotKeepsItRevoked() async throws {
        store.records = [purchaseRecord()]
        let model = make()
        await model.start()
        #expect(model.adRemoval == .purchased)
        store.continuation.yield(.verified(purchaseRecord(revoked: true, signed: purchaseTestDate + 60)))
        try await waitUntil("refund update") { model.adRemoval == .notPurchased }
        // StoreKit's entitlements may still list it for a moment.
        await model.refresh()
        #expect(model.adRemoval == .notPurchased)
        store.continuation.finish()
    }

    @Test func duplicateAndOlderUpdatesAreHarmless() async throws {
        let model = make()
        await model.start()
        store.continuation.yield(.verified(purchaseRecord(revoked: true, signed: purchaseTestDate + 60)))
        try await waitUntil("refund update") { store.finished.count == 1 }
        store.continuation.yield(.verified(purchaseRecord(signed: purchaseTestDate)))
        try await waitUntil("older update") { store.finished.count == 2 }
        #expect(model.adRemoval == .notPurchased)
        store.continuation.finish()
    }

    @Test func anUnverifiedEntitlementNeitherRemovesTheAdsNorErasesAVerifiedOne() async {
        store.complete = false
        let model = make()
        await model.start()
        #expect(model.adRemoval == .notPurchased)
        store.complete = true
        store.records = [purchaseRecord()]
        await model.refresh()
        #expect(model.adRemoval == .purchased)
        store.complete = false
        store.records = []
        await model.refresh()
        #expect(model.adRemoval == .purchased)
        store.continuation.finish()
    }

    @Test func aPurchaseDuringAQueryWinsOverItsSnapshot() async {
        let model = make()
        await model.start()
        store.snapshotHook = { [store] in
            store.snapshotHook = nil
            store.continuation.yield(.verified(purchaseRecord(id: 9)))
            try? await Task.sleep(for: .milliseconds(100))
        }
        await model.refresh()
        #expect(model.adRemoval == .purchased)
        store.continuation.finish()
    }

    @Test func otherProductsAreIgnored() async throws {
        store.records = [purchaseRecord(productID: "test.other")]
        let model = make()
        await model.start()
        #expect(model.adRemoval == .notPurchased)
        store.continuation.yield(.verified(purchaseRecord(id: 3, productID: "test.other")))
        try await waitUntil("update") { store.finished == [3] }
        #expect(model.adRemoval == .notPurchased)
        store.continuation.finish()
    }

    @Test func withoutAProductThereIsNothingToBuyAndTheAdsShow() async {
        let model = PurchaseModel(configuration: PurchaseConfiguration(removeAdsID: ""), store: store)
        await model.start()
        #expect(model.adRemoval == .notPurchased)
        #expect(store.syncs == 0)
        store.continuation.finish()
    }
}
