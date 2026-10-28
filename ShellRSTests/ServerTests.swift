import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// Against a real SSH server, only when one is named: for example the
/// openssh-server the README starts in Docker. `xcodebuild test` passes
/// `TEST_RUNNER_`-prefixed variables to the tests without the prefix.
@MainActor
@Suite(.enabled(if: TestServer.address != nil, "set SHELLRS_TEST_SSH to host:port"))
struct ServerTests {
    let test: TestCore

    init() throws {
        test = try TestCore()
    }

    /// Trust the key, type the password, run a command and see what it
    /// printed on SwiftTerm's screen; then disconnect and reconnect, with the
    /// key now trusted.
    @Test func logsInAndRunsACommand() async throws {
        let server = try #require(TestServer.address)
        let store = test.core.store()
        let id = try await store.addHost(
            draft: draft(address: server.address, port: server.port, user: TestServer.user),
            password: .keep, proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()

        try await waitUntil("the server's key is asked about") { session.prompt != nil }
        guard case .unknownHost = session.prompt?.kind else {
            Issue.record("asked \(String(describing: session.prompt))")
            return
        }
        session.answer(.trustAndSave)

        try await waitUntil("the password is asked for") { session.prompt != nil }
        guard case .password(savedRejected: false) = session.prompt?.kind else {
            Issue.record("asked \(String(describing: session.prompt))")
            return
        }
        session.answer(.answers(answers: [TestServer.password]))

        try await waitUntil("the shell starts") { session.state == .connected }
        session.surface.onInput(Data("echo shellrs-$((6*7))\r".utf8))
        try await waitUntil("the command's output shows") {
            session.surface.text.contains("shellrs-42")
        }

        session.disconnect()
        #expect(session.isClosed)
        // Enter on a closed terminal connects again, as on the desktop.
        session.surface.onInput(Data([0x0d]))
        try await waitUntil("the password is asked for again") { session.prompt != nil }
        guard case .password = session.prompt?.kind else {
            Issue.record("asked \(String(describing: session.prompt))")
            return
        }
        session.answer(.cancel)
        try await waitUntil("the cancelled login ends") { session.isClosed }
    }

    /// A key credential logs in with nothing asked but the server's key:
    /// the server trusts `testKey`, as the README's does.
    @Test func logsInWithAKeyCredential() async throws {
        let server = try #require(TestServer.address)
        let store = test.core.store()
        let credential = try await store.addCredential(
            draft: CredentialDraft(name: "test key", kind: .key, user: TestServer.user),
            key: .text(text: testKey, passphrase: nil), password: .keep)
        let id = try await store.addHost(
            draft: draft(
                address: server.address, port: server.port, user: "",
                auth: .credential(id: credential)),
            password: .keep, proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()

        #expect(try await trustEachKey(session) == [nil])
        try await expectAShell(session)
    }

    /// Through the server to a host only it reaches: the jump host's key is
    /// asked about first, and the saved passwords log both in.
    @Test(.enabled(if: TestServer.target != nil, "set SHELLRS_TEST_SSH_TARGET"))
    func goesThroughAJumpHost() async throws {
        let server = try #require(TestServer.address)
        let target = try #require(TestServer.target)
        let store = test.core.store()
        let jump = try await store.addHost(
            draft: draft(
                name: "jump", address: server.address, port: server.port, user: TestServer.user),
            password: .set(value: TestServer.password), proxyPassword: .keep)
        let id = try await store.addHost(
            draft: draft(
                name: "target", address: target.address, port: target.port,
                user: TestServer.user, route: .jump(hosts: [jump])),
            password: .set(value: TestServer.password), proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()

        #expect(try await trustEachKey(session) == ["jump", nil])
        try await expectAShell(session)
    }

    /// Through a SOCKS5 proxy, which resolves the host's address itself.
    @Test(.enabled(
        if: TestServer.target != nil && TestServer.socks != nil,
        "set SHELLRS_TEST_SSH_TARGET and SHELLRS_TEST_SOCKS"))
    func goesThroughAProxy() async throws {
        let target = try #require(TestServer.target)
        let socks = try #require(TestServer.socks)
        let store = test.core.store()
        let proxy = HostProxy(kind: .socks5, host: socks.address, port: socks.port, user: nil)
        let id = try await store.addHost(
            draft: draft(
                address: target.address, port: target.port, user: TestServer.user,
                route: .proxy(proxy: proxy)),
            password: .set(value: TestServer.password), proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()

        #expect(try await trustEachKey(session) == [nil])
        try await expectAShell(session)
    }

    /// On the terminal's connection: browse, upload, download, a conflict,
    /// a preview, rename and delete; the files go with the connection and
    /// come back with it.
    @Test func browsesAndTransfersFiles() async throws {
        let server = try #require(TestServer.address)
        let store = test.core.store()
        let id = try await store.addHost(
            draft: draft(address: server.address, port: server.port, user: TestServer.user),
            password: .set(value: TestServer.password), proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()
        #expect(try await trustEachKey(session) == [nil])
        try await waitUntil("the shell starts") { session.state == .connected }

        let downloads = test.folder.appending(path: "Downloads", directoryHint: .isDirectory)
        let files = session.openFiles(downloadsFolder: downloads)
        files.open()
        try await waitUntil("SFTP starts") { files.state == .connected }
        let home = files.home
        #expect(files.path == RemotePath.ancestors(of: home))

        let name = "shellrs-files-\(UUID().uuidString.prefix(8))"
        let folder = RemotePath.join(home, name)
        try await files.createFolder(name, in: home)
        #expect(try await files.list(home).contains { $0.name == name && $0.isFolder })

        // Large enough to go up and come down resumably.
        let bytes = Data((0..<(3 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let source = test.folder.appending(path: "big.bin")
        try bytes.write(to: source)
        await files.upload([source], to: folder)
        try await waitUntil("the upload is done", timeout: .seconds(30)) {
            files.queue.entries.last?.state == .done
        }
        let uploaded = try await files.list(folder)
        #expect(uploaded.map(\.name) == ["big.bin"])
        #expect(uploaded.first?.size == UInt64(bytes.count))
        #expect(files.revision(of: folder) > 0)

        let remote = RemotePath.join(folder, "big.bin")
        files.download([remote])
        try await waitUntil("the download is done", timeout: .seconds(30)) {
            files.queue.entries.last?.state == .done
        }
        #expect(try Data(contentsOf: downloads.appending(path: "big.bin")) == bytes)
        #expect(files.downloads == 1)

        // Downloading it again asks before replacing what came down.
        files.download([remote])
        try await waitUntil("asked about the copy there") { files.question != nil }
        #expect(files.question?.kind == .conflict)
        files.answer(.skip)
        try await waitUntil("the skipped download ends") {
            files.queue.entries.last?.state == .done
        }
        #expect(files.queue.entries.last?.progress?.skipped == 1)

        files.preview(remote)
        try await waitUntil("the preview comes down", timeout: .seconds(30)) {
            files.preview != nil
        }
        #expect(try Data(contentsOf: try #require(files.preview)) == bytes)

        try await files.rename("big.bin", to: "renamed.bin", in: folder)
        #expect(try await files.list(folder).map(\.name) == ["renamed.bin"])
        try await files.delete([name], in: home)
        let after = try await files.list(home)
        #expect(!after.contains { $0.name == name })

        session.disconnect()
        try await waitUntil("SFTP goes with the connection") {
            if case .disconnected = files.state { true } else { false }
        }
        session.start()
        try await waitUntil("the shell starts again") { session.state == .connected }
        try await waitUntil("SFTP opens again") { files.state == .connected }
        files.end()
        session.disconnect()
    }

    /// A transfer stopped halfway goes on where it was; one the terminal's
    /// disconnecting cut short goes on by itself once the terminal is back,
    /// without asking whether to resume.
    @Test func stopsAndResumesTransfers() async throws {
        let server = try #require(TestServer.address)
        let store = test.core.store()
        let id = try await store.addHost(
            draft: draft(address: server.address, port: server.port, user: TestServer.user),
            password: .set(value: TestServer.password), proxyPassword: .keep)
        let session = TerminalSession(host: try #require(store.host(id: id)), core: test.core)
        session.start()
        #expect(try await trustEachKey(session) == [nil])
        try await waitUntil("the shell starts") { session.state == .connected }
        let downloads = test.folder.appending(path: "Downloads", directoryHint: .isDirectory)
        let files = session.openFiles(downloadsFolder: downloads)
        files.open()
        try await waitUntil("SFTP starts") { files.state == .connected }

        // Large enough to stop halfway; a pattern that shows a misplaced block.
        var bytes = Data()
        let block = Data((0..<4093).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        while bytes.count < 96 << 20 {
            bytes.append(block)
        }
        let source = test.folder.appending(path: "large.bin")
        try bytes.write(to: source)
        let name = "shellrs-resume-\(UUID().uuidString.prefix(8))"
        let folder = RemotePath.join(files.home, name)
        try await files.createFolder(name, in: files.home)

        func halfway() async throws {
            try await waitUntil("the upload is under way", timeout: .seconds(30)) {
                (files.queue.head?.progress?.completedBytes ?? 0) > 0
            }
            #expect(files.queue.head?.state == .active)
        }
        func uploadedSize() async throws -> UInt64? {
            try await files.list(folder).first { $0.name == "large.bin" }?.size
        }

        await files.upload([source], to: folder)
        try await halfway()
        files.cancel()
        try await waitUntil("the upload stops") { files.queue.head?.state == .stopped }
        files.resume()
        try await waitUntil("the upload is done", timeout: .seconds(60)) {
            files.queue.entries.last?.state == .done
        }
        #expect(try await uploadedSize() == UInt64(bytes.count))

        try await files.delete(["large.bin"], in: folder)
        await files.upload([source], to: folder)
        try await halfway()
        session.disconnect()
        try await waitUntil("the upload stops with the terminal") {
            files.queue.head?.state == .stopped
        }
        if case .disconnected = files.state {} else {
            Issue.record("still \(files.state)")
        }
        session.start()
        try await waitUntil("the upload is done", timeout: .seconds(60)) {
            files.queue.entries.last?.state == .done
        }
        #expect(files.question == nil)
        #expect(files.queue.entries.last?.progress?.failed == 0)
        #expect(try await uploadedSize() == UInt64(bytes.count))

        // What went up is what was sent: back down, byte for byte.
        files.download([RemotePath.join(folder, "large.bin")])
        try await waitUntil("the download is done", timeout: .seconds(60)) {
            files.queue.entries.last?.state == .done
        }
        #expect(try Data(contentsOf: downloads.appending(path: "large.bin")) == bytes)
        try await files.delete([name], in: files.home)
        files.end()
        session.disconnect()
    }

    /// Trusts each key the login asks about until it ends asking; whose
    /// each was: a jump host's name, or `nil` for the host itself.
    private func trustEachKey(_ session: TerminalSession) async throws -> [String?] {
        var asked: [String?] = []
        while true {
            try await waitUntil("a key asked about, or the login done") {
                session.prompt != nil || session.state != .connecting
            }
            guard let prompt = session.prompt else {
                return asked
            }
            guard case .unknownHost = prompt.kind else {
                Issue.record("asked \(prompt)")
                return asked
            }
            asked.append(prompt.jumpHost)
            session.answer(.trustAndSave)
        }
    }

    /// The shell starts, runs a command and shows what it printed.
    private func expectAShell(_ session: TerminalSession) async throws {
        try await waitUntil("the login ends") { session.state != .connecting }
        guard session.state == .connected else {
            Issue.record("not connected: \(session.state)")
            return
        }
        session.surface.onInput(Data("echo shellrs-$((6*7))\r".utf8))
        try await waitUntil("the command's output shows") {
            session.surface.text.contains("shellrs-42")
        }
        session.disconnect()
    }
}

/// The servers the environment names.
enum TestServer {
    static var address: (address: String, port: UInt16)? {
        endpoint("SHELLRS_TEST_SSH")
    }

    /// A server only `address` reaches, logging in as it does.
    static var target: (address: String, port: UInt16)? {
        endpoint("SHELLRS_TEST_SSH_TARGET")
    }

    /// A SOCKS5 proxy that reaches `target`.
    static var socks: (address: String, port: UInt16)? {
        endpoint("SHELLRS_TEST_SOCKS")
    }

    static var user: String {
        ProcessInfo.processInfo.environment["SHELLRS_TEST_SSH_USER"] ?? "root"
    }

    static var password: String {
        ProcessInfo.processInfo.environment["SHELLRS_TEST_SSH_PASSWORD"] ?? ""
    }

    /// `host:port` from the variable `name`.
    private static func endpoint(_ name: String) -> (address: String, port: UInt16)? {
        guard let value = ProcessInfo.processInfo.environment[name],
            let colon = value.lastIndex(of: ":"),
            let port = UInt16(value[value.index(after: colon)...])
        else {
            return nil
        }
        return (String(value[..<colon]), port)
    }
}
