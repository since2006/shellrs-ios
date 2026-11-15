import CoreGraphics
import Testing

@testable import ShellRS

/// How 状态 lays out each core's column: a hundred cores in a few even rows
/// rather than a row each, and a tap finds the core under it.
@MainActor
struct StatusPartsTests {
    /// An iPhone's list row.
    static let width: CGFloat = 370

    @Test func manyCoresTakeAFewEvenRows() {
        let geometry = CoreBars.geometry(width: Self.width, count: 128)
        #expect(geometry.rows == 4)
        #expect(geometry.perRow == 32)
        #expect(geometry.bar >= 6)
        // The widest row fits.
        let row = CGFloat(geometry.perRow) * geometry.bar + CGFloat(geometry.perRow - 1) * 3
        #expect(row <= Self.width + 0.001)
        #expect(geometry.height == CGFloat(4 * 30 + 3 * 6))
    }

    @Test func theRowsAreFilledEvenly() {
        // 41 fit to a row: three rows of 34, not 41, 41 and 18.
        let geometry = CoreBars.geometry(width: Self.width, count: 100)
        #expect(geometry.rows == 3)
        #expect(geometry.perRow == 34)
    }

    @Test func fewCoresAreOneRowOfWiderColumns() {
        let geometry = CoreBars.geometry(width: Self.width, count: 4)
        #expect(geometry.rows == 1)
        #expect(geometry.perRow == 4)
        #expect(geometry.bar == CGFloat(36))
    }

    @Test func beforeItIsMeasuredItIsOneRow() {
        let geometry = CoreBars.geometry(width: 0, count: 16)
        #expect(geometry.rows == 1)
        #expect(geometry.height == CGFloat(30))
    }

    @Test func aTapFindsTheCoreUnderIt() {
        let geometry = CoreBars.geometry(width: Self.width, count: 100)
        let column = geometry.bar + 3
        // Row 1, column 2.
        let point = CGPoint(x: 2 * column + 1, y: 36 + 1)
        #expect(CoreBars.index(at: point, in: geometry, count: 100) == 34 + 2)
        // The last row has 32: nothing at its 34th place.
        let past = CGPoint(x: 33 * column + 1, y: 2 * 36 + 1)
        #expect(CoreBars.index(at: past, in: geometry, count: 100) == nil)
        // Below the last row, and right of the widest.
        #expect(CoreBars.index(at: CGPoint(x: 1, y: 3 * 36 + 1), in: geometry, count: 100) == nil)
        #expect(
            CoreBars.index(at: CGPoint(x: 34 * column + 1, y: 1), in: geometry, count: 100) == nil)
    }
}
