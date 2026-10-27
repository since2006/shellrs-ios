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
        #expect(await hosts.savedPassword(of: hosts.hosts[0]) == password)
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
        #expect(await hosts.savedPassword(of: hosts.hosts[0]) == nil)

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
}
