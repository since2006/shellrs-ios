import Foundation
import Observation
import ShellRSCore
import UIKit

/// What the app holds while it runs: the core, the saved hosts and the
/// terminals open.
@MainActor
@Observable
final class AppModel {
    let core: Core
    let hosts: HostsModel
    /// The terminals open, oldest first.
    private(set) var sessions: [TerminalSession] = []
    /// The terminal shown over everything else, if any.
    var shownSession: TerminalSession?

    init(core: Core) {
        self.core = core
        hosts = HostsModel(store: core.store())
    }

    /// Opens the core on the app's data folder and keychain.
    static func open() throws -> AppModel {
        LocalFolders.clearLeftovers()
        let config = CoreConfig(
            dataDir: DataFolder.url.path,
            deviceName: UIDevice.current.name,
            platform: "ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        )
        return AppModel(core: try Core(config: config, keychain: AppKeychain()))
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
