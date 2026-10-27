import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

@MainActor
struct TerminalSessionTests {
    let test: TestCore

    init() throws {
        test = try TestCore()
    }

    /// A port nothing listens on: the terminal closes and says why in the
    /// desktop's words.
    @Test func sayWhyItCouldNotConnect() async throws {
        let port = try closedPort()
        let store = test.core.store()
        let id = try await store.addHost(
            draft: draft(port: port, auth: .noPassword), password: .keep, proxyPassword: .keep)
        let host = try #require(store.host(id: id))

        let session = TerminalSession(host: host, core: test.core)
        session.start()
        try await waitUntil("the terminal closes") { session.isClosed }

        guard case .closed(let reason?) = session.state else {
            Issue.record("closed without a reason: \(session.state)")
            return
        }
        #expect(reason.contains(String(localized: "连接被拒绝，该端口上没有服务在监听")), "\(reason)")
    }

    @Test func aDeletedHostDoesNotConnect() async throws {
        let store = test.core.store()
        let id = try await store.addHost(draft: draft(), password: .keep, proxyPassword: .keep)
        let host = try #require(store.host(id: id))
        try store.deleteHost(id: id)

        let session = TerminalSession(host: host, core: test.core)
        session.start()
        #expect(session.state == .closed(Describe.store(StoreError.NotFound)))
    }
}
