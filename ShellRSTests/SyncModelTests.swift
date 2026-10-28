import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// A device in the tests: a core of its own, its hosts and its sync,
/// told about the store's changes as the app tells it.
@MainActor
final class TestDevice {
    let test: TestCore
    let hosts: HostsModel
    let sync: SyncModel

    init(_ name: String) throws {
        test = try TestCore(name: name)
        hosts = HostsModel(store: test.core.store())
        sync = SyncModel(service: test.core.sync(), deviceName: name)
        sync.editPause = .milliseconds(200)
        sync.foregroundGap = .zero
        hosts.onChange = { [sync] in
            sync.storeChanged()
        }
    }

    /// Waits for the round running, and any it asked for, to end.
    func settled() async throws {
        try await waitUntil("\(sync.deviceName) synced") {
            !sync.busy && sync.attention == nil && sync.phase.isSynced
                && !sync.service.status().hasChanges
        }
    }

    func addHost(_ name: String) async throws {
        try await hosts.save(
            id: nil, draft: draft(name: name, address: "\(name).example.com"),
            password: .set(value: "\(name)-password"))
    }
}

extension SyncModel.Phase {
    var isSynced: Bool {
        if case .synced = self {
            return true
        }
        return false
    }
}

/// Two devices syncing through a folder, as two phones would through a
/// server: the core's folder storage keeps the network out of the tests.
@MainActor
struct SyncModelTests {
    let one: TestDevice
    let two: TestDevice
    let location: SyncLocation
    let password = "correct horse battery"

    init() throws {
        one = try TestDevice("one")
        two = try TestDevice("two")
        let folder = one.test.folder.appending(path: "Sync", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        location = .folder(path: folder.path)
    }

    /// `one` sets sync up with a host, `two` joins it.
    private func setUpBoth() async throws {
        try await one.addHost("web")
        try await one.sync.create(location, login: nil, password: password)
        try await one.settled()
        #expect(try await two.sync.inspect(location, login: nil))
        try await two.sync.join(location, login: nil, password: password, fresh: true)
        try await two.settled()
    }

    @Test func whatOneDeviceSavesTheOtherGetsByItself() async throws {
        #expect(one.sync.phase == .off)
        #expect(try await !one.sync.inspect(location, login: nil))
        try await one.addHost("web")
        try await one.sync.create(location, login: nil, password: password)
        #expect(one.sync.location == location)
        try await one.settled()
        #expect(one.sync.devices.isEmpty)
        #expect(one.sync.deviceId != nil)

        await #expect {
            try await two.sync.join(
                location, login: nil, password: "wrong horse battery", fresh: true)
        } throws: { error in
            Describe.sync(error) == String(localized: "同步密码不对。")
        }
        try await two.sync.join(location, login: nil, password: password, fresh: true)
        try await two.settled()
        #expect(two.hosts.hosts.map(\.name) == ["web"])
        #expect(two.test.keychain.all.values.contains("web-password"))
        #expect(two.sync.devices.map(\.name) == ["one"])

        // An edit goes out a moment after it is made; the other device
        // gets it when it comes to the foreground.
        try await two.addHost("db")
        try await two.settled()
        one.sync.cameForward()
        try await waitUntil("one has db") { one.hosts.hosts.count == 2 }
        try await one.settled()
        #expect(one.sync.devices.map(\.name) == ["two"])
    }

    @Test func whatOnlyTheUserCanSettleHoldsTheAutomaticRounds() async throws {
        try await setUpBoth()
        let newPassword = "battery staple horse"
        try await one.sync.changePassword(newPassword)
        try await one.settled()

        two.sync.syncNow()
        try await waitUntil("two asks") { two.sync.attention == .needsPassword }
        #expect(two.sync.notice == .needsPassword)
        #expect(Describe.attention(.needsPassword).isEmpty == false)

        // Neither an edit nor the foreground runs a round meanwhile.
        try await two.addHost("db")
        two.sync.cameForward()
        try await Task.sleep(for: .milliseconds(600))
        #expect(!two.sync.syncing)
        #expect(two.sync.service.status().hasChanges)
        #expect(two.sync.attention == .needsPassword)

        // Settled, the edit goes out.
        try await two.sync.join(location, login: nil, password: newPassword, fresh: false)
        #expect(two.sync.attention == nil)
        try await two.settled()
        one.sync.cameForward()
        try await waitUntil("one has db") { one.hosts.hosts.count == 2 }
    }

