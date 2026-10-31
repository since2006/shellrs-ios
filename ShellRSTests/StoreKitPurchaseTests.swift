import Foundation
import StoreKitTest
import Testing

@testable import ShellRS

private final class StoreKitBundleToken: NSObject {}

/// Uses Xcode's signed local transactions; no Apple account or real charges.
@MainActor
@Suite(.serialized)
struct StoreKitPurchaseTests {
    @Test(.timeLimit(.minutes(1)), .enabled(if: ProcessInfo.processInfo.environment["SHELLRS_TEST_STOREKIT"] == "1"))
    func localProductsTrialLifetimeRestoreAndRefund() async throws {
        let url = try #require(Bundle(for: StoreKitBundleToken.self).url(forResource: "Purchases", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let configuration = PurchaseConfiguration(trialID: "com.shellrs.ios.trial30", lifetimeID: "com.shellrs.ios.lifetime")
        let store = StoreKitPurchaseStore(configuration: configuration)
        let products = try await store.products()
        #expect(products.count == 2)
        #expect(products.first { $0.id == configuration.trialID }?.isFree == true)
        guard case .verified(let trial) = try await store.purchase(configuration.trialID) else {
            Issue.record("Local trial purchase did not verify")
            return
        }
        #expect(!trial.revoked)
        await store.finish(trial.id)
        let restored = try await store.entitlements()
        #expect(restored.complete)
        #expect(restored.records.first { $0.productID == configuration.trialID }?.originalPurchaseDate == trial.originalPurchaseDate)
        guard case .verified(let lifetime) = try await store.purchase(configuration.lifetimeID) else {
            Issue.record("Local lifetime purchase did not verify")
            return
        }
        await store.finish(lifetime.id)
        let cache = MemoryPurchaseCache()
        let model = PurchaseModel(configuration: configuration, store: store, cache: cache)
        await model.start()
        #expect(model.state == .lifetime)
        await model.restore()
        #expect(model.notice == String(localized: "购买已恢复"))
        try session.refundTransaction(identifier: UInt(lifetime.id))
        try await waitUntil("StoreKit refund update") { model.state != .lifetime }
        #expect(model.state != .lifetime)
        #expect(model.canStartNewConnection) // The original trial remains valid.
        try session.refundTransaction(identifier: UInt(trial.id))
        try await waitUntil("trial revocation update") { !model.canStartNewConnection }
        guard case .verified(let reclaimed) = try await store.purchase(configuration.trialID) else {
            Issue.record("Reclaimed trial did not verify")
            return
        }
        #expect(reclaimed.originalPurchaseDate == trial.originalPurchaseDate)
        await store.finish(reclaimed.id)
    }
}
