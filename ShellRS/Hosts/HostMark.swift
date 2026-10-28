import ShellRSCore
import SwiftUI
import UIKit

/// The host's colored mark: its system's logo on the brand's color once the
/// system is known, else its initial on the color its address picks. Always
/// in color; gray is for offline.
struct HostMark: View {
    let host: Host
    var dimmed = false
    /// Its side: a list row's, or smaller on a tab.
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 2 / 9, style: .continuous)
            .fill(dimmed ? Color.gray : background)
            .frame(width: size, height: size)
            .overlay {
                if let logo {
                    Image(uiImage: logo)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 5 / 9, height: size * 5 / 9)
                        .foregroundStyle(foreground)
                } else {
                    Text(initial)
                        .font(.system(size: size * 17 / 36, weight: .semibold))
                        .foregroundStyle(foreground)
                }
            }
            .accessibilityHidden(true)
    }

    private var background: Color {
        Color(rgb: host.os?.brandColor ?? host.markColor)
    }

    private var foreground: Color {
        guard !dimmed, host.os?.brandColor != nil else {
            return .white
        }
        return host.os?.brandForeground.map { Color(rgb: $0) } ?? .white
    }

    /// The system's logo, by the key the desktop names its icons with; none
    /// for a system this build does not know.
    private var logo: UIImage? {
        host.os.flatMap { UIImage(named: "OS/\($0.key)") }
    }

    private var initial: String {
        (host.title.first.map(String.init) ?? "?").uppercased()
    }
}

extension Color {
    /// A color as the core gives it: 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255)
    }
}
