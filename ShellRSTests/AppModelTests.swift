import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// A wide window's terminal tabs, as the desktop's tabs behave, and a
/// narrow window's terminal shown over its tabs.
@MainActor
struct AppModelTests {
    let test: TestCore
    let defaults: UserDefaults
    let model: AppModel

    init() throws {
        test = try TestCore()
        defaults = try #require(UserDefaults(suiteName: "AppModelTests.\(UUID().uuidString)"))
        model = AppModel(core: test.core, deviceName: "iPad", defaults: defaults, purchases: .unlockedForTesting())
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
        model.updateLayout(AppLayout(width: 1200, regular: true))
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
        model.updateLayout(.compact)
        let tabs = try await open("a", "b")
        model.close(tabs[1])
        #expect(model.shownSession == nil)
        #expect(model.sessions.map(\.host.name) == ["a"])
    }

    @Test func aTabsMenuClosesTheOnesAroundIt() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
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
        model.updateLayout(AppLayout(width: 1200, regular: true))
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

    @Test func theTextSizeStaysInItsRangeAndIsKept() async throws {
        #expect(model.fontSize == 13)
        let a = try #require(try await open("a").first)
        #expect(a.surface.fontSize == 13)

        for _ in 0..<20 {
            model.biggerText()
        }
        #expect(model.fontSize == 28)
        // Every terminal open changes with it.
        #expect(a.surface.view.font.pointSize == 28)
        for _ in 0..<30 {
            model.smallerText()
        }
        #expect(model.fontSize == 10)
        model.defaultText()
        #expect(model.fontSize == 13)

        model.fontSize = 16
        let b = try #require(try await open("b").last)
        #expect(b.surface.fontSize == 16)
        // This device's, kept for the next launch.
        #expect(AppModel(core: test.core, deviceName: "iPad", defaults: defaults, purchases: .unlockedForTesting()).fontSize == 16)
        defaults.set(99.0, forKey: "terminalFontSize")
        #expect(AppModel(core: test.core, deviceName: "iPad", defaults: defaults, purchases: .unlockedForTesting()).fontSize == 13)
    }

    @Test func commandsShowTheListWhereTheWindowHasIt() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        model.sidebarList = .credentials
        model.sidebarShown = false
        model.request(.newHost)
        #expect(model.sidebarList == .hosts)
        #expect(model.sidebarShown)
        #expect(model.tab == .hosts)
        #expect(model.hostListRequest == .newHost)
        model.hostListRequest = nil

        // Not behind the settings.
        model.openSettings()
        #expect(model.showingSettings)
        model.request(.search)
        #expect(model.hostListRequest == nil)
        model.showingSettings = false

        model.toggleSidebar()
        #expect(!model.sidebarShown)

        model.updateLayout(.compact)
        model.toggleSidebar()
        #expect(!model.sidebarShown)
        model.tab = .credentials
        model.request(.newGroup)
        #expect(model.tab == .hosts)
        #expect(model.hostListRequest == .newGroup)
        model.hostListRequest = nil
        model.openSettings()
        #expect(model.tab == .settings)
        #expect(!model.showingSettings)

