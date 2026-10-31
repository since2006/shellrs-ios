import Foundation
import Observation
import ShellRSCore
import UIKit

/// The app's tabs, on an iPhone or a narrow iPad window.
enum AppTab: Hashable {
    case hosts
    case terminals
    case credentials
    case settings
}

/// The lists the sidebar of a wide window switches between, as the
/// desktop's sidebar does.
enum SidebarList: Hashable {
    case hosts
    case credentials
}

/// What a command asks of the host list.
enum HostListRequest: Equatable {
    case newHost
    case newGroup
    case search
}

/// The terminal tabs a tab's menu closes with it, as on the desktop.
enum TabsAround {
    case left
    case right
    case others
    case all
}

/// What the app holds while it runs: the core, the saved hosts, sync and
/// the terminals open.
@MainActor
@Observable
final class AppModel {
    let core: Core
    let hosts: HostsModel
    let sync: SyncModel
    var tab = AppTab.hosts
    var settingsPath: [SettingsRoute] = []
    /// The terminals open, oldest first: the tabs of a wide window.
    private(set) var sessions: [TerminalSession] = []
    /// The terminal shown: over everything else in a narrow window, the
    /// tab in front in a wide one (none: the start page).
    var shownSession: TerminalSession? {
        didSet {
            if shownSession !== oldValue {
                oldValue?.surface.dismissInput()
                compactTerminalPresented = shownSession != nil
            }
        }
    }
    /// Selection survives 收起 and automatic layout changes. Presentation is separate.
    var compactTerminalPresented = false
    private(set) var layout = AppLayout.compact
    var sheet: AppSheet?
    let hostListState = HostListState()
    let credentialListState = CredentialListState()
    /// Whether the window is a wide one: a sidebar and the terminal
    /// tabs beside it, rather than the iPhone's tabs.
    var isWide: Bool { layout.isWide }
    var sidebarList = SidebarList.hosts
    /// Whether a wide window shows its sidebar; hidden, the terminal has
    /// the width.
    var sidebarShown = true
    /// Whether a wide window shows the files of the terminal in front
    /// beside it, as the desktop's right sidebar does; a narrow one shows
    /// them over the terminal when asked. Kept by host as the desktop keeps
    /// its right sidebar: a tab brought forward shows them if its host's
    /// were shown, and a host never shown them does not.
    var showsFiles: Bool {
        get {
            shownSession.map { filesShown.contains($0.host.id) } ?? false
        }
        set {
            guard let host = shownSession?.host.id else {
                return
            }
            if newValue {
                filesShown.insert(host)
            } else {
                filesShown.remove(host)
            }
        }
    }
    /// The hosts whose files are shown, while the app runs: its terminals
    /// do not outlive it either.
    private var filesShown: Set<UInt64> = []
    /// The settings, over a wide window; a narrow one has a tab for them.
    var showingSettings = false

    /// One stable sheet host outside both layout branches. Authentication can wait
    /// behind an editor, but a fold never answers or cancels its prompt.
    var presentedSheet: AppSheet? {
        if let sheet { return sheet }
        if showingSettings { return .settings }
        if let session = shownSession, isWide || compactTerminalPresented,
            let prompt = session.prompt
        {
            return .login(session, prompt)
        }
        return nil
    }

    func dismissSheet() {
        // Authentication has explicit buttons and disallows interactive dismissal.
        // A system presentation update must never be treated as a user cancellation.
        if sheet != nil {
            sheet = nil
        } else if showingSettings {
            showingSettings = false
        }
    }

    func updateLayout(_ layout: AppLayout) {
        let wasWide = isWide
        self.layout = layout
        if wasWide && !isWide {
            compactTerminalPresented = shownSession != nil
        } else if !wasWide && isWide {
            if shownSession == nil {
                sidebarList = tab == .credentials ? .credentials : .hosts
            }
            if tab == .settings {
                showingSettings = true
                tab = .hosts
            }
        }
    }

