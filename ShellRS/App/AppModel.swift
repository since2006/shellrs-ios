import Foundation
import Observation
import ShellRSCore
import UIKit

/// What the window shows: a narrow one's tabs, or the page chosen in the
/// sidebar of a wide one, as an admin console's menu. A narrow window has
/// no tab for the credentials: they are in its settings.
enum AppTab: Hashable {
    case status
    case hosts
    /// The terminals open, one of them shown in their place until 收起;
    /// on a wide window the hosts connected lately while none is open.
    case terminals
    case credentials
    case settings
}

/// What a command asks of the host list.
enum HostListRequest: Equatable {
    case newHost
    case newGroup
    case search
}

/// What the app holds while it runs: the core, the saved hosts, sync and
/// the terminals open.
@MainActor
@Observable
final class AppModel {
    let core: Core
    let hosts: HostsModel
    let purchases: PurchaseModel
    let ads: AdsModel
    let sync: SyncModel
    let status: StatusModel
    /// 状态 first, once it has hosts to show; the hosts until then. A wide
    /// window opens on its terminals: the hosts connected lately.
    var tab = AppTab.hosts
    var settingsPath: [SettingsRoute] = []
    var statusPath: [StatusRoute] = []
    /// The terminals open, oldest first.
    private(set) var sessions: [TerminalSession] = []
    /// The terminal chosen last: over the tabs of a narrow window, in the
    /// place of the list on a wide window's terminals' page.
    var shownSession: TerminalSession? {
        didSet {
            if shownSession !== oldValue {
                oldValue?.surface.dismissInput()
                terminalPresented = shownSession != nil
                // A wide window shows it on its terminals' page.
                if isWide, shownSession != nil {
                    tab = .terminals
                }
            }
        }
    }
    /// Whether the terminal chosen is shown rather than the list of them,
    /// in either layout. The choice survives 收起 and changes of layout.
    var terminalPresented = false
    private(set) var layout = AppLayout.compact
    /// Whether the window has been measured: the first time, a wide one
    /// opens on its terminals.
    @ObservationIgnored private var laidOut = false
    var sheet: AppSheet?
    let hostListState = HostListState()
    let credentialListState = CredentialListState()
    /// Whether the window is a wide one: a sidebar and the page chosen in
    /// it beside, rather than the iPhone's tabs.
    var isWide: Bool { layout.isWide }
    /// Whether a wide window shows its sidebar; hidden, the page has the
    /// width.
    var sidebarShown = true
    /// Whether a wide window shows the files of the terminal shown beside
    /// it, as the desktop's right sidebar does; a narrow one shows them
    /// over the terminal when asked. Kept by host as the desktop keeps its
    /// right sidebar: a terminal shown shows them if its host's were shown,
    /// and a host never shown them does not.
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

    /// One stable sheet host outside both layout branches. Authentication can wait
    /// behind an editor, but a fold never answers or cancels its prompt.
    var presentedSheet: AppSheet? {
        if let sheet { return sheet }
        if let session = shownSession, terminalPresented,
            let prompt = session.prompt
        {
            return .login(session, prompt)
        }
        return nil
    }

    func dismissSheet() {
        // Authentication has explicit buttons and disallows interactive dismissal.
        // A system presentation update must never be treated as a user cancellation.
        sheet = nil
    }

    func updateLayout(_ layout: AppLayout) {
        let wasWide = isWide
        let first = !laidOut
        laidOut = true
        self.layout = layout
        if first, isWide {
            // As the desktop's start page: the hosts connected lately.
            tab = .terminals
        } else if wasWide && !isWide {
            // The terminal over the tabs only if it was the page shown.
            terminalPresented = terminalPresented && shownSession != nil && tab == .terminals
            if tab == .credentials {
                tab = .settings
                settingsPath = [.credentials]
            }
        } else if !wasWide && isWide {
            if terminalPresented {
                tab = .terminals
            } else if tab == .settings, settingsPath.first == .credentials {
                tab = .credentials
                settingsPath = []
            }
        }
    }

    /// Shows `session` in the place of the list, as a tap on it does.
    func show(_ session: TerminalSession) {
        shownSession = session
        terminalsForward()
    }

    /// 收起: back to the list, the terminal still chosen and connected.
    func hideTerminal() {
        shownSession?.surface.dismissInput()
        terminalPresented = false
    }

    var sidebarVisible: Bool {
        layout.showsSidebar(requested: sidebarShown, filesShown: showsFiles && terminalShown)
    }

    /// Whether the terminal chosen is in sight: over a narrow window's
    /// tabs, or on a wide window's terminals' page.
    var terminalShown: Bool {
        shownSession != nil && terminalPresented && (!isWide || tab == .terminals)
    }

