// The only file that talks to Google's SDKs, with NativeAdCard.swift. A
// fork that takes the two packages out builds without it, and without ads.
#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
    import Foundation
    import GoogleMobileAds
    import UserMessagingPlatform

    /// AdMob native ads, after Google's consent form (UMP) where the law
    /// asks for one. No App Tracking Transparency prompt: the ads never use
    /// the advertising identifier.
    @MainActor
    final class GoogleAdsService: AdsService {
        private let nativeAdUnitID: String
        /// The loads in flight: an ad loader holds its delegate weakly.
        private var requests: Set<NativeAdRequest> = []

        init(nativeAdUnitID: String) {
            self.nativeAdUnitID = nativeAdUnitID
        }

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
            }
            return ConsentInformation.shared.canRequestAds
        }

        var privacyOptionsRequired: Bool {
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        }

        func presentPrivacyOptions() async {
            try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
        }

        func startSDK() {
            MobileAds.shared.start(completionHandler: nil)
        }

        func loadNativeAd() async throws -> AnyObject {
            let request = NativeAdRequest(adUnitID: nativeAdUnitID)
            requests.insert(request)
            defer { requests.remove(request) }
            return try await request.load()
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
