import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// A wide window's terminal tabs, as the desktop's tabs behave, and a
/// narrow window's terminal shown over its tabs.
@MainActor
struct AppModelTests {
    let test: TestCore
    let model: AppModel

    init() throws {
        test = try TestCore()
        model = AppModel(core: test.core, deviceName: "iPad")
    }

    /// Opens a terminal on each of `names`, saved on a port nothing listens
    /// on: what the tabs do does not need them connected.
    private func open(_ names: String...) async throws -> [TerminalSession] {
        let port = try closedPort()
        let store = test.core.store()
        for name in names {
            let id = try await store.addHost(
                draft: draft(name: name, port: port, auth: .noPassword), password: .keep,
                proxyPassword: .keep)
            try model.connect(try #require(store.host(id: id)))
        }
        return model.sessions
    }

    private var front: String? {
        model.shownSession?.host.name
    }

    @Test func closingTheFrontTabBringsItsNeighbourForward() async throws {
        model.isWide = true
        let tabs = try await open("a", "b", "c")
        #expect(front == "c")

        model.shownSession = tabs[1]
        model.close(tabs[1])
        #expect(front == "c")
        model.close(tabs[2])
        #expect(front == "a")
        // A tab behind closes without changing the one in front.
        let d = try #require(try await open("d").last)
        model.close(tabs[0])
        #expect(front == "d")
        model.close(d)
        #expect(model.shownSession == nil)
        #expect(model.sessions.isEmpty)
    }

    @Test func closingTheShownTerminalOfANarrowWindowGoesBackToTheList() async throws {
        model.isWide = false
        let tabs = try await open("a", "b")
        model.close(tabs[1])
        #expect(model.shownSession == nil)
        #expect(model.sessions.map(\.host.name) == ["a"])
    }

    @Test func aTabsMenuClosesTheOnesAroundIt() async throws {
        model.isWide = true
        var tabs = try await open("a", "b", "c", "d")
        model.close(.left, of: tabs[1])
        #expect(model.sessions.map(\.host.name) == ["b", "c", "d"])
        #expect(front == "b")
        model.close(.right, of: tabs[2])
        #expect(model.sessions.map(\.host.name) == ["b", "c"])
        #expect(front == "c")

        tabs = model.sessions
        model.close(.others, of: tabs[0])
        #expect(model.sessions.map(\.host.name) == ["b"])
        model.close(.all, of: tabs[0])
        #expect(model.sessions.isEmpty)
        #expect(model.shownSession == nil)
    }

    @Test func numbersAndArrowsPickATab() async throws {
        model.isWide = true
        // Nothing open: nothing to pick.
        model.selectNext()
        model.select(tab: 1)
        #expect(model.shownSession == nil)

        _ = try await open("a", "b", "c")
        model.select(tab: 1)
        #expect(front == "a")
        // ⌘9 is the last, as in a browser; a tab not there does nothing.
        model.select(tab: 9)
        #expect(front == "c")
        model.select(tab: 5)
        #expect(front == "c")

        model.selectNext()
        #expect(front == "a")
        model.selectPrevious()
        #expect(front == "c")
        model.selectPrevious()
        #expect(front == "b")

        // From the start page, the first or the last.
        model.shownSession = nil
        model.selectPrevious()
        #expect(front == "c")
    }

    @Test func onlySshConnects() async throws {
        let store = test.core.store()
        var telnet = draft(name: "router")
        telnet.protocol = .telnet(userPrompt: "", passwordPrompt: "")
        let id = try await store.addHost(draft: telnet, password: .keep, proxyPassword: .keep)
        let host = try #require(store.host(id: id))
        #expect(throws: StoreError.NotSsh) {
            try model.connect(host)
        }
        #expect(model.sessions.isEmpty)
    }

    @Test func syncsReviewOpensWhereTheWindowHasTheSettings() {
        model.isWide = true
        model.reviewSync()
        #expect(model.showingSettings)
        #expect(model.tab == .hosts)
        #expect(model.settingsPath == [.sync])

        model.showingSettings = false
        model.settingsPath = []
        model.isWide = false
        model.reviewSync()
        #expect(!model.showingSettings)
        #expect(model.tab == .settings)
        #expect(model.settingsPath == [.sync])
    }
}