    var filesCoverTerminal: Bool {
        showsFiles && terminalShown && !layout.fitsFilesBesideTerminal
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
        let filesBeside = showsFiles && terminalShown
        if !visible, filesBeside, !layout.fitsThreeColumns { return }
        if visible, filesBeside, !layout.fitsThreeColumns {
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

    /// Kept locally with the terminal size, independent of cloud sync.
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// The desktop's default text size and range.
    static let defaultFontSize = 13.0
    static let fontSizes = 10.0...28.0
    private static let fontSizeKey = "terminalFontSize"
    private static let appearanceKey = "appAppearance"
    @ObservationIgnored private let defaults: UserDefaults

    init(
        core: Core, deviceName: String, defaults: UserDefaults = .standard,
        purchases: PurchaseModel = PurchaseModel(), ads: AdsModel = AdsModel()
    ) {
        self.purchases = purchases
        self.ads = ads
        self.core = core
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
        let saved = defaults.double(forKey: Self.fontSizeKey)
        fontSize = Self.fontSizes.contains(saved) ? saved : Self.defaultFontSize
        hosts = HostsModel(store: core.store())
        sync = SyncModel(service: core.sync(), deviceName: deviceName)
        let status = StatusModel(core: core, hosts: hosts, defaults: defaults)
        self.status = status
        hosts.onChange = { [sync, status] in
            sync.storeChanged()
            status.hostsChanged()
        }
        if !status.shownHosts.isEmpty {
            tab = .status
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
        Task {
            await purchases.refresh()
            await ads.cameForward()
        }
        for session in sessions {
            Task {
                await session.checkAlive()
            }
        }
        sync.cameForward()
        status.cameForward()
    }

    /// The app is going to the background, where iOS soon suspends it.
    func wentToBackground() {
        sync.goingToBackground()
        status.wentToBackground()
    }

    /// Whether a command may show the host list or the settings now: not
    /// under the terminal over a narrow window, nor behind a sheet.
    var canPresent: Bool {
        presentedSheet == nil && (isWide || !terminalPresented)
    }

    /// Shows the host list, and has it do `request`: ⌘N, ⌘⇧N, ⌘K.
    func request(_ request: HostListRequest) {
        guard canPresent else {
            return
        }
        tab = .hosts
        hostListRequest = request
    }

    /// ⌘,: the settings' page or tab.
    func openSettings() {
        guard canPresent else {
            return
        }
        tab = .settings
    }

    /// 去除广告 under an ad: the settings, where the purchase is.
    func openAdSettings() {
        settingsPath = []
        openSettings()
    }

    /// ⌘B: only a wide window has the sidebar.
    func toggleSidebar() {
        if isWide {
            setSidebarVisible(!sidebarVisible)
        }
    }

    /// ⌘⌥B: the files beside the terminal shown on a wide window.
    func toggleFiles() {
        if isWide, terminalShown {
            showsFiles.toggle()
        }
    }

    /// ⌘W: closes the terminal in sight, not one put away or behind
    /// another page of a wide window.
    func closeShown() {
        if let shownSession, terminalShown {
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
        tab = .settings
        settingsPath = [.sync]
        sync.reviewRequested = true
    }

    /// Ends `session` and forgets it. Closing the terminal shown goes back
    /// to the list, in either layout.
    func close(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else {
            return
        }
        end(session)
        sessions.remove(at: index)
        if shownSession === session {
            shownSession = nil
        }
    }

    /// Shows the `number`th terminal, from 1: ⌘1 to ⌘8 go to that one and
    /// ⌘9 to the last, as in a browser. One that is not there does nothing.
    func selectTerminal(_ number: Int) {
        if number == 9 {
            shownSession = sessions.last ?? shownSession
        } else if sessions.indices.contains(number - 1) {
            shownSession = sessions[number - 1]
        } else {
            return
        }
        terminalsForward()
    }

    /// Shows the next terminal, round to the first.
    func selectNext() {
        step(by: 1)
    }

    /// Shows the previous terminal, round to the last.
    func selectPrevious() {
        step(by: -1)
    }

    private func step(by offset: Int) {
        guard !sessions.isEmpty else {
            return
        }
        defer { terminalsForward() }
        guard let index = sessions.firstIndex(where: { $0 === shownSession }) else {
            shownSession = offset > 0 ? sessions.first : sessions.last
            return
        }
        let count = sessions.count
        shownSession = sessions[(index + offset + count) % count]
    }

    /// A terminal chosen is shown, even the one chosen already: over a
    /// narrow window's tabs, on a wide window's terminals' page.
    private func terminalsForward() {
        guard shownSession != nil else { return }
        terminalPresented = true
        if isWide {
            tab = .terminals
        }
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
