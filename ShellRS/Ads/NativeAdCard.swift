import SwiftUI

#if canImport(GoogleMobileAds)
    import GoogleMobileAds
    import UIKit

    /// A native ad laid out for a list row: its picture or video on the
    /// left, its words beside it, marked 广告.
    struct NativeAdCard: UIViewRepresentable {
        let ad: LoadedAd

        func makeUIView(context: Context) -> NativeAdCardView {
            NativeAdCardView()
        }

        func updateUIView(_ view: NativeAdCardView, context: Context) {
            if let nativeAd = ad.content as? NativeAd {
                view.show(nativeAd)
            }
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize, uiView: NativeAdCardView, context: Context
        ) -> CGSize? {
            let width = proposal.width ?? 360
            let height = uiView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            return CGSize(width: width, height: height)
        }
    }

    /// The SDK's view of a native ad. Every asset the ad has is shown: the
    /// media at least 120 by 120 points, as the SDK requires; the AdChoices
    /// mark in the top right, inside the padding so that a list row's
    /// rounded corner never clips it, and the words clear of it.
    final class NativeAdCardView: NativeAdView {
        private static let padding: CGFloat = 12
        private static let mediaSide: CGFloat = 120

        private let media = MediaView()
        private let choices = AdChoicesView()
        private let badge = InsetLabel(insets: UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4))
        private let advertiser = UILabel()
        private let headline = UILabel()
        private let body = UILabel()
        private let action = InsetLabel(insets: UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12))

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear

            media.contentMode = .scaleAspectFit
            media.clipsToBounds = true
            media.layer.cornerRadius = 8

            badge.text = String(localized: "广告")
            badge.font = .preferredFont(forTextStyle: .caption2).bold
            badge.textColor = .white
            badge.backgroundColor = .systemOrange
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.setContentHuggingPriority(.required, for: .horizontal)
            badge.setContentCompressionResistancePriority(.required, for: .horizontal)

            style(advertiser, .caption1, color: .secondaryLabel, lines: 1)
            style(headline, .headline, color: .label, lines: 2)
            style(body, .footnote, color: .secondaryLabel, lines: 2)

            action.font = .preferredFont(forTextStyle: .subheadline).bold
            action.adjustsFontForContentSizeCategory = true
            action.textColor = .white
            action.backgroundColor = .tintColor
            action.layer.cornerRadius = 8
            action.clipsToBounds = true
            // The SDK handles the taps on the whole ad.
            action.isUserInteractionEnabled = false

            let marks = UIStackView(arrangedSubviews: [badge, advertiser])
            marks.axis = .horizontal
            marks.spacing = 6
            marks.alignment = .center

            let words = UIStackView(arrangedSubviews: [marks, headline, body, action])
            words.axis = .vertical
            words.alignment = .leading
            words.spacing = 4
            words.setCustomSpacing(8, after: body)

            for view in [media, words, choices] as [UIView] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            let padding = Self.padding
            NSLayoutConstraint.activate([
                media.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
                media.topAnchor.constraint(equalTo: topAnchor, constant: padding),
                media.widthAnchor.constraint(equalToConstant: Self.mediaSide),
                media.heightAnchor.constraint(equalToConstant: Self.mediaSide),
                bottomAnchor.constraint(greaterThanOrEqualTo: media.bottomAnchor, constant: padding),

                choices.topAnchor.constraint(equalTo: topAnchor, constant: padding),
                choices.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
                choices.widthAnchor.constraint(equalToConstant: 15),
                choices.heightAnchor.constraint(equalToConstant: 15),

                words.leadingAnchor.constraint(equalTo: media.trailingAnchor, constant: padding),
                words.topAnchor.constraint(equalTo: topAnchor, constant: padding),
                words.trailingAnchor.constraint(equalTo: choices.leadingAnchor, constant: -4),
                bottomAnchor.constraint(greaterThanOrEqualTo: words.bottomAnchor, constant: padding),
            ])

            mediaView = media
            headlineView = headline
            advertiserView = advertiser
            bodyView = body
            callToActionView = action
            // Before the ad is set, or the SDK places the mark itself.
            adChoicesView = choices
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func show(_ ad: NativeAd) {
            guard nativeAd !== ad else { return }
            headline.text = ad.headline
            media.mediaContent = ad.mediaContent
            advertiser.text = ad.advertiser
            advertiser.isHidden = ad.advertiser == nil
            body.text = ad.body
            body.isHidden = ad.body == nil
            action.text = ad.callToAction
            action.isHidden = ad.callToAction == nil
            // Last: it registers the views above and makes the ad clickable.
            nativeAd = ad
        }

        private func style(_ label: UILabel, _ style: UIFont.TextStyle, color: UIColor, lines: Int) {
            label.font = .preferredFont(forTextStyle: style)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = color
            label.numberOfLines = lines
        }
    }

    /// A label with room around its text, for the 广告 mark and the action.
    private final class InsetLabel: UILabel {
        private let insets: UIEdgeInsets

        init(insets: UIEdgeInsets) {
            self.insets = insets
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: insets))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(
                width: size.width + insets.left + insets.right,
                height: size.height + insets.top + insets.bottom)
        }
    }

    extension UIFont {
        fileprivate var bold: UIFont {
            fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) }
                ?? self
        }
    }
#else
    /// Without the ads SDK there is never an ad to show.
    struct NativeAdCard: View {
        let ad: LoadedAd

        var body: some View {
            EmptyView()
        }
    }
#endif