    @Test func aDeviceRemovedElsewhereAsksBeforeComingBack() async throws {
        try await setUpBoth()
        one.sync.syncNow()
        try await one.settled()
        let twoId = try #require(two.sync.deviceId)
        let removed = try #require(one.sync.devices.first { $0.id == twoId })
        try await one.sync.removeDevice(removed)
        #expect(one.sync.devices.isEmpty)

        two.sync.syncNow()
        try await waitUntil("two asks") { two.sync.attention == .removed }
        two.sync.rejoin()
        try await two.settled()
        one.sync.syncNow()
        try await one.settled()
        #expect(one.sync.devices.map(\.id) == [twoId])
    }

    @Test func turnedOffItKeepsTheDataAndSyncsNoMore() async throws {
        try await setUpBoth()
        try await two.sync.turnOff(deleteFile: true)
        #expect(two.sync.location == nil)
        #expect(two.sync.phase == .off)
        #expect(two.hosts.hosts.map(\.name) == ["web"])
        #expect(!two.test.keychain.all.keys.contains("sync:keyring"))

        one.sync.syncNow()
        try await one.settled()
        #expect(one.sync.devices.isEmpty)

        try await two.addHost("db")
        two.sync.cameForward()
        try await Task.sleep(for: .milliseconds(400))
        #expect(!two.sync.syncing)
        #expect(two.sync.phase == .off)
    }
}

/// Sync's words for what is typed and what went wrong, as the desktop's.
struct DescribeSyncTests {
    @Test func aPasswordAsTyped() {
        #expect(checkNewSyncPassword(password: "", repeat: "") == .tooShort)
        #expect(checkSyncPassword(password: "") == .missing)
        #expect(checkNewSyncPassword(password: "short", repeat: "short") == .tooShort)
        #expect(
            checkNewSyncPassword(password: "correct horse battery", repeat: "correct horse")
                == .mismatch)
        #expect(checkSyncPassword(password: "correct horse battery") == nil)
        #expect(
            Describe.password(.tooShort)
                == String(localized: "同步密码至少要 \(Int(minSyncPasswordLength())) 个字符。"))
        let random = randomSyncPassword()
        #expect(checkNewSyncPassword(password: random, repeat: random) == nil)
    }

    @Test func aLoginAsTyped() throws {
        let error = #expect(throws: LoginProblem.self) {
            try checkWebdavLogin(url: "ftp://dav.example.com", username: "me", password: "pw")
        }
        #expect(
            Describe.login(try #require(error))
                == String(localized: "地址要以 https:// 或 http:// 开头，比如 https://dav.example.com/ShellRS。"))
        let login = try checkWebdavLogin(
            url: "https://dav.example.com/ShellRS", username: "me", password: "pw")
        #expect(login.location == .webDav(url: "https://dav.example.com/ShellRS", username: "me"))
        #expect(login.login == "pw")

        #expect(throws: LoginProblem.self) {
            try checkS3Login(
                login: S3Login(
                    endpoint: "https://s3.example.com", region: "", bucket: "", prefix: "",
                    pathStyle: false, accessKey: "id", secretKey: "key"))
        }
    }

    @Test func whatTheStorageSaid() {
        #expect(
            Describe.sync(SyncFailure.Storage(problem: .unauthorized))
                == String(localized: "同步的位置拒绝了访问：检查用户名和密码，或文件夹的权限。"))
        #expect(
            Describe.sync(SyncFailure.Storage(problem: .unavailable(detail: "503")))
                == String(localized: "同步文件夹暂时用不了：\("503")"))
        #expect(Describe.platform("macos") == "macOS")
    }
}
