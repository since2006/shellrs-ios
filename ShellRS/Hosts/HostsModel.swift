import Foundation
import Observation
import ShellRSCore

/// A group of hosts: the core's `Group`, which SwiftUI's own hides in
/// the views.
typealias HostGroup = ShellRSCore.Group

/// The saved hosts, groups and credentials as the screens show them: a copy
/// of the store's, read again whenever the store says it changed.
@MainActor
@Observable
final class HostsModel {
    let store: HostStore
    private(set) var hosts: [Host] = []
    private(set) var groups: [Group] = []
    private(set) var credentials: [Credential] = []
    /// The hosts connected to lately, the latest first.
    private(set) var recent: [Host] = []
    /// What the store could not keep, until the user has seen it.
    var problem: String?
    /// Told when the store changed, by the user or by sync.
    var onChange: (@MainActor () -> Void)?

    init(store: HostStore) {
        self.store = store
        reload()
        Task { [weak self, store] in
            while let event = await store.nextEvent() {
                guard let self else { return }
                switch event {
                case .changed:
                    reload()
                    onChange?()
                case .failed(let failure):
                    problem = Describe.storeFailure(failure)
                }
            }
        }
    }

    func reload() {
        hosts = store.hosts()
        groups = store.groups()
        credentials = store.credentials()
        recent = store.recentHosts()
    }

    func host(_ id: UInt64) -> Host? {
        hosts.first { $0.id == id }
    }

    func group(_ id: UInt64) -> Group? {
        groups.first { $0.id == id }
    }

    func credential(_ id: UInt64) -> Credential? {
        credentials.first { $0.id == id }
    }

    // MARK: Hosts

    /// Saves a new host, or the changes to `id`; returns the host's id.
    @discardableResult
    func save(
        id: UInt64?, draft: HostDraft, password: SecretChange,
        proxyPassword: SecretChange = .keep
    ) async throws -> UInt64 {
        let saved: UInt64
        if let id {
            try await store.updateHost(
                id: id, draft: draft, password: password, proxyPassword: proxyPassword)
            saved = id
        } else {
            saved = try await store.addHost(
                draft: draft, password: password, proxyPassword: proxyPassword)
        }
        reload()
        return saved
    }

    func delete(_ host: Host) throws {
        try store.deleteHost(id: host.id)
        reload()
    }

    /// A copy of `host` just after it, named as the desktop names copies.
    @discardableResult
    func duplicate(_ host: Host) throws -> UInt64 {
        let id = try store.duplicateHost(
            id: host.id, name: String(localized: "\(host.name) 副本"))
        reload()
        return id
    }

    /// Moves a host or a group; whether it moved.
    @discardableResult
    func move(_ node: TreeNode, to drop: TreeDrop) -> Bool {
        let moved = store.moveNode(node: node, drop: drop)
        reload()
        return moved
    }

    /// What deleting `node` takes with it.
    func dependents(of node: TreeNode) -> Dependents {
        store.dependents(node: node)
    }

    /// A saved password or passphrase, read from the keychain off the main
    /// thread.
    func savedSecret(_ secret: SavedSecret) async -> String? {
        try? await store.savedSecret(secret: secret)
    }

    // MARK: Groups

    @discardableResult
    func saveGroup(id: UInt64?, draft: GroupDraft) throws -> UInt64 {
        let saved: UInt64
        if let id {
            try store.updateGroup(id: id, draft: draft)
            saved = id
        } else {
            saved = try store.addGroup(draft: draft)
        }
        reload()
        return saved
    }

    func delete(_ group: Group) throws {
        _ = try store.deleteGroup(id: group.id)
        reload()
    }

    func setExpanded(_ group: Group, _ expanded: Bool) {
        guard group.expanded != expanded else {
            return
        }
        store.setGroupExpanded(id: group.id, expanded: expanded)
        reload()
    }

    // MARK: Credentials

    /// Saves a new credential, or the changes to `id`; returns its id.
    @discardableResult
    func saveCredential(
        id: UInt64?, draft: CredentialDraft, key: KeyChange, password: SecretChange
    ) async throws -> UInt64 {
        let saved: UInt64
        if let id {
            try await store.updateCredential(id: id, draft: draft, key: key, password: password)
            saved = id
        } else {
            saved = try await store.addCredential(draft: draft, key: key, password: password)
        }
        reload()
        return saved
    }

    func delete(_ credential: Credential) throws {
        _ = try store.deleteCredential(id: credential.id)
        reload()
    }

    /// The hosts logging in with `credential`.
    func hostsUsing(_ credential: Credential) -> [UInt64] {
        store.hostsUsing(credential: credential.id)
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

extension Credential {
    /// `user · kind`, as the desktop sums a credential up.
    var summary: String {
        "\(user) · \(kind.label)"
    }
}

extension CredentialKind {
    var label: String {
        switch self {
        case .password: String(localized: "密码")
        case .key: String(localized: "密钥")
        case .agent: "SSH Agent"
        }
    }
}
