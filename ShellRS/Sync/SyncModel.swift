import Foundation
import Observation
import ShellRSCore
import UIKit

/// Sync as the settings show it, and when it runs: when the app starts or
/// comes to the foreground (at most once a minute), a few seconds after
/// the user stops editing, and before the app goes to the background if
/// something changed. Never on a timer. What only the user can settle
/// holds the automatic rounds until they have.
@MainActor
@Observable
final class SyncModel {
    /// How the last round went, as the page says it. A round running is
    /// `syncing`, beside it.
    enum Phase: Equatable {
        case off
        /// On, and no round went through this run.
        case waiting
        case synced(Date)
        /// In words, errors only show here (as on the desktop).
        case failed(String)
    }

    let service: SyncService
    /// What the other devices call this one.
    let deviceName: String
    /// `nil` while sync is off.
    private(set) var location: SyncLocation?
    /// This device's id in sync, once a round has gone through.
    private(set) var deviceId: String?
    /// The other devices, as the last round found them.
    private(set) var devices: [SyncDevice] = []
    private(set) var phase: Phase
    /// What only the user can settle; automatic rounds wait for it.
    private(set) var attention: Attention?
    /// An attention the user has not been told about yet.
    var notice: Attention?
    /// The sync page is on screen: it says what `notice` would.
    var pageShown = false
    /// Someone asked from elsewhere for the page to settle `attention`.
    var reviewRequested = false
    /// A job other than a round runs: setting up, joining, …
    private(set) var jobRunning = false

    /// How long after the last edit a round runs.
    var editPause: Duration = .seconds(5)
    /// The least time between rounds the foreground brings.
    var foregroundGap: Duration = .seconds(60)

    /// A round asked for while something ran, to run after it.
    private enum Again {
        case automatic
        /// The user asked: it runs whatever waits for them.
        case asked
    }

    private var round: Task<Void, Never>?
    private var again: Again?
    private var allowMassDelete = false
    private var acceptRemoved = false
    private var lastRoundAt: ContinuousClock.Instant?
    private var pause: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(service: SyncService, deviceName: String) {
        self.service = service
        self.deviceName = deviceName
        phase = .off
        refresh()
        phase = location == nil ? .off : .waiting
    }

    var syncing: Bool {
        round != nil
    }

    var busy: Bool {
        round != nil || jobRunning
    }

    // MARK: When to sync

    /// 立即同步: a round now, whatever waited for the user (it asks again
    /// if it still does).
    func syncNow() {
        attention = nil
        notice = nil
        startRound(asked: true)
    }

    /// The app started or came to the foreground: a round, unless one ran
    /// just now.
    func cameForward() {
        if let lastRoundAt, ContinuousClock.now - lastRoundAt < foregroundGap {
            return
        }
        syncAutomatically()
    }

    /// The store changed: a round once the user stops editing, if what
    /// syncs did.
    func storeChanged() {
        guard location != nil, service.status().hasChanges else {
            return
        }
        pause?.cancel()
        pause = Task { [weak self, editPause] in
            try? await Task.sleep(for: editPause)
            guard let self, !Task.isCancelled else {
                return
            }
            pause = nil
            if service.status().hasChanges {
                syncAutomatically()
            }
        }
    }

