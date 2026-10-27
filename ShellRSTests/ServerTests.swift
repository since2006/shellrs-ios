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
}

/// The server the environment names.
enum TestServer {
    static var address: (address: String, port: UInt16)? {
        guard let value = ProcessInfo.processInfo.environment["SHELLRS_TEST_SSH"],
            let colon = value.lastIndex(of: ":"),
            let port = UInt16(value[value.index(after: colon)...])
        else {
            return nil
        }
        return (String(value[..<colon]), port)
    }

    static var user: String {
        ProcessInfo.processInfo.environment["SHELLRS_TEST_SSH_USER"] ?? "root"
    }

    static var password: String {
        ProcessInfo.processInfo.environment["SHELLRS_TEST_SSH_PASSWORD"] ?? ""
    }
}
