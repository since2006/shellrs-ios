import ShellRSCore
import SwiftUI

/// The 主机 tab of a narrow window: the list in a stack of its own.
struct HostListView: View {
    var body: some View {
        NavigationStack {
            HostList()
        }
    }
}

/// The saved hosts as a tree of groups, the latest connected above it: tap
/// a host to connect, swipe or hold a row for the rest, 排序 to drag. Its
/// container gives it the navigation bar: the 主机 tab or the sidebar.
struct HostList: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var searchShown = false
    @State private var editMode = EditMode.inactive
    @State private var editingHost: HostEditor.Subject?
    @State private var editingGroup: GroupEditor.Subject?
    @State private var deleting: Deletion?
    @State private var failure: String?

    /// How many of the latest connected go above the tree.
    private static let recentShown = 3

    var body: some View {
        @Bindable var hosts = model.hosts
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let tree = HostTree(groups: hosts.groups, hosts: hosts.hosts, query: query)
        let showsRecent = !searching && !editMode.isEditing && !hosts.recent.isEmpty
        let isEmpty = hosts.hosts.isEmpty && hosts.groups.isEmpty
        List {
            if showsRecent {
                Section("最近连接") {
                    ForEach(hosts.recent.prefix(Self.recentShown), id: \.id) { host in
                        HostButton(host: host, actions: actions)
                    }
                }
            }
            Section {
                HostLevel(tree: tree, searching: searching, actions: actions)
            } header: {
                if showsRecent {
                    Text("全部主机")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $query, isPresented: $searchShown, prompt: "搜索主机或分组")
        // ⌘N, ⌘⇧N and ⌘K, once the list is shown.
        .onChange(of: model.hostListRequest, initial: true) { _, request in
            guard let request else {
                return
            }
            model.hostListRequest = nil
            switch request {
            case .newHost:
                editingHost = .new(group: nil)
            case .newGroup:
                editingGroup = .new(parent: nil)
            case .search:
                searchShown = true
            }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView {
                    Label("还没有主机", systemImage: "server.rack")
                } description: {
                    Text("新建一台主机，或在设置里加入电脑上的云同步。")
                } actions: {
                    Button("新建主机") {
                        editingHost = .new(group: nil)
                    }
                }
            } else if searching && tree.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("主机")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !isEmpty {
                    Button(
                        editMode.isEditing
                            ? String(localized: "完成") : String(localized: "排序")) {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建主机…", systemImage: "server.rack") {
                        editingHost = .new(group: nil)
                    }
                    Button("新建分组…", systemImage: "folder.badge.plus") {
                        editingGroup = .new(parent: nil)
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingHost) { subject in
            HostEditor(subject: subject)
        }
        .sheet(item: $editingGroup) { subject in
            GroupEditor(subject: subject)
        }
        .confirmationDialog(
            deleting.map { String(localized: "删除“\($0.name)”？") } ?? "",
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { deletion in
            Button("删除", role: .destructive) {
                delete(deletion)
            }
        } message: { deletion in
            Text(deletion.message)
        }
        .alert(
            "出错了", isPresented: Binding(
                get: { failure != nil || hosts.problem != nil },
                set: { if !$0 { failure = nil; hosts.problem = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? hosts.problem ?? "")
        }
    }

    private var actions: HostActions {
        HostActions(
            connect: { host in
                do {
                    try model.connect(host)
                } catch {
                    failure = Describe.store(error)
                }
            },
            edit: { editingHost = .edit($0) },
            duplicate: { host in
                do {
                    try model.hosts.duplicate(host)
                } catch {
                    failure = Describe.store(error)
                }
            },
            delete: { node in
                let dependents = model.hosts.dependents(of: node)
                switch node {
                case .host(let id):
                    deleting = model.hosts.host(id).map { .host($0, dependents) }
                case .group(let id):
                    deleting = model.hosts.group(id).map { .group($0, dependents) }
                }
            },
            newHost: { editingHost = .new(group: $0) },
            newGroup: { editingGroup = .new(parent: $0) },
            editGroup: { editingGroup = .edit($0) }
        )
    }

    private func delete(_ deletion: Deletion) {
        do {
            switch deletion {
            case .host(let host, _):
                try model.hosts.delete(host)
            case .group(let group, _):
                try model.hosts.delete(group)
            }
        } catch {
            failure = Describe.store(error)
        }
    }
}

/// What the rows ask the list to do.
private struct HostActions {
    var connect: (Host) -> Void
    var edit: (Host) -> Void
    var duplicate: (Host) -> Void
    /// Asks first.
    var delete: (TreeNode) -> Void
    /// A new host, in the group given.
    var newHost: (UInt64?) -> Void
    /// A new group, in the group given.
    var newGroup: (UInt64?) -> Void
    var editGroup: (HostGroup) -> Void
}

/// What is about to be deleted, and what goes with it.
private enum Deletion {
    case host(Host, Dependents)
    case group(HostGroup, Dependents)

    var name: String {
        switch self {
        case .host(let host, _): host.title
        case .group(let group, _): group.name
        }
    }

    var message: String {
        let goes: String? = switch self {
        case .host(_, let dependents): Describe.deleting(host: dependents)
        case .group(_, let dependents): Describe.deleting(group: dependents)
        }
        let open = String(localized: "已打开的终端不受影响。")
        return goes.map { "\($0)\n\(open)" } ?? open
    }
}

/// A level of the tree: its groups, each opening onto the level in it, then
/// its hosts. Dragging orders groups among groups and hosts among hosts, as
/// the core keeps them.
private struct HostLevel: View {
    let tree: HostTree
    /// Every group is open, and nothing moves.
    let searching: Bool
    let actions: HostActions
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(tree.branches) { branch in
            DisclosureGroup(isExpanded: expanded(branch.group)) {
                HostLevel(tree: branch.tree, searching: searching, actions: actions)
            } label: {
                GroupRow(group: branch.group, actions: actions)
            }
        }
        .onMove { from, to in
            move(from, to, among: tree.branches.map { .group(id: $0.group.id) })
        }
        .moveDisabled(searching)
        ForEach(tree.hosts, id: \.id) { host in
            HostButton(host: host, actions: actions)
        }
        .onMove { from, to in
            move(from, to, among: tree.hosts.map { .host(id: $0.id) })
        }
        .moveDisabled(searching)
    }

    /// Open or not as the core keeps it, so the desktop's choice comes along
    /// with sync.
    private func expanded(_ group: HostGroup) -> Binding<Bool> {
        Binding(
            get: { searching || group.expanded },
            set: { expanded in
                if !searching {
                    model.hosts.setExpanded(group, expanded)
                }
            })
    }

    private func move(_ from: IndexSet, _ to: Int, among siblings: [TreeNode]) {
        guard let index = from.first,
            let drop = HostTree.drop(moving: index, to: to, among: siblings)
        else {
            return
        }
        model.hosts.move(siblings[index], to: drop)
    }
}

private struct GroupRow: View {
    let group: HostGroup
    let actions: HostActions

    var body: some View {
        Label(group.name, systemImage: "folder")
            .lineLimit(1)
            .swipeActions {
                Button("删除", role: .destructive) {
                    actions.delete(.group(id: group.id))
                }
                Button("编辑") {
                    actions.editGroup(group)
                }
                .tint(.blue)
            }
            .contextMenu {
                Button("新建主机…", systemImage: "server.rack") {
                    actions.newHost(group.id)
                }
                Button("新建子分组…", systemImage: "folder.badge.plus") {
                    actions.newGroup(group.id)
                }
                Button("重命名分组…", systemImage: "pencil") {
                    actions.editGroup(group)
                }
                Divider()
                Button("删除分组", systemImage: "trash", role: .destructive) {
                    actions.delete(.group(id: group.id))
                }
            }
    }
}

/// A host's row: tap to connect, except while dragging.
private struct HostButton: View {
    let host: Host
    let actions: HostActions
    @Environment(\.editMode) private var editMode

    var body: some View {
        Button {
            if editMode?.wrappedValue.isEditing != true {
                actions.connect(host)
            }
        } label: {
            HostRow(host: host)
        }
        .tint(.primary)
        .swipeActions {
            Button("删除", role: .destructive) {
                actions.delete(.host(id: host.id))
            }
            Button("编辑") {
                actions.edit(host)
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button("创建副本") {
                actions.duplicate(host)
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button("连接", systemImage: "terminal") {
                actions.connect(host)
            }
            Button("编辑主机…", systemImage: "pencil") {
                actions.edit(host)
            }
            Button("创建副本", systemImage: "plus.square.on.square") {
                actions.duplicate(host)
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                actions.delete(.host(id: host.id))
            }
        }
    }
}

/// A host in the list: its mark, name and where it is.
struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 12) {
            HostMark(host: host)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.title)
                    .font(.body)
                    .lineLimit(1)
                Text(host.isSsh ? host.subtitle : "Telnet · \(host.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