    /// The app goes to the background: what changed goes out first, with
    /// the time the system gives for it.
    func goingToBackground() {
        guard location != nil, attention == nil, round != nil || service.status().hasChanges
        else {
            return
        }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Sync") {
                [weak self] in
                MainActor.assumeIsolated {
                    self?.endBackgroundTask()
                }
            }
        }
        if round == nil {
            startRound()
        }
    }

    /// The user agreed to the deletions the round would make.
    func allowMassDeletes() {
        allowMassDelete = true
        syncNow()
    }

    /// The user wants this device back in sync, removed elsewhere as it
    /// was.
    func rejoin() {
        acceptRemoved = true
        syncNow()
    }

    private func syncAutomatically() {
        if attention == nil {
            startRound()
        }
    }

    private func startRound(asked: Bool = false) {
        if busy {
            if asked || again == nil {
                again = asked ? .asked : .automatic
            }
            return
        }
        guard location != nil else {
            endBackgroundTask()
            return
        }
        pause?.cancel()
        pause = nil
        let allowMassDelete = self.allowMassDelete
        let acceptRemoved = self.acceptRemoved
        self.allowMassDelete = false
        self.acceptRemoved = false
        round = Task { [weak self, service] in
            let outcome: Result<SyncOutcome, Error>
            do {
                outcome = .success(
                    try await service.syncNow(
                        allowMassDelete: allowMassDelete, acceptRemoved: acceptRemoved))
            } catch {
                outcome = .failure(error)
            }
            self?.roundEnded(outcome)
        }
    }

    private func roundEnded(_ outcome: Result<SyncOutcome, Error>) {
        round = nil
        lastRoundAt = .now
        switch outcome {
        case .success(.synced):
            phase = .synced(Date())
        case .success(.attention(let attention)):
            // What the last round that went through found still stands.
            if self.attention != attention {
                self.attention = attention
                notice = pageShown ? nil : attention
            }
        case .failure(SyncFailure.Closed):
            break
        case .failure(SyncFailure.NotSetUp):
            phase = .off
        case .failure(let error):
            phase = .failed(Describe.sync(error))
        }
        refresh()
        ended()
    }

    /// A round or a job ended: what waited for it runs now.
    private func ended() {
        switch again.take() {
        case .asked:
            syncNow()
        case .automatic:
            syncAutomatically()
        case nil:
            break
        }
        if round == nil {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Where sync goes, this device's id and the others, as the core keeps
    /// them.
    private func refresh() {
        let status = service.status()
        location = status.location
        deviceId = status.deviceId
        devices = status.devices
    }

    // MARK: Jobs

    /// Whether sync is set up at `location` already: to join it, or to set
    /// it up.
    func inspect(_ location: SyncLocation, login: String?) async throws -> Bool {
        try await job { [service] in
            try await service.inspect(location: location, login: login)
        }
    }

    /// 测试连接: write, read and delete a file there, keeping nothing.
    func testConnection(_ location: SyncLocation, login: String?) async throws {
        try await service.testConnection(location: location, login: login)
    }

    /// Set sync up at `location` with a new sync password, then sync.
    func create(_ location: SyncLocation, login: String?, password: String) async throws {
        try await job { [service] in
            try await service.create(location: location, login: login, password: password)
        }
        joined()
    }

    /// Join the sync at `location`, then sync. `fresh` forgets what this
    /// device synced before: the first time, or sync was reset.
    func join(
        _ location: SyncLocation, login: String?, password: String, fresh: Bool
    ) async throws {
        try await job { [service] in
            try await service.join(
                location: location, login: login, password: password, fresh: fresh)
        }
        joined()
    }

    /// Sign in anew to where sync goes, then sync.
    func changeLogin(_ location: SyncLocation, login: String) async throws {
        try await job { [service] in
            try await service.changeLogin(location: location, login: login)
        }
        joined()
    }

    /// 更换同步密码, the data key with it; then sync.
    func changePassword(_ password: String) async throws {
        try await job { [service] in
            try await service.changePassword(password: password)
        }
        syncNow()
    }

    func removeDevice(_ device: SyncDevice) async throws {
        try await job { [service] in
            try await service.removeDevice(id: device.id)
        }
        refresh()
    }

    /// 关闭同步: the data here stays; with `deleteFile`, this device's file
    /// there goes too.
    func turnOff(deleteFile: Bool) async throws {
        try await job { [service] in
            try await service.turnOff(deleteFile: deleteFile)
        }
        pause?.cancel()
        pause = nil
        attention = nil
        notice = nil
        lastRoundAt = nil
        refresh()
        phase = .off
    }

    /// Sync goes somewhere now, or again: a round tells how it stands.
    private func joined() {
        refresh()
        phase = .waiting
        syncNow()
    }

    /// Runs `work` once the round running has ended: the core runs one
    /// job at a time.
    private func job<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        jobRunning = true
        defer {
            jobRunning = false
            ended()
        }
        while let round {
            await round.value
        }
        return try await work()
    }
}