    func show(_ session: TerminalSession) {
        shownSession = session
        compactTerminalPresented = true
    }

    func hideTerminal() {
        shownSession?.surface.dismissInput()
        compactTerminalPresented = false
    }

    var sidebarVisible: Bool {
        layout.showsSidebar(requested: sidebarShown, filesShown: showsFiles)
    }

    var filesCoverTerminal: Bool {
        showsFiles && (isWide || compactTerminalPresented) && !layout.fitsFilesBesideTerminal
    }

    var terminalInputAllowed: Bool {
        guard presentedSheet == nil, !filesCoverTerminal else { return false }
        if showsFiles, let files = shownSession?.files {
            let folder = files.folderState(for: files.path.last ?? "/")
            if folder.naming != nil || folder.importing || !folder.deleting.isEmpty
                || files.question != nil || files.preview != nil || files.notice != nil
            {
                return false
            }
        }
        return hostListState.deleting == nil && credentialListState.deleting == nil
    }

    func setSidebarVisible(_ visible: Bool) {
        // Automatic space budgeting is temporary, not a change in preference.
        if !visible, showsFiles, !layout.fitsThreeColumns { return }
        if visible, showsFiles, !layout.fitsThreeColumns {
            showsFiles = false
        }
        sidebarShown = visible
    }
    /// What a command asks of the host list, which does it once shown.
    var hostListRequest: HostListRequest?
    /// The terminals' text size in points, the same in all of them; this
    /// device's own, not synced.
    var fontSize: Double {
        didSet {
            defaults.set(fontSize, forKey: Self.fontSizeKey)
            for session in sessions {
                session.surface.fontSize = fontSize
            }
        }
    }

    /// The desktop's default text size and range.
    static let defaultFontSize = 13.0
    static let fontSizes = 10.0...28.0
    private static let fontSizeKey = "terminalFontSize"
    @ObservationIgnored private let defaults: UserDefaults

