import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// The real keychain, under a service of the test's own that it deletes.
struct AppKeychainTests {
    let keychain = AppKeychain(service: "com.shellrs.ios.tests.\(UUID().uuidString)")

    @Test func keepsChangesAndDeletes() throws {
        let account = "password:root@example.com:22"
        #expect(try keychain.get(account: account) == nil)

        try keychain.set(account: account, value: "first")
        #expect(try keychain.get(account: account) == "first")

        try keychain.set(account: account, value: "第二个")
        #expect(try keychain.get(account: account) == "第二个")

        try keychain.delete(account: account)
        #expect(try keychain.get(account: account) == nil)
        // Deleting what is not there is no failure.
        try keychain.delete(account: account)
    }

    @Test func keepsAccountsApart() throws {
        defer {
            try? keychain.delete(account: "a")
            try? keychain.delete(account: "b")
        }
        try keychain.set(account: "a", value: "1")
        try keychain.set(account: "b", value: "2")
        #expect(try keychain.get(account: "a") == "1")
        #expect(try keychain.get(account: "b") == "2")
        #expect(try AppKeychain(service: "com.shellrs.ios.tests.other").get(account: "a") == nil)
    }
}
