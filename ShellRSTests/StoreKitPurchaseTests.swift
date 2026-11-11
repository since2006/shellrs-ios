import Foundation
import StoreKitTest
import Testing

@testable import ShellRS

private final class StoreKitBundleToken: NSObject {}

/// Uses Xcode's signed local transactions; no Apple account or real charges.
@MainActor
@Suite(.serialized)
struct StoreKitPurchaseTests {
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["SHELLRS_TEST_STOREKIT"] == "1"))
    func localRemoveAdsPurchaseRestoreAndRefund() async throws {
        let url = try #require(
            Bundle(for: StoreKitBundleToken.self).url(forResource: "Purchases", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let configuration = PurchaseConfiguration(removeAdsID: "com.shellrs.ios.lifetime")
        let store = StoreKitPurchaseStore(configuration: configuration)
        let product = try #require(try await store.product())
        #expect(product.id == configuration.removeAdsID)

        let model = PurchaseModel(configuration: configuration, store: store)
        await model.start()
        #expect(model.adRemoval == .notPurchased)
        await model.purchase()
        #expect(model.adRemoval == .purchased)

        let restored = try await store.entitlements()
        #expect(restored.complete)
        let record = try #require(restored.records.first)
        await model.restore()
        #expect(model.notice == String(localized: "购买已恢复"))

        try session.refundTransaction(identifier: UInt(record.id))
        try await waitUntil("StoreKit refund update") { model.adRemoval == .notPurchased }
        #expect(model.adRemoval == .notPurchased)
    }
}
