import ShellRSCore

/// The host tree as the list shows it, built the desktop's way: each level
/// lists its subgroups first, then its hosts; hosts with no group sit at the
/// top beside the top-level groups.
struct HostTree: Equatable {
    struct Branch: Equatable, Identifiable {
        let group: Group
        let tree: HostTree

        var id: UInt64 { group.id }
    }

    private(set) var branches: [Branch] = []
    private(set) var hosts: [Host] = []

    var isEmpty: Bool {
        branches.isEmpty && hosts.isEmpty
    }

    /// The tree of `groups` and `hosts`, each in the store's order. A query
    /// keeps the hosts it matches and the groups it matches with all that is
    /// in them, and drops the groups left with neither.
    init(groups: [Group], hosts: [Host], query: String = "") {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        self.init(
            groups: groups, hosts: hosts, query: query, parent: nil,
            everything: query.isEmpty, depth: 0)
    }

    private init(
        groups: [Group], hosts: [Host], query: String, parent: UInt64?, everything: Bool,
        depth: Int
    ) {
        // Deeper than there are groups only with a cycle, which the core
        // never makes: stop rather than recurse forever.
        guard depth <= groups.count else {
            return
        }
        for group in groups where group.parent == parent {
            let matched = everything || group.name.lowercased().contains(query)
            let tree = HostTree(
                groups: groups, hosts: hosts, query: query, parent: group.id,
                everything: matched, depth: depth + 1)
            if matched || !tree.isEmpty {
                branches.append(Branch(group: group, tree: tree))
            }
        }
        self.hosts = hosts.filter { $0.group == parent && (everything || $0.matches(query)) }
    }

    /// Where a row dragged among its siblings lands: before the one it was
    /// dropped on, or after the last. `nil` when it stays where it was.
    static func drop(moving index: Int, to destination: Int, among siblings: [TreeNode])
        -> TreeDrop?
    {
        guard siblings.indices.contains(index), destination != index, destination != index + 1
        else {
            return nil
        }
        guard destination < siblings.count else {
            return .after(node: siblings[siblings.count - 1])
        }
        return .before(node: siblings[destination])
    }

    /// Groups depth first, each named by its path (`生产 / 数据库`), for the
    /// pickers. A group `excluded` is left out with everything in it: a group
    /// cannot go into itself.
    static func groupOptions(_ groups: [Group], excluding excluded: UInt64? = nil)
        -> [GroupOption]
    {
        var options: [GroupOption] = []
        func add(under parent: UInt64?, prefix: String, depth: Int) {
            guard depth <= groups.count else {
                return
            }
            for group in groups where group.parent == parent && group.id != excluded {
                let path = prefix.isEmpty ? group.name : "\(prefix) / \(group.name)"
                options.append(GroupOption(id: group.id, path: path))
                add(under: group.id, prefix: path, depth: depth + 1)
            }
        }
        add(under: nil, prefix: "", depth: 0)
        return options
    }
}

/// A group as a picker lists it.
struct GroupOption: Hashable, Identifiable {
    let id: UInt64
    let path: String
}

extension Host {
    /// Whether what was typed in the search field finds the host: in its
    /// name, address or user, ignoring case, as on the desktop.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty
            || [name, address, user].contains { $0.lowercased().contains(query) }
    }
}
