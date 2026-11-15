import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// The terminals: a list of them in either layout, the one chosen shown
/// over a narrow window's tabs or on a wide window's terminals' page.
@MainActor
struct AppModelTests {
    let test: TestCore
    let defaults: UserDefaults
    let model: AppModel

    init() throws {
        test = try TestCore()
        defaults = try #require(UserDefaults(suiteName: "AppModelTests.\(UUID().uuidString)"))
        model = AppModel(core: test.core, deviceName: "iPad", defaults: defaults)
    }

    /// Opens a terminal on each of `names`, saved on a port nothing listens
    /// on: what the list does does not need them connected.
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

    @Test(arguments: [AppLayout.compact, AppLayout(width: 1200, regular: true)])
    func closingTheShownTerminalGoesBackToTheList(layout: AppLayout) async throws {
        model.updateLayout(layout)
        let terminals = try await open("a", "b", "c")
        #expect(front == "c")
        #expect(model.terminalShown)

        // One not shown closes without changing the one shown.
        model.close(terminals[0])
        #expect(front == "c")
        #expect(model.terminalShown)
        model.close(terminals[2])
        #expect(model.shownSession == nil)
        #expect(!model.terminalShown)
        #expect(model.sessions.map(\.host.name) == ["b"])
    }

    @Test func aWideWindowsTerminalsPageIsTheirListUntilOneIsShown() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        let terminals = try await open("a", "b")
        #expect(model.tab == .terminals)
        #expect(model.terminalShown)

        // 收起: the list, the terminal still the one chosen and open.
        model.hideTerminal()
        #expect(!model.terminalShown)
        #expect(model.tab == .terminals)
        #expect(front == "b")
        // ⌘W and the files are for a terminal in sight.
        model.closeShown()
        #expect(model.sessions.count == 2)
        model.toggleFiles()
        #expect(!model.showsFiles)
        // Another page and back: still the list.
        model.tab = .hosts
        model.tab = .terminals
        #expect(!model.terminalShown)

