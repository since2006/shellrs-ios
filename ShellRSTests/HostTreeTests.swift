import ShellRSCore
import Testing

@testable import ShellRS

/// The tree as the desktop builds it.
struct HostTreeTests {
    let groups = [
        group(1, "生产"),
        group(2, "数据库", parent: 1),
        group(3, "测试"),
    ]
    let hosts = [
        host(1, "web", group: 1),
        host(2, "db", group: 2, address: "10.0.0.2"),
        host(3, "laptop"),
        host(4, "ci", group: 3, user: "deploy"),
    ]

    @Test func subgroupsComeFirstThenHosts() {
        let tree = HostTree(groups: groups, hosts: hosts)
        #expect(
            outline(tree) == [
                "生产", "  数据库", "    db", "  web",
                "测试", "  ci",
                "laptop",
            ])
    }

    @Test func aQueryKeepsWhatItFindsAndTheGroupsAboveIt() {
        // A host deep in the tree, by name, address or user, ignoring case.
        #expect(outline(HostTree(groups: groups, hosts: hosts, query: " DB ")) == ["生产", "  数据库", "    db"])
        #expect(outline(HostTree(groups: groups, hosts: hosts, query: "10.0.0.2")) == ["生产", "  数据库", "    db"])
        #expect(outline(HostTree(groups: groups, hosts: hosts, query: "deploy")) == ["测试", "  ci"])
        // A group, with all that is in it.
        #expect(outline(HostTree(groups: groups, hosts: hosts, query: "生产")) == ["生产", "  数据库", "    db", "  web"])
        // Only a host at the top: no group stays.
        #expect(outline(HostTree(groups: groups, hosts: hosts, query: "lap")) == ["laptop"])
        #expect(HostTree(groups: groups, hosts: hosts, query: "nothing").isEmpty)
    }

    @Test func aDragLandsBeforeTheRowDroppedOnOrAfterTheLast() {
        let siblings: [TreeNode] = [.host(id: 1), .host(id: 2), .host(id: 3)]
        // Dropped where it was.
        #expect(HostTree.drop(moving: 0, to: 0, among: siblings) == nil)
        #expect(HostTree.drop(moving: 0, to: 1, among: siblings) == nil)
        #expect(HostTree.drop(moving: 2, to: 3, among: siblings) == nil)
        #expect(HostTree.drop(moving: 0, to: 2, among: siblings) == .before(node: .host(id: 3)))
        #expect(HostTree.drop(moving: 2, to: 0, among: siblings) == .before(node: .host(id: 1)))
        #expect(HostTree.drop(moving: 0, to: 3, among: siblings) == .after(node: .host(id: 3)))
    }

    @Test func groupPickersListPathsAndLeaveAGroupOutOfItself() {
        #expect(HostTree.groupOptions(groups).map(\.path) == ["生产", "生产 / 数据库", "测试"])
        #expect(HostTree.groupOptions(groups, excluding: 1).map(\.path) == ["测试"])
    }
}

/// The tree as text, a level indented two spaces.
private func outline(_ tree: HostTree, depth: Int = 0) -> [String] {
    let indent = String(repeating: "  ", count: depth)
    return tree.branches.flatMap { [indent + $0.group.name] + outline($0.tree, depth: depth + 1) }
        + tree.hosts.map { indent + $0.name }
}

private func group(_ id: UInt64, _ name: String, parent: UInt64? = nil) -> HostGroup {
    HostGroup(id: id, name: name, parent: parent, expanded: false)
}

private func host(
    _ id: UInt64, _ name: String, group: UInt64? = nil, address: String = "10.0.0.1",
    user: String = "root"
) -> Host {
    Host(
        id: id, publicId: "host-\(id)", name: name, protocol: .ssh, address: address, port: 22,
        user: user, auth: .password, route: .direct, group: group, notes: "", os: nil,
        markColor: 0)
}
