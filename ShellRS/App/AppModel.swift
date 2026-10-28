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
    /// The settings, over a wide window; a narrow one has a tab for them.
    var showingSettings = false

    init(core: Core, deviceName: String) {
        self.core = core
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
        let session = TerminalSession(host: host, core: core)
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
