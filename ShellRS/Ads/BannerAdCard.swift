import SwiftUI

#if canImport(GoogleMobileAds)
    import GoogleMobileAds
    import UIKit

    /// A banner, centred: the model keeps the SDK's `BannerView`, loaded,
    /// and this only holds it, so that a list row made again shows the same
    /// banner rather than loading another.
    struct BannerAdCard: UIViewRepresentable {
        let ad: LoadedAd

        func makeUIView(context: Context) -> UIView {
            UIView()
        }

        func updateUIView(_ container: UIView, context: Context) {
            guard let banner = ad.content as? BannerView, banner.superview !== container else {
                return
            }
            container.subviews.forEach { $0.removeFromSuperview() }
            banner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(banner)
            let size = banner.adSize.size
            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                banner.widthAnchor.constraint(equalToConstant: size.width),
                banner.heightAnchor.constraint(equalToConstant: size.height),
            ])
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
            let size = (ad.content as? BannerView)?.adSize.size ?? .zero
            return CGSize(width: proposal.width ?? size.width, height: size.height)
        }
    }
#else
    /// Without the ads SDK there is never an ad to show.
    struct BannerAdCard: View {
        let ad: LoadedAd

        var body: some View {
            EmptyView()
        }
    }
#endif
