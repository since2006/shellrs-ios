import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

@MainActor
struct CredentialTests {
    let test: TestCore
    let hosts: HostsModel

    init() throws {
        test = try TestCore()
        hosts = HostsModel(store: test.core.store())
    }

    @Test func aPasswordIsKeptInTheKeychainOnlyAndItsHostsLogInAloneOnceItGoes() async throws {
        let password = "s3cret-\(UUID().uuidString)"
        let id = try await hosts.saveCredential(
            id: nil, draft: CredentialDraft(name: "生产 root", kind: .password, user: "root"),
            key: .keep(passphrase: .keep), password: .set(value: password))
        #expect(await hosts.savedSecret(.credentialPassword(credential: id)) == password)
        let stored = try test.storedBytes()
        #expect(stored.range(of: Data(password.utf8)) == nil, "a password in the data folder")

        let host = try await hosts.save(
            id: nil, draft: draft(user: "", auth: .credential(id: id)), password: .keep)
        #expect(hosts.host(host)?.user == "root")
        let credential = try #require(hosts.credential(id))
        #expect(hosts.hostsUsing(credential) == [host])
        #expect(Describe.deleting(credential, usedBy: 1) != nil)

        try hosts.delete(credential)
        #expect(hosts.credentials.isEmpty)
        #expect(hosts.host(host)?.auth == .password)
        #expect(hosts.host(host)?.user == "root")
    }

    @Test func aPastedKeyIsKeptWithItsPublicKey() async throws {
        let info = try checkPrivateKey(text: testKey)
        #expect(!info.encrypted)
        #expect(info.publicKey?.hasPrefix(testPublicKey) == true)

        let id = try await hosts.saveCredential(
            id: nil, draft: CredentialDraft(name: "key", kind: .key, user: "deploy"),
            key: .text(text: testKey, passphrase: nil), password: .keep)
        #expect(hosts.credential(id)?.summary == "deploy · \(CredentialKind.key.label)")
        #expect(await test.core.store().publicKey(credential: id)?.hasPrefix(testPublicKey) == true)
    }

    @Test func aPublicKeyIsNoPrivateKey() async throws {
        #expect(throws: KeyProblem.PublicKey) {
            try checkPrivateKey(text: testPublicKey)
        }
        await #expect {
            try await hosts.saveCredential(
                id: nil, draft: CredentialDraft(name: "key", kind: .key, user: ""),
                key: .text(text: testPublicKey, passphrase: nil), password: .keep)
        } throws: { error in
            Describe.store(error) == Describe.key(.PublicKey)
        }
        #expect(hosts.credentials.isEmpty)
    }

    @Test func aGeneratedKeyIsEncryptedWithAPassphraseKeptInTheKeychainOnly() async throws {
        let passphrase = "phrase-\(UUID().uuidString)"
        let key = try await test.core.store().generateKey(algorithm: .ed25519)
        let line = key.publicKey(comment: "phone")
        #expect(line.hasPrefix("ssh-ed25519 ") && line.hasSuffix(" phone"))

        let id = try await hosts.saveCredential(
            id: nil, draft: CredentialDraft(name: "phone", kind: .key, user: ""),
            key: .generated(key: key, passphrase: passphrase), password: .keep)
        #expect(await hosts.savedSecret(.passphrase(credential: id)) == passphrase)
        let stored = try test.storedBytes()
        #expect(stored.range(of: Data(passphrase.utf8)) == nil, "a passphrase in the data folder")

        // Kept as it is, its passphrase changed.
        try await hosts.saveCredential(
            id: id, draft: CredentialDraft(name: "phone", kind: .key, user: ""),
            key: .keep(passphrase: .clear), password: .keep)
        #expect(await hosts.savedSecret(.passphrase(credential: id)) == nil)
    }
}
