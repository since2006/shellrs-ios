import Foundation
import StoreKit

/// IDs come from build configuration, never inferred from the bundle identifier.
struct PurchaseConfiguration: Codable, Equatable {
    let trialID: String
    let lifetimeID: String

    static var bundled: Self {
        Self(
            trialID: Bundle.main.object(forInfoDictionaryKey: "ShellRSTrialProductID") as? String ?? "",
            lifetimeID: Bundle.main.object(forInfoDictionaryKey: "ShellRSLifetimeProductID") as? String ?? "")
    }

    var isConfigured: Bool {
        !trialID.isEmpty && !lifetimeID.isEmpty && trialID != lifetimeID
            && !trialID.contains("$(") && !lifetimeID.contains("$(")
    }
    var ids: Set<String> { [trialID, lifetimeID] }
}

struct PurchaseProduct: Identifiable, Equatable {
    let id: String
    let displayPrice: String
    let isFree: Bool
}

/// Only the StoreKit adapter constructs these from verified, matching non-consumables.
struct PurchaseRecord: Codable, Equatable {
    let id: UInt64
    let productID: String
    let originalPurchaseDate: Date
    let signedDate: Date
    let revoked: Bool
}

struct PurchaseSnapshot {
    let records: [PurchaseRecord]
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
    func products() async throws -> [PurchaseProduct]
    func entitlements() async throws -> PurchaseSnapshot
    func purchase(_ id: String) async throws -> PurchaseOutcome
    func sync() async throws
    func updates() -> AsyncStream<PurchaseUpdate>
    func finish(_ id: UInt64) async
}

@MainActor
final class StoreKitPurchaseStore: PurchaseStore {
    private let configuration: PurchaseConfiguration
    private var loaded: [String: Product] = [:]
    private var unfinished: [UInt64: StoreKit.Transaction] = [:]

    init(configuration: PurchaseConfiguration) { self.configuration = configuration }

    func products() async throws -> [PurchaseProduct] {
        guard configuration.isConfigured else { throw PurchaseStoreError.configuration }
        let products = try await Product.products(for: configuration.ids)
        loaded = Dictionary(uniqueKeysWithValues: products.filter { $0.type == .nonConsumable }.map { ($0.id, $0) })
        return loaded.values.map { PurchaseProduct(id: $0.id, displayPrice: $0.displayPrice, isFree: $0.price == 0) }
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
                if configuration.ids.contains(transaction.productID) { failed = true }
            }
        }
        // A partial or unverified query must never erase a previously verified purchase.
        if records.contains(where: { $0.productID == configuration.trialID }),
            let start = await earliestTrialStart()
        {
            records = records.map { withTrialStart($0, start: start) }
        }
        return PurchaseSnapshot(records: records, complete: !failed)
    }

    func purchase(_ id: String) async throws -> PurchaseOutcome {
        guard let product = loaded[id], configuration.ids.contains(id),
            product.type == .nonConsumable,
            id != configuration.trialID || product.price == 0
        else { throw PurchaseStoreError.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result, let record = record(transaction) else {
                throw PurchaseStoreError.verification
            }
            unfinished[transaction.id] = transaction
            let start = record.productID == configuration.trialID ? await earliestTrialStart() : nil
            return .verified(withTrialStart(record, start: start))
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
                            let start = record.productID == configuration.trialID ? await earliestTrialStart() : nil
                            continuation.yield(.verified(withTrialStart(record, start: start)))
                        }
                    case .unverified(let transaction, _):
                        if configuration.ids.contains(transaction.productID) {
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

    private func earliestTrialStart() async -> Date? {
        var earliest: Date?
        // Includes revoked history: a later repurchase must not reset the 30 days.
        for await result in StoreKit.Transaction.all {
            guard case .verified(let transaction) = result,
                transaction.productID == configuration.trialID,
                record(transaction) != nil else { continue }
            earliest = min(earliest ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
        }
        return earliest
    }

    private func withTrialStart(_ record: PurchaseRecord, start: Date?) -> PurchaseRecord {
        guard record.productID == configuration.trialID, let start else { return record }
        return PurchaseRecord(id: record.id, productID: record.productID,
                              originalPurchaseDate: min(start, record.originalPurchaseDate),
                              signedDate: record.signedDate, revoked: record.revoked)
    }

    private func record(_ transaction: StoreKit.Transaction) -> PurchaseRecord? {
        guard configuration.ids.contains(transaction.productID),
            transaction.appBundleID == Bundle.main.bundleIdentifier,
            transaction.productType == .nonConsumable
        else { return nil }
        return PurchaseRecord(
            id: transaction.id, productID: transaction.productID,
            originalPurchaseDate: transaction.originalPurchaseDate,
            signedDate: transaction.signedDate, revoked: transaction.revocationDate != nil)
    }
}
