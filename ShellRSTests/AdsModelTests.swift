import Foundation
import Testing

@testable import ShellRS

@MainActor
final class FakeAdsService: AdsService {
    var formats: Set<AdFormat> = [.banner, .native]
    var canRequestAds = true
    var failLoads = false
    var consentRequests = 0
    var starts = 0
    var loaded: [AdFormat] = []
    var loads: Int { loaded.count }

    func gatherConsent() async -> Bool {
        consentRequests += 1
        return canRequestAds
    }

    func startSDK() {
        starts += 1
    }

    func loadAd(_ format: AdFormat) async throws -> AnyObject {
        loaded.append(format)
        if failLoads { throw PurchaseStoreError.unavailable }
        return NSObject()
    }
}

@MainActor
final class AdsTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

/// The ads wait for StoreKit, never start for whoever bought them away,
/// and load one ad per placement: a native ad again once it is old, a
/// banner never (the SDK refreshes it).
@MainActor
struct AdsModelTests {
    let service = FakeAdsService()
    let clock = AdsTestClock()

    func make() -> AdsModel {
        AdsModel(service: service, now: { [clock] in clock.date })
    }

    @Test func nothingStartsUntilStoreKitAnswers() async {
        let ads = make()
        await ads.purchaseChanged(.unknown)
        #expect(service.consentRequests == 0)
        #expect(!ads.ready)
        await ads.prepare(.hosts)
        #expect(service.loads == 0)
    }

    @Test func whoeverBoughtThemAwayNeverStartsTheSDK() async {
        let ads = make()
        await ads.purchaseChanged(.purchased)
        await ads.cameForward()
        await ads.prepare(.hosts)
        #expect(service.consentRequests == 0)
        #expect(service.starts == 0)
        #expect(service.loads == 0)
        #expect(ads.ad(for: .hosts) == nil)
    }

    @Test func consentThenTheSDKThenAnAdPerPlacement() async {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        #expect(service.consentRequests == 1)
        #expect(service.starts == 1)
        #expect(ads.ready)
        await ads.prepare(.hosts)
        await ads.prepare(.sessions)
        #expect(service.loaded == [.banner, .native])
        #expect(ads.ad(for: .hosts) != nil)
        #expect(ads.ad(for: .sessions) != nil)
        #expect(ads.ad(for: .start) == nil)
        await ads.prepare(.start)
        #expect(service.loaded == [.banner, .native, .native])
        // Starting again changes nothing.
        await ads.cameForward()
        #expect(service.starts == 1)
    }

    @Test func withoutConsentNoAdIsRequestedUntilItIsGiven() async {
        service.canRequestAds = false
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        #expect(!ads.ready)
        #expect(service.starts == 0)
        await ads.prepare(.hosts)
        #expect(service.loads == 0)
        service.canRequestAds = true
        await ads.cameForward()
        #expect(service.consentRequests == 2)
        #expect(ads.ready)
    }

    @Test func aNativeAdIsKeptForAnHourThenLoadedAgain() async throws {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.sessions)
        let first = try #require(ads.ad(for: .sessions))
        clock.date += AdsModel.lifetime - 1
        await ads.prepare(.sessions)
        #expect(service.loads == 1)
        #expect(ads.ad(for: .sessions)?.id == first.id)
        clock.date += 1
        await ads.prepare(.sessions)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .sessions)?.id != first.id)
    }

    @Test func aBannerIsKeptAsTheSDKRefreshesIt() async throws {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        let banner = try #require(ads.ad(for: .hosts))
        clock.date += AdsModel.lifetime * 3
        await ads.prepare(.hosts)
        #expect(service.loaded == [.banner])
        #expect(ads.ad(for: .hosts)?.id == banner.id)
    }

    @Test func aFailedLoadWaitsAMinuteAndDropsAnExpiredAd() async {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.sessions)
        #expect(ads.ad(for: .sessions) != nil)
        service.failLoads = true
        clock.date += AdsModel.lifetime
        await ads.prepare(.sessions)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .sessions) == nil)
        clock.date += AdsModel.retryDelay - 1
        await ads.prepare(.sessions)
        #expect(service.loads == 2)
        service.failLoads = false
        clock.date += 1
        await ads.prepare(.sessions)
        #expect(service.loads == 3)
        #expect(ads.ad(for: .sessions) != nil)
    }

    @Test func aBuildWithoutABannerUnitLeavesTheHostsWithout() async {
        service.formats = [.native]
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        await ads.prepare(.sessions)
        #expect(service.loaded == [.native])
        #expect(ads.ad(for: .hosts) == nil)
    }

    @Test func buyingThemAwayDropsTheAdsAndARefundBringsThemBack() async {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        await ads.purchaseChanged(.purchased)
        #expect(ads.ad(for: .hosts) == nil)
        await ads.prepare(.hosts)
        #expect(service.loads == 1)
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .hosts) != nil)
    }

    @Test func aBuildWithoutAnAdUnitHasNoAds() {
        let banner = "ca-app-pub-3940256099942544/2934735716"
        let native = "ca-app-pub-3940256099942544/3986624511"
        #expect(!AdsConfiguration().isEnabled)
        #expect(
            !AdsConfiguration(
                bannerAdUnitID: "$(SHELLRS_BANNER_AD_UNIT_ID)", nativeAdUnitID: "$(SHELLRS_NATIVE_AD_UNIT_ID)"
            ).isEnabled)
        #expect(AdsConfiguration(bannerAdUnitID: banner).formats == [.banner])
        #expect(AdsConfiguration(nativeAdUnitID: native).formats == [.native])
        #expect(AdsConfiguration(bannerAdUnitID: banner, nativeAdUnitID: native).unitID(for: .banner) == banner)
        #expect(AdsModel.bundledService(AdsConfiguration()) == nil)
        #expect(!AdsModel(service: nil).isAvailable)
    }

    /// What the repository builds asks for Google's test ads only: the real
    /// IDs come from the release workflow, or Local.xcconfig for Release, so
    /// that no build from a clone ever counts against the AdMob account.
    @Test func debugBuildsAskForGoogleTestAdsOnly() {
        for key in ["GADApplicationIdentifier", "ShellRSBannerAdUnitID", "ShellRSNativeAdUnitID"] {
            if let id = Bundle.main.object(forInfoDictionaryKey: key) as? String, !id.isEmpty {
                #expect(id.hasPrefix("ca-app-pub-3940256099942544"), "\(key) is \(id)")
            }
        }
    }

    /// The test host is the app: it must not start the ads SDK.
    @Test func theTestHostHasNoAds() {
        #expect(!AdsConfiguration.bundled.isEnabled)
        #expect(!AdsModel().isAvailable)
    }
}