    init(core: Core, deviceName: String, defaults: UserDefaults = .standard) {
        self.core = core
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.fontSizeKey)
        fontSize = Self.fontSizes.contains(saved) ? saved : Self.defaultFontSize
        hosts = HostsModel(store: core.store())
        sync = SyncModel(service: core.sync(), deviceName: deviceName)
        hosts.onChange = { [sync] in
            sync.storeChanged()
        }
    }

    /// Opens the core on the app's data folder and keychain.
    static func open() throws -> AppModel {
        LocalFolders.clearLeftovers()
        let deviceName = UIDevice.current.name
        let config = CoreConfig(
            dataDir: DataFolder.url.path,
            deviceName: deviceName,
            platform: "ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        )
        return AppModel(
            core: try Core(config: config, keychain: AppKeychain()), deviceName: deviceName)
    }

    /// Opens a terminal on `host` and shows it. Only SSH connects here: a
    /// Telnet host fails with `StoreError.NotSsh`.
    func connect(_ host: Host) throws {
        guard host.isSsh else {
            throw StoreError.NotSsh
        }
        let session = TerminalSession(host: host, core: core, fontSize: fontSize)
        session.onClose = { [weak self, weak session] in
            if let self, let session {
                close(session)
            }
        }
        sessions.append(session)
        shownSession = session
        session.start()
    }

    /// The app came back to the foreground: the connections may have died
    /// while it was away, and sync may be due.
    func cameForward() {
        for session in sessions {
            Task {
                await session.checkAlive()
            }
        }
        sync.cameForward()
    }

    /// Whether a command may show the host list or the settings now: not
    /// under the terminal over a narrow window, nor behind the settings
    /// over a wide one.
    var canPresent: Bool {
        presentedSheet == nil && (isWide || !compactTerminalPresented)
    }

    /// Shows the host list, and has it do `request`: ⌘N, ⌘⇧N, ⌘K.
    func request(_ request: HostListRequest) {
        guard canPresent else {
            return
        }
        if isWide {
            sidebarList = .hosts
            sidebarShown = true
        } else {
            tab = .hosts
        }
        hostListRequest = request
    }

    /// ⌘,: the settings sheet of a wide window, the tab of a narrow one.
    func openSettings() {
        guard canPresent else {
            return
        }
        if isWide {
            showingSettings = true
        } else {
            tab = .settings
        }
    }

    /// ⌘B: only a wide window has the sidebar.
    func toggleSidebar() {
        if isWide {
            setSidebarVisible(!sidebarVisible)
        }
    }

    /// ⌘⌥B: the files beside the terminal in front of a wide window.
    func toggleFiles() {
        if isWide, shownSession != nil {
            showsFiles.toggle()
        }
    }

    /// ⌘W: closes the terminal shown.
    func closeShown() {
        if let shownSession {
            close(shownSession)
        }
    }

    /// ⌘= / ⌘- / ⌘0: a point bigger or smaller, within the range, or back
    /// to the default.
    func biggerText() {
        fontSize = min(fontSize + 1, Self.fontSizes.upperBound)
    }

    func smallerText() {
        fontSize = max(fontSize - 1, Self.fontSizes.lowerBound)
    }

    func defaultText() {
        fontSize = Self.defaultFontSize
    }

    /// Opens the sync page on what sync waits for the user to settle.
    func reviewSync() {
        if isWide {
            showingSettings = true
        } else {
            tab = .settings
        }
        settingsPath = [.sync]
        sync.reviewRequested = true
    }

    /// Ends `session` and forgets it. Closing the tab in front of a wide
    /// window brings the one to its right forward, else the one to its
    /// left, as the desktop's tabs do; a narrow window goes back to the
    /// list.
    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else {
            return
        }
        end(session)
        sessions.remove(at: index)
        if shownSession === session {
            shownSession =
                isWide && !sessions.isEmpty ? sessions[min(index, sessions.count - 1)] : nil
        }
    }

    /// Closes the tabs to one side of `session`, all but it, or all of
    /// them, from a tab's menu; `session` comes forward if it stays.
    func close(_ around: TabsAround, of session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else {
            return
        }
        let closing: [TerminalSession] =
            switch around {
            case .left: Array(sessions[..<index])
            case .right: Array(sessions[(index + 1)...])
            case .others: sessions.filter { $0 !== session }
            case .all: sessions
            }
        for other in closing {
            end(other)
        }
        sessions.removeAll { open in closing.contains { $0 === open } }
        shownSession = around == .all ? nil : session
    }

    /// Brings the `number`th tab forward, from 1: ⌘1 to ⌘8 go to that tab
    /// and ⌘9 to the last, as in a browser. A tab that is not there does
    /// nothing.
    func select(tab number: Int) {
        if number == 9 {
            shownSession = sessions.last ?? shownSession
        } else if sessions.indices.contains(number - 1) {
            shownSession = sessions[number - 1]
        }
    }

    /// Brings the next tab forward, round to the first.
    func selectNext() {
        step(by: 1)
    }

    /// Brings the previous tab forward, round to the last.
    func selectPrevious() {
        step(by: -1)
    }

    private func step(by offset: Int) {
        guard !sessions.isEmpty else {
            return
        }
        guard let index = sessions.firstIndex(where: { $0 === shownSession }) else {
            shownSession = offset > 0 ? sessions.first : sessions.last
            return
        }
        let count = sessions.count
        shownSession = sessions[(index + offset + count) % count]
    }

    private func end(_ session: TerminalSession) {
        if case .login(let owner, _) = sheet, owner === session { sheet = nil }
        if let files = session.files {
            switch sheet {
            case .transfers(let owner), .downloads(let owner), .file(let owner, _):
                if owner === files { sheet = nil }
            default: break
            }
        }
        session.files?.end()
        session.disconnect()
    }
}

/// Where the core keeps its data: Application Support/ShellRS.
enum DataFolder {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "ShellRS", directoryHint: .isDirectory)
    }
}
