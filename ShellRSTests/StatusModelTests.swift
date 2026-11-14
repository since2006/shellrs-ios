import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// Which hosts 状态 shows, and how its monitors and the host form's
/// 测试连接 say what went wrong.
@MainActor
struct StatusModelTests {
    let test: TestCore
    let defaults: UserDefaults
    let hosts: HostsModel

    init() throws {
        test = try TestCore()
        defaults = try #require(UserDefaults(suiteName: "StatusModelTests.\(UUID().uuidString)"))
        hosts = HostsModel(store: test.core.store())
    }

    private func add(_ name: String, port: UInt16 = 22, telnet: Bool = false) async throws -> Host {
        var draft = draft(name: name, port: port, auth: .noPassword)
        if telnet {
            draft.protocol = .telnet(userPrompt: "", passwordPrompt: "")
        }
        let id = try await hosts.save(id: nil, draft: draft, password: .keep)
        return try #require(hosts.host(id))
    }

    @Test func theChoiceIsThisDevicesKeptByPublicId() async throws {
        let web = try await add("web")
        let db = try await add("db")
        let status = StatusModel(core: test.core, hosts: hosts, defaults: defaults)
        #expect(status.shownHosts.isEmpty)

        status.setShown(true, for: db)
        status.setShown(true, for: web)
        // In the host list's order, not the order chosen.
        #expect(status.shownHosts.map(\.name) == ["web", "db"])
        #expect(defaults.stringArray(forKey: StatusModel.shownKey)?.sorted() == [db.publicId, web.publicId].sorted())

        // Read back at the next launch.
        let again = StatusModel(core: test.core, hosts: hosts, defaults: defaults)
        #expect(again.isShown(web) && again.isShown(db))
        again.setShown(false, for: web)
        #expect(again.shownHosts.map(\.name) == ["db"])

        // A host deleted is shown no more.
        try hosts.delete(db)
        #expect(again.shownHosts.isEmpty)
    }

    @Test func onlySshHostsAreShown() async throws {
        let switchHost = try await add("switch", port: 23, telnet: true)
        let status = StatusModel(core: test.core, hosts: hosts, defaults: defaults)
        #expect(status.candidates.isEmpty)
        status.setShown(true, for: switchHost)
        #expect(status.shownHosts.isEmpty)
    }

    @Test func theAppStartsOnStatusOnceItHasHosts() async throws {
        let web = try await add("web")
        #expect(AppModel(core: test.core, deviceName: "iPhone", defaults: defaults).tab == .hosts)
        StatusModel(core: test.core, hosts: hosts, defaults: defaults).setShown(true, for: web)
        #expect(AppModel(core: test.core, deviceName: "iPhone", defaults: defaults).tab == .status)
    }

    /// A port nothing listens on: the monitor says why in the desktop's
    /// words, and only while a page of 状态 is shown does it try.
    @Test func aMonitorSaysWhyItCouldNotConnect() async throws {
        let host = try await add("web", port: try closedPort())
        let status = StatusModel(core: test.core, hosts: hosts, defaults: defaults)
        status.setShown(true, for: host)
        let monitor = status.monitor(for: host)
        #expect(monitor.state == .idle, "no page shown")

        status.pageAppeared()
        try await waitUntil("the connection fails") {
            if case .failed = monitor.state { true } else { false }
        }
        guard case .failed(let reason) = monitor.state else { return }
        #expect(reason.contains(String(localized: "连接被拒绝，该端口上没有服务在监听")), "\(reason)")
        // Looking at it is not connecting to it.
        #expect(hosts.recent.isEmpty)

        status.wentToBackground()
        status.cameForward()
        status.pageDisappeared()
    }

    @Test func aTestSaysWhyItCouldNotConnectAndSavesNothing() async throws {
        let port = try closedPort()
        let connectionTest = ConnectionTest()
        connectionTest.run(
            core: test.core, editing: nil, draft: draft(port: port), password: "secret")
        #expect(connectionTest.running)
        try await waitUntil("the test fails") { !connectionTest.running }
        guard case .failed(let reason) = connectionTest.outcome else {
            Issue.record("\(String(describing: connectionTest.outcome))")
            return
        }
        #expect(reason.contains(String(localized: "连接被拒绝，该端口上没有服务在监听")), "\(reason)")
        #expect(test.core.store().hosts().isEmpty)
        #expect(test.keychain.all.isEmpty, "the typed password stays in memory")

        // Checked as saving would check it.
        connectionTest.run(core: test.core, editing: nil, draft: draft(address: " "), password: nil)
        #expect(!connectionTest.running)
        #expect(connectionTest.outcome == .failed(Describe.store(StoreError.Host(problem: .address))))
        connectionTest.reset()
        #expect(connectionTest.outcome == nil)
    }
}
