import Foundation
import Testing

@testable import ShellRS

@MainActor
final class FakeAdsService: AdsService {
    var canRequestAds = true
    var privacyOptionsRequired = false
    var failLoads = false
    var consentRequests = 0
    var starts = 0
    var loads = 0
    var privacyOptionsShown = 0

    func gatherConsent() async -> Bool {
        consentRequests += 1
        return canRequestAds
    }

    func presentPrivacyOptions() async {
        privacyOptionsShown += 1
    }

    func startSDK() {
        starts += 1
    }

    func loadNativeAd() async throws -> AnyObject {
        loads += 1
        if failLoads { throw PurchaseStoreError.unavailable }
        return NSObject()
    }
}

@MainActor
final class AdsTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

/// The ads wait for StoreKit, never start for whoever bought them away,
/// and load one ad per placement, again only once it is old.
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
        service.privacyOptionsRequired = true
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        #expect(service.consentRequests == 1)
        #expect(service.starts == 1)
        #expect(ads.ready)
        #expect(ads.privacyOptionsRequired)
        await ads.prepare(.hosts)
        await ads.prepare(.sessions)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .hosts) != nil)
        #expect(ads.ad(for: .sessions) != nil)
        #expect(ads.ad(for: .start) == nil)
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

    @Test func anAdIsKeptForAnHourThenLoadedAgain() async throws {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        let first = try #require(ads.ad(for: .hosts))
        clock.date += AdsModel.lifetime - 1
        await ads.prepare(.hosts)
        #expect(service.loads == 1)
        #expect(ads.ad(for: .hosts)?.id == first.id)
        clock.date += 1
        await ads.prepare(.hosts)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .hosts)?.id != first.id)
    }

    @Test func aFailedLoadWaitsAMinuteAndDropsAnExpiredAd() async {
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        await ads.prepare(.hosts)
        #expect(ads.ad(for: .hosts) != nil)
        service.failLoads = true
        clock.date += AdsModel.lifetime
        await ads.prepare(.hosts)
        #expect(service.loads == 2)
        #expect(ads.ad(for: .hosts) == nil)
        clock.date += AdsModel.retryDelay - 1
        await ads.prepare(.hosts)
        #expect(service.loads == 2)
        service.failLoads = false
        clock.date += 1
        await ads.prepare(.hosts)
        #expect(service.loads == 3)
        #expect(ads.ad(for: .hosts) != nil)
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

    @Test func privacyOptionsAreShownAndReadAgain() async {
        service.privacyOptionsRequired = true
        let ads = make()
        await ads.purchaseChanged(.notPurchased)
        service.privacyOptionsRequired = false
        await ads.presentPrivacyOptions()
        #expect(service.privacyOptionsShown == 1)
        #expect(!ads.privacyOptionsRequired)
    }

    @Test func aBuildWithoutAnAdUnitHasNoAds() {
        #expect(!AdsConfiguration(nativeAdUnitID: "").isEnabled)
        #expect(!AdsConfiguration(nativeAdUnitID: "$(SHELLRS_NATIVE_AD_UNIT_ID)").isEnabled)
        #expect(AdsConfiguration(nativeAdUnitID: "ca-app-pub-3940256099942544/3986624511").isEnabled)
        #expect(AdsModel.bundledService(AdsConfiguration(nativeAdUnitID: "")) == nil)
        #expect(!AdsModel(service: nil).isAvailable)
    }

    /// What the repository builds asks for Google's test ads only: the real
    /// IDs come from the release workflow, or Local.xcconfig for Release, so
    /// that no build from a clone ever counts against the AdMob account.
    @Test func debugBuildsAskForGoogleTestAdsOnly() {
        for key in ["GADApplicationIdentifier", "ShellRSNativeAdUnitID"] {
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
