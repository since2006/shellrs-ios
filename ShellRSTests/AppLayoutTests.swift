import CoreGraphics
import Testing

@testable import ShellRS

struct AppLayoutTests {
    @Test func aSidebarNeedsRoomForBothColumnsAndARegularSizeClass() {
        #expect(!AppLayout(width: 660, regular: true).isWide)
        #expect(AppLayout(width: 661, regular: true).isWide)
        #expect(!AppLayout(width: 1200, regular: false).isWide)
        #expect(!AppLayout(width: .nan, regular: true).isWide)
    }

    @Test func filesTemporarilyDisplaceTheSidebarWithoutChangingItsPreference() {
        let twoColumns = AppLayout(width: 981, regular: true)
        #expect(twoColumns.showsSidebar(requested: true, filesShown: false))
        #expect(!twoColumns.showsSidebar(requested: true, filesShown: true))
        let threeColumns = AppLayout(width: 982, regular: true)
        #expect(threeColumns.showsSidebar(requested: true, filesShown: true))
        #expect(!threeColumns.showsSidebar(requested: false, filesShown: true))
        #expect(!AppLayout(width: 720, regular: true).fitsFilesBesideTerminal)
        #expect(AppLayout(width: 721, regular: true).fitsFilesBesideTerminal)
    }

    @Test func aTerminalAvoidsHorizontalAndVerticalFolds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let horizontal = CGRect(x: 0, y: 280, width: 800, height: 40)
        #expect(
            UnobscuredRegion.largest(in: bounds, avoiding: [horizontal])
                == CGRect(x: 0, y: 0, width: 800, height: 280))
        let vertical = CGRect(x: 380, y: 0, width: 40, height: 600)
        #expect(
            UnobscuredRegion.largest(in: bounds, avoiding: [vertical])
                == CGRect(x: 0, y: 0, width: 380, height: 600))
    }

    @Test func camerasAndMultipleObstructionsLeaveOneUsableRectangle() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let obstacles = [
            CGRect(x: 0, y: 280, width: 800, height: 40),
            CGRect(x: 0, y: 0, width: 80, height: 80),
        ]
        let result = UnobscuredRegion.largest(in: bounds, avoiding: obstacles)
        #expect(result == CGRect(x: 0, y: 320, width: 800, height: 280))
        #expect(obstacles.allSatisfy { result.intersection($0).isEmpty })
        #expect(UnobscuredRegion.largest(in: bounds, avoiding: [.zero, .null]) == bounds)
        #expect(UnobscuredRegion.largest(in: bounds, avoiding: [bounds]).isEmpty)
    }
}
