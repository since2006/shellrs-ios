import Foundation
import Observation
import ShellRSCore
import UIKit

/// The app's tabs.
enum AppTab: Hashable {
    case hosts
    case terminals
    case credentials
    case settings
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
    /// The terminals open, oldest first.
    private(set) var sessions: [TerminalSession] = []
    /// The terminal shown over everything else, if any.
    var shownSession: TerminalSession?

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

    /// Opens a terminal on `host` and shows it.
    func connect(_ host: Host) {
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
        tab = .settings
        settingsPath = [.sync]
        sync.reviewRequested = true
    }

    /// Ends `session` and forgets it.
    func close(_ session: TerminalSession) {
        session.files?.end()
        session.disconnect()
        sessions.removeAll { $0 === session }
        if shownSession === session {
            shownSession = nil
        }
    }
}

/// Where the core keeps its data: Application Support/ShellRS.
enum DataFolder {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "ShellRS", directoryHint: .isDirectory)
    }
}
