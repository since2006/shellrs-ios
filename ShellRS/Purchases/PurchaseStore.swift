import Foundation
import StoreKit

/// The product that removes the ads. Its ID comes from the build
/// configuration (`SHELLRS_REMOVE_ADS_PRODUCT_ID`), never inferred from the
/// bundle identifier.
struct PurchaseConfiguration: Equatable {
    let removeAdsID: String

    static var bundled: Self {
        Self(
            removeAdsID: Bundle.main.object(forInfoDictionaryKey: "ShellRSRemoveAdsProductID")
                as? String ?? "")
    }

    /// A fork may leave it empty; an unexpanded `$(…)` means the build
    /// setting is missing.
    var isConfigured: Bool { !removeAdsID.isEmpty && !removeAdsID.contains("$(") }
}

struct PurchaseProduct: Identifiable, Equatable {
    let id: String
    let displayPrice: String
}

/// Only the StoreKit adapter constructs these, from verified non-consumables
/// of this app.
struct PurchaseRecord: Equatable {
    let id: UInt64
    let productID: String
    let signedDate: Date
    let revoked: Bool
}

struct PurchaseSnapshot {
    let records: [PurchaseRecord]
    /// False when StoreKit returned an entitlement for the product that did
    /// not verify.
    let complete: Bool
}

enum PurchaseOutcome {
    case verified(PurchaseRecord)
    case cancelled
    case pending
}

enum PurchaseStoreError: Error {
    case configuration, unavailable, verification
}

enum PurchaseUpdate {
    case verified(PurchaseRecord)
    case unverified
}

@MainActor
protocol PurchaseStore: AnyObject {
    func product() async throws -> PurchaseProduct?
    func entitlements() async throws -> PurchaseSnapshot
    func purchase(_ id: String) async throws -> PurchaseOutcome
    func sync() async throws
    func updates() -> AsyncStream<PurchaseUpdate>
    func finish(_ id: UInt64) async
}

@MainActor
final class StoreKitPurchaseStore: PurchaseStore {
    private let configuration: PurchaseConfiguration
    private var loaded: Product?
    private var unfinished: [UInt64: StoreKit.Transaction] = [:]

    init(configuration: PurchaseConfiguration) { self.configuration = configuration }

    func product() async throws -> PurchaseProduct? {
        guard configuration.isConfigured else { throw PurchaseStoreError.configuration }
        loaded = try await Product.products(for: [configuration.removeAdsID])
            .first { $0.type == .nonConsumable }
        return loaded.map { PurchaseProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }

    func entitlements() async throws -> PurchaseSnapshot {
        guard configuration.isConfigured else { throw PurchaseStoreError.configuration }
        var records: [PurchaseRecord] = []
        var failed = false
        // StoreKit provides its locally verified entitlements even without a network.
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if let record = record(transaction) { records.append(record) }
            case .unverified(let transaction, _):
                if transaction.productID == configuration.removeAdsID { failed = true }
            }
        }
        return PurchaseSnapshot(records: records, complete: !failed)
    }

    func purchase(_ id: String) async throws -> PurchaseOutcome {
        guard let product = loaded, product.id == id, id == configuration.removeAdsID else {
            throw PurchaseStoreError.unavailable
        }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, let record = record(transaction) else {
                throw PurchaseStoreError.verification
            }
            unfinished[transaction.id] = transaction
            return .verified(record)
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw PurchaseStoreError.unavailable
        }
    }

    func sync() async throws { try await AppStore.sync() }

    func updates() -> AsyncStream<PurchaseUpdate> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    guard let self else { break }
                    switch result {
                    case .verified(let transaction):
                        if let record = self.record(transaction) {
                            unfinished[transaction.id] = transaction
                            continuation.yield(.verified(record))
                        }
                    case .unverified(let transaction, _):
                        if transaction.productID == configuration.removeAdsID {
                            continuation.yield(.unverified)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finish(_ id: UInt64) async {
        guard let transaction = unfinished.removeValue(forKey: id) else { return }
        await transaction.finish()
    }

    private func record(_ transaction: StoreKit.Transaction) -> PurchaseRecord? {
        guard transaction.productID == configuration.removeAdsID,
            transaction.appBundleID == Bundle.main.bundleIdentifier,
            transaction.productType == .nonConsumable
        else { return nil }
        return PurchaseRecord(
            id: transaction.id, productID: transaction.productID,
            signedDate: transaction.signedDate, revoked: transaction.revocationDate != nil)
    }
}
