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

    @Test func aRateIsAtMostFourCharactersAndItsUnit() {
        let cases: [(Double?, String, String)] = [
            (0, "0", "B/s"),
            (900, "900", "B/s"),
            (999.4, "999", "B/s"),
            // Not 「1000 B/s」, five characters.
            (999.5, "1", "K/s"),
            (2048, "2", "K/s"),
            (1.6 * 1024 * 1024, "1.6", "M/s"),
            (10.74 * 1024 * 1024, "10.7", "M/s"),
            (99.96 * 1024, "100", "K/s"),
            (898 * 1024, "898", "K/s"),
            (999.7 * 1024, "1", "M/s"),
            (3 * 1024 * 1024 * 1024, "3", "G/s"),
            (-5, "0", "B/s"),
            (nil, "—", "B/s"),
        ]
        for (bytes, number, unit) in cases {
            let rate = StatusFormat.compactRate(bytes)
            #expect(rate.number == number, "\(String(describing: bytes))")
            #expect(rate.unit == unit, "\(String(describing: bytes))")
            #expect(rate.number.count <= 4)
        }
    }

    @Test func aLoadUnderASmallRingIsShort() {
        #expect(StatusFormat.compactLoad(0) == "0.0")
        #expect(StatusFormat.compactLoad(0.64) == "0.6")
        #expect(StatusFormat.compactLoad(9.96) == "10")
        #expect(StatusFormat.compactLoad(128.4) == "128")
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
