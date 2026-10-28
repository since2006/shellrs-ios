import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

@MainActor
struct HostsModelTests {
    let test: TestCore
    let hosts: HostsModel

    init() throws {
        test = try TestCore()
        hosts = HostsModel(store: test.core.store())
    }

    @Test func savesAHostWithItsPasswordInTheKeychainOnly() async throws {
        let password = "s3cret-\(UUID().uuidString)"
        let id = try await hosts.save(
            id: nil, draft: draft(name: "Web", address: "web.example.com"),
            password: .set(value: password))

        #expect(hosts.hosts.map(\.id) == [id])
        #expect(hosts.hosts.first?.title == "Web")
        #expect(test.keychain.all.values.contains(password))
        #expect(await hosts.savedSecret(.hostPassword(host: id)) == password)
        let stored = try test.storedBytes()
        #expect(stored.range(of: Data(password.utf8)) == nil, "a password in the data folder")
    }

    @Test func editsAndDeletes() async throws {
        let id = try await hosts.save(
            id: nil, draft: draft(address: "db.example.com"), password: .set(value: "pw"))
        #expect(hosts.hosts.first?.title == "db.example.com")

        try await hosts.save(
            id: id, draft: draft(name: "DB", address: "db.example.com", port: 2222),
            password: .clear)
        #expect(hosts.hosts.first?.title == "DB")
        #expect(hosts.hosts.first?.subtitle == "root@db.example.com:2222")
        #expect(await hosts.savedSecret(.hostPassword(host: id)) == nil)

        try hosts.delete(hosts.hosts[0])
        #expect(hosts.hosts.isEmpty)
    }

    @Test func aHostWithoutAnAddressIsNotSaved() async throws {
        await #expect {
            try await hosts.save(id: nil, draft: draft(address: " "), password: .keep)
        } throws: { error in
            Describe.store(error) == Describe.host(.address)
        }
        #expect(hosts.hosts.isEmpty)
    }

    @Test func aCopyIsNamedAsTheDesktopNamesIt() async throws {
        let id = try await hosts.save(id: nil, draft: draft(name: "web"), password: .keep)
        let copy = try hosts.duplicate(try #require(hosts.host(id)))
        #expect(hosts.hosts.map(\.id) == [id, copy])
        #expect(hosts.host(copy)?.name == String(localized: "\("web") 副本"))
    }

    @Test func groupsNestAndGoWithAllThatIsInThem() async throws {
        let production = try hosts.saveGroup(id: nil, draft: GroupDraft(name: "生产", parent: nil))
        let databases = try hosts.saveGroup(
            id: nil, draft: GroupDraft(name: "数据库", parent: production))
        let db = try await hosts.save(
            id: nil, draft: draft(name: "db", group: databases), password: .keep)
        // A host outside that jumps through the one inside.
        try await hosts.save(
            id: nil, draft: draft(name: "app", route: .jump(hosts: [db])), password: .keep)

        #expect(HostTree.groupOptions(hosts.groups).map(\.path) == ["生产", "生产 / 数据库"])
        // A group cannot go into a group in it.
        #expect {
            try hosts.saveGroup(id: production, draft: GroupDraft(name: "生产", parent: databases))
        } throws: { error in
            Describe.store(error) == Describe.store(StoreError.GroupIntoItself)
        }

        let dependents = hosts.dependents(of: .group(id: production))
        #expect(dependents == Dependents(hosts: 1, subgroups: 1, forwards: 0, jumpUsers: 1))
        #expect(Describe.deleting(group: dependents) != nil)
        try hosts.delete(try #require(hosts.group(production)))
        #expect(hosts.groups.isEmpty)
        #expect(hosts.hosts.map(\.name) == ["app"])
        // Its route keeps the place of the host deleted, empty.
        #expect(hosts.hosts.first?.route == .jump(hosts: [nil]))
    }

    @Test func aDragOrdersHostsAmongTheirSiblings() async throws {
        for name in ["a", "b", "c"] {
            try await hosts.save(id: nil, draft: draft(name: name), password: .keep)
        }
        let tree = HostTree(groups: hosts.groups, hosts: hosts.hosts)
        let siblings = tree.hosts.map { TreeNode.host(id: $0.id) }
        let drop = try #require(HostTree.drop(moving: 2, to: 0, among: siblings))
        #expect(hosts.move(siblings[2], to: drop))
        #expect(hosts.hosts.map(\.name) == ["c", "a", "b"])
    }

    @Test func aGroupOpensAndClosesAsTheCoreKeepsIt() throws {
        let id = try hosts.saveGroup(id: nil, draft: GroupDraft(name: "生产", parent: nil))
        let group = try #require(hosts.group(id))
        hosts.setExpanded(group, !group.expanded)
        #expect(hosts.group(id)?.expanded == !group.expanded)
        #expect(test.core.store().groups().first?.expanded == !group.expanded)
    }

    @Test func aHostCannotJumpThroughItself() async throws {
        let id = try await hosts.save(id: nil, draft: draft(name: "a"), password: .keep)
        await #expect {
            try await hosts.save(
                id: id, draft: draft(name: "a", route: .jump(hosts: [id])), password: .keep)
        } throws: { error in
            Describe.store(error) == Describe.store(StoreError.JumpThroughItself)
        }
    }

    @Test func aProxyPasswordIsKeptInTheKeychainOnly() async throws {
        let password = "proxy-\(UUID().uuidString)"
        let proxy = HostProxy(kind: .socks5, host: "127.0.0.1", port: 1080, user: "me")
        let id = try await hosts.save(
            id: nil, draft: draft(route: .proxy(proxy: proxy)), password: .keep,
            proxyPassword: .set(value: password))

        #expect(hosts.host(id)?.route == .proxy(proxy: proxy))
        #expect(await hosts.savedSecret(.proxyPassword(host: id)) == password)
        let stored = try test.storedBytes()
        #expect(stored.range(of: Data(password.utf8)) == nil, "a password in the data folder")
    }
}
