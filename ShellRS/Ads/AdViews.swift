import SwiftUI

/// The ad of `placement` as a list section of its own, with the way to
/// remove the ads under it. Nothing while there is no ad.
struct AdSection: View {
    let placement: AdPlacement
    @Environment(AppModel.self) private var model

    var body: some View {
        if let ad = model.ads.ad(for: placement) {
            Section {
                NativeAdCard(ad: ad)
                    .id(ad.id)
                    .listRowInsets(EdgeInsets())
            } footer: {
                RemoveAdsLink()
            }
        }
    }
}

/// The ad of `placement` outside a list: a card like the start page's
/// hosts, with the way to remove the ads under it. `fill` stands out from
/// what is behind it: the grouped background by default.
struct AdCard: View {
    let placement: AdPlacement
    var fill = Color(.secondarySystemGroupedBackground)
    @Environment(AppModel.self) private var model

    var body: some View {
        if let ad = model.ads.ad(for: placement) {
            VStack(alignment: .leading, spacing: 6) {
                NativeAdCard(ad: ad)
                    .id(ad.id)
                    .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                RemoveAdsLink()
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// 去除广告: the settings, where buying and restoring it are.
private struct RemoveAdsLink: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.purchases.configuration.isConfigured {
            Button("去除广告") {
                model.openAdSettings()
            }
            .font(.footnote)
        }
    }
}

extension View {
    /// Loads the ad of `placement` while this is shown and `active`: on
    /// showing it, and again once the ads are ready.
    func loadsAd(_ placement: AdPlacement, when active: Bool = true) -> some View {
        modifier(AdLoading(placement: placement, active: active))
    }
}

private struct AdLoading: ViewModifier {
    let placement: AdPlacement
    let active: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task(id: active && model.ads.ready) {
            if active {
                await model.ads.prepare(placement)
            }
        }
    }
}
