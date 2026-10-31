import SwiftUI

/// Layout belongs to the window's available space, never to a device name or idiom.
struct AppLayout: Equatable {
    static let sidebarMinimum = 260.0
    static let terminalMinimum = 400.0
    static let filesMinimum = 320.0
    static let divider = 1.0

    let width: Double
    let regular: Bool

    static let compact = AppLayout(width: 0, regular: false)

    var isWide: Bool {
        regular && width >= Self.sidebarMinimum + Self.terminalMinimum + Self.divider
    }

    var fitsThreeColumns: Bool {
        isWide
            && width >= Self.sidebarMinimum + Self.terminalMinimum
                + Self.filesMinimum + 2 * Self.divider
    }

    var fitsFilesBesideTerminal: Bool {
        isWide && width >= Self.terminalMinimum + Self.filesMinimum + Self.divider
    }

    func showsSidebar(requested: Bool, filesShown: Bool) -> Bool {
        isWide && requested && (!filesShown || fitsThreeColumns)
    }
}

/// A terminal is rectangular: keep the entire viewport clear of folds and cameras.
/// Keeping all four remainders allows a later obstruction to select a different side.
enum UnobscuredRegion {
    static func largest(in bounds: CGRect, avoiding obstacles: [CGRect]) -> CGRect {
        var candidates = [bounds]
        for obstacle in obstacles where !obstacle.isNull && !obstacle.isEmpty {
            candidates = candidates.flatMap { candidate -> [CGRect] in
                let cut = candidate.intersection(obstacle)
                guard !cut.isNull, !cut.isEmpty else { return [candidate] }
                return [
                    CGRect(
                        x: candidate.minX, y: candidate.minY,
                        width: candidate.width, height: cut.minY - candidate.minY),
                    CGRect(
                        x: candidate.minX, y: cut.maxY,
                        width: candidate.width, height: candidate.maxY - cut.maxY),
                    CGRect(
                        x: candidate.minX, y: candidate.minY,
                        width: cut.minX - candidate.minX, height: candidate.height),
                    CGRect(
                        x: cut.maxX, y: candidate.minY,
                        width: candidate.maxX - cut.maxX, height: candidate.height),
                ].filter { $0.width > 0 && $0.height > 0 }
            }
        }
        return candidates.sorted {
            let a = $0.width * $0.height
            let b = $1.width * $1.height
            if a != b { return a > b }
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            return $0.minX < $1.minX
        }.first ?? CGRect(origin: bounds.origin, size: .zero)
    }
}

struct UnobscuredArea<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let frame = frame(in: geometry)
            content()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private func frame(in geometry: GeometryProxy) -> CGRect {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        if #available(iOS 27.1, *) {
            let regions =
                geometry.reservedRegions(kind: .division)
                + geometry.reservedRegions(kind: .occlusion)
            let obstacles = regions.map { region in
                CGRect(
                    x: region.frame.minX - region.margins.leading,
                    y: region.frame.minY - region.margins.top,
                    width: region.frame.width + region.margins.leading + region.margins.trailing,
                    height: region.frame.height + region.margins.top + region.margins.bottom)
            }
            return UnobscuredRegion.largest(in: bounds, avoiding: obstacles)
        }
        return bounds
    }
}
