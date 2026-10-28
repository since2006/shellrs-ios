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

/// The lists the sidebar of a wide iPad window switches between, as the
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
    var shownSession: TerminalSession?
    /// Whether the window is a wide iPad one: a sidebar and the terminal
    /// tabs beside it, rather than the iPhone's tabs.
    var isWide = false
    var sidebarList = SidebarList.hosts
    /// Whether a wide window shows its sidebar; hidden, the terminal has
    /// the width.
    var sidebarShown = true
    /// The settings, over a wide window; a narrow one has a tab for them.
    var showingSettings = false
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
        isWide ? !showingSettings : shownSession == nil
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
            sidebarShown.toggle()
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
            shownSession = isWide && !sessions.isEmpty ? sessions[min(index, sessions.count - 1)] : nil
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
