// The only file that talks to Google's SDKs, with the cards that show the
// ads (NativeAdCard.swift, BannerAdCard.swift). A
// fork that takes the two packages out builds without it, and without ads.
#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
    import Foundation
    import GoogleMobileAds
    import UserMessagingPlatform
    import os

    /// AdMob banners and native ads, after Google's consent form (UMP)
    /// where the law asks for one. No App Tracking Transparency prompt: the
    /// ads never use the advertising identifier.
    @MainActor
    final class GoogleAdsService: AdsService {
        private let configuration: AdsConfiguration
        /// The loads in flight: the SDK holds their delegates weakly.
        private var requests: Set<NSObject> = []

        init(configuration: AdsConfiguration) {
            self.configuration = configuration
        }

        var formats: Set<AdFormat> { configuration.formats }

        func gatherConsent() async -> Bool {
            let parameters = RequestParameters()
            #if DEBUG
                // To see the form as a user in the EEA does.
                if ProcessInfo.processInfo.environment["SHELLRS_UMP_DEBUG_EEA"] == "1" {
                    let debug = DebugSettings()
                    debug.geography = .EEA
                    parameters.debugSettings = debug
                }
            #endif
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
            } catch {
                // Offline, or the form would not show: what was agreed before holds.
                Logger.ads.error("Consent (UMP) failed: \(error.localizedDescription, privacy: .public)")
            }
            let consent = ConsentInformation.shared
            Logger.ads.notice(
                "Consent status \(consent.consentStatus.rawValue, privacy: .public), can request ads: \(consent.canRequestAds, privacy: .public)"
            )
            return consent.canRequestAds
        }

        func startSDK() {
            MobileAds.shared.start(completionHandler: nil)
        }

        func loadAd(_ format: AdFormat) async throws -> AnyObject {
            guard let unitID = configuration.unitID(for: format) else {
                throw AdsServiceError.noAdUnit
            }
            switch format {
            case .banner:
                let request = BannerRequest(adUnitID: unitID)
                requests.insert(request)
                defer { requests.remove(request) }
                return try await request.load()
            case .native:
                let request = NativeAdRequest(adUnitID: unitID)
                requests.insert(request)
                defer { requests.remove(request) }
                return try await request.load()
            }
        }
    }

    enum AdsServiceError: Error {
        case noAdUnit
    }

    /// One banner, loaded: the standard 320 by 50 points, which fits beside
    /// the hosts on every iPhone. After that the SDK refreshes it itself, as
    /// the ad unit says, while it shows.
    @MainActor
    private final class BannerRequest: NSObject, BannerViewDelegate {
        private let banner: BannerView
        private var continuation: CheckedContinuation<Void, any Error>?

        init(adUnitID: String) {
            banner = BannerView(adSize: AdSizeBanner)
            banner.adUnitID = adUnitID
            super.init()
            banner.delegate = self
        }

        func load() async throws -> BannerView {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                banner.load(Request())
            }
            return banner
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            continuation?.resume()
            continuation = nil
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    /// One native ad, loaded.
    @MainActor
    private final class NativeAdRequest: NSObject, NativeAdLoaderDelegate {
        private let loader: AdLoader
        private var continuation: CheckedContinuation<Delivered, any Error>?

        /// The SDK delivers the ad on the main actor and the request awaits it
        /// there: it never actually crosses actors.
        private struct Delivered: @unchecked Sendable {
            let ad: NativeAd
        }

        init(adUnitID: String) {
            let options = NativeAdViewAdOptions()
            options.preferredAdChoicesPosition = .topRightCorner
            loader = AdLoader(
                adUnitID: adUnitID, rootViewController: nil, adTypes: [.native], options: [options])
            super.init()
            loader.delegate = self
        }

        func load() async throws -> NativeAd {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                loader.load(Request())
            }.ad
        }

        func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
            continuation?.resume(returning: Delivered(ad: nativeAd))
            continuation = nil
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
#endif
