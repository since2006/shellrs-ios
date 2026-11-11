import Foundation
import Observation

/// Where an ad goes, one each. Never over a terminal or its files.
enum AdPlacement: Hashable, CaseIterable {
    /// The 主机 tab of a narrow window, after 最近连接.
    case hosts
    /// The 终端 tab of a narrow window, after the terminals.
    case sessions
    /// A wide window's start page, after the hosts connected lately.
    case start
}

/// The ad unit from the build configuration (`SHELLRS_NATIVE_AD_UNIT_ID`).
/// Empty, as a fork without ads sets it, in the test host, or with
/// `SHELLRS_DISABLE_ADS=1` (screenshots): no ads, and the ads SDK and its
/// consent form never start.
struct AdsConfiguration: Equatable {
    let nativeAdUnitID: String

    static var bundled: Self {
        let environment = ProcessInfo.processInfo.environment
        let off =
            environment["XCTestConfigurationFilePath"] != nil
            || environment["SHELLRS_DISABLE_ADS"] == "1"
        let id = Bundle.main.object(forInfoDictionaryKey: "ShellRSNativeAdUnitID") as? String ?? ""
        return Self(nativeAdUnitID: off ? "" : id)
    }

    var isEnabled: Bool { !nativeAdUnitID.isEmpty && !nativeAdUnitID.contains("$(") }
}

/// A native ad, loaded: what a card shows.
struct LoadedAd: Identifiable {
    let id = UUID()
    /// The SDK's `NativeAd`, opaque here so that the model builds without
    /// the SDK.
    let content: AnyObject
    let loadedAt: Date
}

/// The ads SDK and its consent form, as the model needs them.
@MainActor
protocol AdsService: AnyObject {
    /// Updates what the user agreed to, asking them if the law says it must,
    /// then whether ads may be requested.
    func gatherConsent() async -> Bool
    /// Whether the settings must offer to change that answer (GDPR).
    var privacyOptionsRequired: Bool { get }
    func presentPrivacyOptions() async
    func startSDK()
    func loadNativeAd() async throws -> AnyObject
}

/// The ads: none until StoreKit says they were not bought away, then the
/// consent form where the law asks for it, then one native ad per
/// placement, loaded when it is shown.
@MainActor
@Observable
final class AdsModel {
    /// Google asks not to show an ad loaded more than an hour ago.
    static let lifetime: TimeInterval = 60 * 60
    /// After a failed load, how long before that placement tries again.
    static let retryDelay: TimeInterval = 60

    /// Consent is settled and the SDK started: ads can be requested.
    private(set) var ready = false
    private(set) var privacyOptionsRequired = false
    private(set) var adRemoval = AdRemoval.unknown
    private var loaded: [AdPlacement: LoadedAd] = [:]

    @ObservationIgnored private let service: (any AdsService)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loading: Set<AdPlacement> = []
    @ObservationIgnored private var failedAt: [AdPlacement: Date] = [:]
    @ObservationIgnored private var starting = false

    init(service: (any AdsService)? = AdsModel.bundledService(), now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    /// The service for this build: none when the ad unit is not set or the
    /// Google packages were taken out.
    static func bundledService(_ configuration: AdsConfiguration = .bundled) -> (any AdsService)? {
        guard configuration.isEnabled else { return nil }
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
            return GoogleAdsService(nativeAdUnitID: configuration.nativeAdUnitID)
        #else
            return nil
        #endif
    }

    /// Whether this build has ads at all: without them the settings have
    /// no 广告 section.
    var isAvailable: Bool { service != nil }

    func ad(for placement: AdPlacement) -> LoadedAd? {
        adRemoval == .notPurchased ? loaded[placement] : nil
    }

    /// Follows the purchase: nothing until StoreKit answers, nothing more
    /// once the ads are bought away (not even the SDK, on the next launch).
    func purchaseChanged(_ removal: AdRemoval) async {
        adRemoval = removal
        switch removal {
        case .unknown:
            break
        case .purchased:
            loaded = [:]
        case .notPurchased:
            await start()
        }
    }

    /// Consent may not have been settled at launch, offline.
    func cameForward() async {
        if adRemoval == .notPurchased {
            await start()
        }
    }

    /// Loads the ad of `placement` unless it has one that is still fresh, or
    /// failed a moment ago.
    func prepare(_ placement: AdPlacement) async {
        guard ready, adRemoval == .notPurchased, let service, !loading.contains(placement) else {
            return
        }
        let time = now()
        if let ad = loaded[placement], time.timeIntervalSince(ad.loadedAt) < Self.lifetime {
            return
        }
        if let failed = failedAt[placement], time.timeIntervalSince(failed) < Self.retryDelay {
            return
        }
        loading.insert(placement)
        defer { loading.remove(placement) }
        do {
            let content = try await service.loadNativeAd()
            guard adRemoval == .notPurchased else { return }
            loaded[placement] = LoadedAd(content: content, loadedAt: now())
            failedAt[placement] = nil
        } catch {
            failedAt[placement] = now()
            // An expired ad no longer counts: better none.
            if let ad = loaded[placement], now().timeIntervalSince(ad.loadedAt) >= Self.lifetime {
                loaded[placement] = nil
            }
        }
    }

    func presentPrivacyOptions() async {
        guard let service else { return }
        await service.presentPrivacyOptions()
        privacyOptionsRequired = service.privacyOptionsRequired
    }

    private func start() async {
        guard let service, !ready, !starting else { return }
        starting = true
        defer { starting = false }
        let canRequest = await service.gatherConsent()
        privacyOptionsRequired = service.privacyOptionsRequired
        guard canRequest, adRemoval == .notPurchased else { return }
        service.startSDK()
        ready = true
    }
}
