import Darwin
import Foundation
import ShellRSCore
import Testing

/// A keychain in memory: the tests never touch the device's.
final class MemoryKeychain: Keychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    var all: [String: String] {
        lock.withLock { items }
    }

    func available() -> Bool {
        true
    }

    func get(account: String) throws -> String? {
        lock.withLock { items[account] }
    }

    func set(account: String, value: String) throws {
        lock.withLock { items[account] = value }
    }

    func delete(account: String) throws {
        _ = lock.withLock { items.removeValue(forKey: account) }
    }
}

/// A core on a data folder of its own, deleted when the test ends.
final class TestCore {
    let folder: URL
    let keychain = MemoryKeychain()
    let core: Core

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "shellrs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        core = try Core(
            config: CoreConfig(
                dataDir: folder.path, deviceName: "Test", platform: "ios", appVersion: "0"),
            keychain: keychain)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Every byte the core wrote into its data folder.
    func storedBytes() throws -> Data {
        var bytes = Data()
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            if let data = try? Data(contentsOf: file) {
                bytes.append(data)
            }
        }
        return bytes
    }
}

func draft(
    name: String = "", address: String = "127.0.0.1", port: UInt16 = 22,
    user: String = "root", auth: HostAuth = .password, route: HostRoute = .direct,
    group: UInt64? = nil
) -> HostDraft {
    HostDraft(
        name: name, protocol: .ssh, address: address, port: port, user: user, auth: auth,
        route: route, group: group, notes: "")
}

/// An Ed25519 key made for the tests, unencrypted; nothing trusts it.
let testKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBbdUTH3lRjzsMSojgUOVzyvrNtHIbu2dktXOz49wfBdQAAAJA/QxkjP0MZ
    IwAAAAtzc2gtZWQyNTUxOQAAACBbdUTH3lRjzsMSojgUOVzyvrNtHIbu2dktXOz49wfBdQ
    AAAEATh0jt90VMd6hiDRFt/3vRa6hhVD9De53qQMFAUisgiVt1RMfeVGPOwxKiOBQ5XPK+
    s20chu7Z2S1c7Pj3B8F1AAAADHNoZWxscnMtdGVzdAE=
    -----END OPENSSH PRIVATE KEY-----

    """

/// `testKey`'s public key, without its comment.
let testPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFt1RMfeVGPOwxKiOBQ5XPK+s20chu7Z2S1c7Pj3B8F1"

/// A port on this computer nothing listens on.
func closedPort() throws -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    try #require(fd >= 0)
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
        }
    }
    try #require(bound)
    return UInt16(bigEndian: address.sin_port)
}

/// Waits for `condition`, checking it on the main actor.
@MainActor
func waitUntil(
    _ what: Comment, timeout: Duration = .seconds(15), _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting: \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