        // A tap on one shows it; the page keeps it through another.
        model.show(terminals[0])
        #expect(front == "a")
        #expect(model.terminalShown)
        model.tab = .status
        #expect(!model.terminalShown)
        model.tab = .terminals
        #expect(model.terminalShown)
        // Shown from another page, even the one chosen already.
        model.hideTerminal()
        model.tab = .status
        model.show(terminals[0])
        #expect(model.tab == .terminals)
        #expect(model.terminalShown)
    }

    @Test func numbersAndArrowsPickATerminal() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        // Nothing open: nothing to pick.
        model.selectNext()
        model.selectTerminal(1)
        #expect(model.shownSession == nil)

        _ = try await open("a", "b", "c")
        model.selectTerminal(1)
        #expect(front == "a")
        // ⌘9 is the last, as in a browser; one not there does nothing.
        model.selectTerminal(9)
        #expect(front == "c")
        model.selectTerminal(5)
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
        // Put away, the one chosen comes out again.
        model.hideTerminal()
        model.selectTerminal(9)
        #expect(model.terminalShown)

        // Over a narrow window's tabs too.
        model.updateLayout(.compact)
        model.hideTerminal()
        model.selectNext()
        #expect(front == "a")
        #expect(model.terminalPresented)
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
        #expect(AppModel(core: test.core, deviceName: "iPad", defaults: defaults).fontSize == 16)
        defaults.set(99.0, forKey: "terminalFontSize")
        #expect(AppModel(core: test.core, deviceName: "iPad", defaults: defaults).fontSize == 13)
    }

    @Test func commandsShowTheListWhereTheWindowHasIt() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        model.tab = .status
        model.sidebarShown = false
        // The hosts are a page: the sidebar can stay hidden.
        model.request(.newHost)
        #expect(model.tab == .hosts)
        #expect(!model.sidebarShown)
        #expect(model.hostListRequest == .newHost)
        model.hostListRequest = nil

        // The settings are a page too, not a sheet in the way.
        model.openSettings()
        #expect(model.tab == .settings)
        #expect(model.presentedSheet == nil)
        model.request(.search)
        #expect(model.tab == .hosts)
        #expect(model.hostListRequest == .search)
        model.hostListRequest = nil

        // Not behind a sheet.
        model.sheet = .host(.new(group: nil))
        model.openSettings()
        #expect(model.tab == .hosts)
        model.sheet = nil

        model.toggleSidebar()
        #expect(model.sidebarShown)
        model.toggleSidebar()
        #expect(!model.sidebarShown)

        model.updateLayout(.compact)
        model.toggleSidebar()
        #expect(!model.sidebarShown)
        model.tab = .status
        model.request(.newGroup)
        #expect(model.tab == .hosts)
        #expect(model.hostListRequest == .newGroup)
        model.hostListRequest = nil
        model.openSettings()
        #expect(model.tab == .settings)
        #expect(model.presentedSheet == nil)

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
        #expect(model.tab == .settings)
        #expect(model.presentedSheet == nil)
        #expect(model.settingsPath == [.sync])

        model.tab = .status
        model.settingsPath = []
        model.updateLayout(.compact)
        model.reviewSync()
        #expect(model.tab == .settings)
        #expect(model.settingsPath == [.sync])
    }

    @Test func aWideWindowOpensOnItsTerminalsAndShowsOneThere() async throws {
        // 状态 has nothing to show: a narrow window opens on the hosts.
        #expect(model.tab == .hosts)
        model.updateLayout(AppLayout(width: 1200, regular: true))
        // The start page, the hosts connected lately.
        #expect(model.tab == .terminals)
        #expect(!model.terminalShown)

        // Connecting from another page brings the terminals' page forward.
        model.tab = .status
        let a = try await open("a")[0]
        #expect(model.tab == .terminals)
        #expect(model.terminalShown)

        // Behind another page, the terminal is neither closed by ⌘W nor
        // given its files.
        model.tab = .hosts
        #expect(!model.terminalShown)
        model.closeShown()
        #expect(model.sessions.count == 1)
        model.toggleFiles()
        #expect(!model.showsFiles)
        model.showsFiles = true
        #expect(!model.filesCoverTerminal)
        model.showsFiles = false

        // A terminal chosen by its keys comes with its page, even the one
        // chosen already.
        model.selectTerminal(1)
        #expect(model.tab == .terminals)
        model.tab = .status
        model.selectNext()
        #expect(model.shownSession === a)
        #expect(model.tab == .terminals)
        model.tab = .status
        model.selectTerminal(5)
        #expect(model.tab == .status)
        model.tab = .terminals
        model.closeShown()
        #expect(model.sessions.isEmpty)
        #expect(model.tab == .terminals)

        // Once measured, a window keeps its page as it widens again.
        model.tab = .status
        model.updateLayout(.compact)
        model.updateLayout(AppLayout(width: 1200, regular: true))
        #expect(model.tab == .status)
    }

    @Test func narrowingFromAnotherPageLeavesTheTerminalBehindTheTabs() async throws {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        let a = try await open("a")[0]
        model.tab = .status
        model.updateLayout(.compact)
        #expect(!model.terminalPresented)
        #expect(model.shownSession === a)
        #expect(model.tab == .status)

        // Shown over the tabs, it is the page a wide window widens to.
        model.show(a)
        model.tab = .hosts
        model.updateLayout(AppLayout(width: 1200, regular: true))
        #expect(model.tab == .terminals)
        model.updateLayout(.compact)
        #expect(model.terminalPresented)
    }

    @Test func theCredentialsAreInTheSettingsOfANarrowWindow() {
        model.updateLayout(AppLayout(width: 1200, regular: true))
        model.tab = .credentials
        model.updateLayout(.compact)
        #expect(model.tab == .settings)
        #expect(model.settingsPath == [.credentials])
        model.updateLayout(AppLayout(width: 1200, regular: true))
        #expect(model.tab == .credentials)
        #expect(model.settingsPath.isEmpty)

        // Sync stays where it was.
        model.tab = .settings
        model.settingsPath = [.sync]
        model.updateLayout(.compact)
        model.updateLayout(AppLayout(width: 1200, regular: true))
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
            #expect(model.terminalPresented)
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
        #expect(!model.terminalPresented)
        #expect(model.canPresent)
        model.show(session)
        #expect(model.terminalPresented)
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
        #expect(model.tab == .settings)
        #expect(model.presentedSheet == nil)
        model.updateLayout(.compact)
        #expect(model.tab == .settings)
        #expect(model.settingsPath == [.sync])
    }
}
