import Foundation
import Observation
import ShellRSCore

/// The saved hosts as the screens show them: a copy of the store's, read
/// again whenever the store says it changed.
@MainActor
@Observable
final class HostsModel {
    let store: HostStore
    private(set) var hosts: [Host] = []
    /// What the store could not keep, until the user has seen it.
    var problem: String?

    init(store: HostStore) {
        self.store = store
        reload()
        Task { [weak self, store] in
            while let event = await store.nextEvent() {
                guard let self else { return }
                switch event {
                case .changed:
                    reload()
                case .failed(let failure):
                    problem = Describe.storeFailure(failure)
                }
            }
        }
    }

    func reload() {
        hosts = store.hosts()
    }

    /// Saves a new host, or the changes to `id`; returns the host's id.
    @discardableResult
    func save(
        id: UInt64?, draft: HostDraft, password: SecretChange
    ) async throws -> UInt64 {
        let saved: UInt64
        if let id {
            try await store.updateHost(
                id: id, draft: draft, password: password, proxyPassword: .keep)
            saved = id
        } else {
            saved = try await store.addHost(
                draft: draft, password: password, proxyPassword: .keep)
        }
        reload()
        return saved
    }

    func delete(_ host: Host) throws {
        try store.deleteHost(id: host.id)
        reload()
    }

    /// The host's saved password, read from the keychain off the main
    /// thread.
    func savedPassword(of host: Host) async -> String? {
        try? await store.savedSecret(secret: .hostPassword(host: host.id))
    }
}

extension Host {
    /// The name shown for the host: its own, or its address.
    var title: String {
        name.isEmpty ? address : name
    }

    /// user@address:port as the list shows it under the name.
    var subtitle: String {
        var text = address
        if !user.isEmpty {
            text = "\(user)@\(text)"
        }
        if port != 22 {
            text += ":\(port)"
        }
        return text
    }

    var isSsh: Bool {
        if case .ssh = `protocol` {
            return true
        }
        return false
    }
}
