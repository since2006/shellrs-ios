import Foundation
import Observation
import os

extension Logger {
    /// Why there is an ad or none: in Xcode's console, or Console.app with
    /// the category Ads.
    static let ads = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShellRS", category: "Ads")
}

/// What an ad is: a banner the SDK draws itself, or a native ad laid out
/// here.
enum AdFormat: Hashable, CaseIterable {
    case banner
    case native
}

/// Where an ad goes, one each. Never over a terminal or its files.
enum AdPlacement: Hashable, CaseIterable {
    /// The 主机 tab of a narrow window, after 最近连接: a banner, which takes
    /// a third of a native ad's height above the hosts.
    case hosts
    /// The 终端 tab of a narrow window, after the terminals.
    case sessions
    /// A wide window's start page, after the hosts connected lately.
    case start

    var format: AdFormat {
        self == .hosts ? .banner : .native
    }
}

/// The ad units from the build configuration (`SHELLRS_BANNER_AD_UNIT_ID`,
/// `SHELLRS_NATIVE_AD_UNIT_ID`). An empty one, as a fork without ads sets
/// both: no ads of that format; neither, or in the test host, or with
/// `SHELLRS_DISABLE_ADS=1` (screenshots): no ads, and the ads SDK and its
/// consent form never start.
struct AdsConfiguration: Equatable {
    var bannerAdUnitID = ""
    var nativeAdUnitID = ""

    static var bundled: Self {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["SHELLRS_DISABLE_ADS"] == "1" {
            return Self()
        }
        func id(_ key: String) -> String {
            Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        return Self(bannerAdUnitID: id("ShellRSBannerAdUnitID"), nativeAdUnitID: id("ShellRSNativeAdUnitID"))
    }

    /// The unit of `format`, if the build has one.
    func unitID(for format: AdFormat) -> String? {
        let id =
            switch format {
            case .banner: bannerAdUnitID
            case .native: nativeAdUnitID
            }
        return id.isEmpty || id.contains("$(") ? nil : id
    }

    var formats: Set<AdFormat> {
        Set(AdFormat.allCases.filter { unitID(for: $0) != nil })
    }

    var isEnabled: Bool { !formats.isEmpty }
}

/// An ad, loaded: what a placement shows.
struct LoadedAd: Identifiable {
    let id = UUID()
    /// The SDK's `BannerView` or `NativeAd`, opaque here so that the model
    /// builds without the SDK.
    let content: AnyObject
    let loadedAt: Date
}

/// The ads SDK and its consent form, as the model needs them.
@MainActor
protocol AdsService: AnyObject {
    /// The formats the build has a unit for.
    var formats: Set<AdFormat> { get }
    /// Updates what the user agreed to, asking them if the law says it must,
    /// then whether ads may be requested.
    func gatherConsent() async -> Bool
    func startSDK()
    func loadAd(_ format: AdFormat) async throws -> AnyObject
}

/// The ads: none until StoreKit says they were not bought away, then the
/// consent form where the law asks for it, then one ad per placement,
/// loaded when it is shown.
@MainActor
@Observable
final class AdsModel {
    /// Google asks not to show a native ad loaded more than an hour ago. A
    /// banner refreshes itself, as the ad unit says, for as long as it shows.
    static let lifetime: TimeInterval = 60 * 60
    /// After a failed load, how long before that placement tries again.
    static let retryDelay: TimeInterval = 60

    /// Consent is settled and the SDK started: ads can be requested.
    private(set) var ready = false
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

    /// The service for this build: none when no ad unit is set or the
    /// Google packages were taken out.
    static func bundledService(_ configuration: AdsConfiguration = .bundled) -> (any AdsService)? {
        guard configuration.isEnabled else { return nil }
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
            return GoogleAdsService(configuration: configuration)
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
            Logger.ads.notice("Remove Ads is purchased: no ads, and the SDK does not start")
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
    /// failed a moment ago, or the build has no unit of its format.
    func prepare(_ placement: AdPlacement) async {
        guard ready, adRemoval == .notPurchased, let service, !loading.contains(placement),
            service.formats.contains(placement.format)
        else {
            return
        }
        let time = now()
        if let ad = loaded[placement], !isExpired(ad, placement, at: time) {
            return
        }
        if let failed = failedAt[placement], time.timeIntervalSince(failed) < Self.retryDelay {
            return
        }
        loading.insert(placement)
        defer { loading.remove(placement) }
        do {
            let content = try await service.loadAd(placement.format)
            guard adRemoval == .notPurchased else { return }
            Logger.ads.notice("Loaded the ad for \(String(describing: placement), privacy: .public)")
            loaded[placement] = LoadedAd(content: content, loadedAt: now())
            failedAt[placement] = nil
        } catch {
            Logger.ads.error(
                "The ad for \(String(describing: placement), privacy: .public) did not load, trying again in a minute: \(error.localizedDescription, privacy: .public)"
            )
            failedAt[placement] = now()
            // An expired ad no longer counts: better none.
            if let ad = loaded[placement], isExpired(ad, placement, at: now()) {
                loaded[placement] = nil
            }
        }
    }

    private func isExpired(_ ad: LoadedAd, _ placement: AdPlacement, at time: Date) -> Bool {
        placement.format == .native && time.timeIntervalSince(ad.loadedAt) >= Self.lifetime
    }

    private func start() async {
        guard let service, !ready, !starting else { return }
        starting = true
        defer { starting = false }
        let canRequest = await service.gatherConsent()
        guard canRequest else {
            Logger.ads.error("Ads may not be requested yet (no consent answer, or offline): asking again when the app comes forward")
            return
        }
        guard adRemoval == .notPurchased else { return }
        service.startSDK()
        Logger.ads.notice("The ads SDK started")
        ready = true
    }
}