        // Not under the terminal over a narrow window.
        model.tab = .hosts
        _ = try await open("a")
        model.request(.search)
        model.openSettings()
        #expect(model.hostListRequest == nil)
        #expect(model.tab == .hosts)
        model.closeShown()
        #expect(model.shownSession == nil)
        #expect(model.sessions.isEmpty)
    }

    @Test func theFilesShowBesideATerminalOfAWideWindow() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        // The start page has no terminal to show the files of.
        model.toggleFiles()
        #expect(!model.showsFiles)
        let a = try await open("a")[0]
        model.toggleFiles()
        #expect(model.showsFiles)
        model.toggleFiles()
        #expect(!model.showsFiles)

        // Kept by host, as the desktop's right sidebar: a host connected
        // after shows none, and its tab and another of the first host's
        // show what their host had.
        model.toggleFiles()
        let b = try await open("b")[1]
        #expect(!model.showsFiles)
        model.shownSession = a
        #expect(model.showsFiles)
        try model.connect(a.host)
        #expect(model.showsFiles)
        model.shownSession = b
        #expect(!model.showsFiles)
        model.toggleFiles()
        model.shownSession = a
        model.toggleFiles()
        #expect(!model.showsFiles)
        model.shownSession = b
        #expect(model.showsFiles)

        // A narrow window shows them over the terminal, from its button:
        // ⌘⌥B leaves what a wide one would show as it was.
        model.updateLayout(.compact)
        model.toggleFiles()
        #expect(model.showsFiles)
    }

    @Test func syncsReviewOpensWhereTheWindowHasTheSettings() {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        model.reviewSync()
        #expect(model.showingSettings)
        #expect(model.tab == .hosts)
        #expect(model.settingsPath == [.sync])

        model.showingSettings = false
        model.settingsPath = []
        model.updateLayout(.compact)
        model.reviewSync()
        #expect(!model.showingSettings)
        #expect(model.tab == .settings)
        #expect(model.settingsPath == [.sync])
    }

    @Test func foldingKeepsSelectionSurfaceAndFilesWhileChangingPresentation() async throws {
        model.updateLayout(AppLayout(width: 900, regular: true))
        let session = try await open("a")[0]
        let surface = session.surface
        surface.feed(Data("survives-folding".utf8))
        let files = session.openFiles()
        files.path = ["/tmp", "/tmp/work"]
        let folder = files.folderState(for: "/tmp/work")
        folder.name = "unfinished-name"
        folder.naming = .newFolder
        folder.selection = ["one.txt"]
        model.showsFiles = true
        #expect(model.sidebarShown)
        #expect(!model.sidebarVisible)
        // A system collapse must not erase the user's sidebar preference.
        model.setSidebarVisible(false)
        #expect(model.sidebarShown)

        for _ in 0..<5 {
            model.updateLayout(.compact)
            #expect(model.compactTerminalPresented)
            #expect(model.shownSession === session)
            #expect(model.showsFiles)
            model.updateLayout(AppLayout(width: 900, regular: true))
        }
        #expect(session.surface === surface)
        #expect(surface.text.contains("survives-folding"))
        #expect(session.openFiles() === files)
        #expect(files.path == ["/tmp", "/tmp/work"])
        #expect(files.folderState(for: "/tmp/work") === folder)
        #expect(folder.name == "unfinished-name")
        #expect(folder.naming == .newFolder)
        #expect(folder.selection == ["one.txt"])

        model.showsFiles = false
        #expect(model.sidebarVisible)
        model.updateLayout(.compact)
        model.hideTerminal()
        #expect(model.shownSession === session)
        #expect(!model.compactTerminalPresented)
        #expect(model.canPresent)
        model.show(session)
        #expect(model.compactTerminalPresented)
        #expect(!model.canPresent)
    }

    @Test func sheetsSearchAndSettingsRoutesSurviveAChangeOfShell() {
        model.hostListState.query = "production"
        model.hostListState.foldedInSearch = [42]
        model.credentialListState.query = "deploy"
        model.sheet = .host(.new(group: 42))
        let sheetID = model.presentedSheet?.id
        model.updateLayout(AppLayout(width: 900, regular: true))
        model.updateLayout(.compact)
        #expect(model.presentedSheet?.id == sheetID)
        #expect(model.hostListState.query == "production")
        #expect(model.hostListState.foldedInSearch == [42])
        #expect(model.credentialListState.query == "deploy")
        model.dismissSheet()
        #expect(model.presentedSheet == nil)

        model.tab = .settings
        model.settingsPath = [.sync]
        model.updateLayout(AppLayout(width: 900, regular: true))
        #expect(model.showingSettings)
        #expect(model.presentedSheet?.id == "settings")
        model.updateLayout(.compact)
        #expect(model.presentedSheet?.id == "settings")
        #expect(model.settingsPath == [.sync])
    }
}
