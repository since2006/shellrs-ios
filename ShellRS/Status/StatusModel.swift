import Foundation
import Observation
import ShellRSCore

/// 状态: the hosts the user chose to see there, and a monitor on each while
/// a page of it is shown. Which hosts are this device's own choice, kept by
/// their public ids, not synced: sync carries what the desktop has, and the
/// desktop has no such list.
@MainActor
@Observable
final class StatusModel {
    /// The public ids of the hosts 状态 shows.
    private(set) var shown: Set<String>

    @ObservationIgnored private let core: Core
    @ObservationIgnored private let hosts: HostsModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var monitors: [String: HostMonitor] = [:]
    /// The pages of 状态 shown now: the list, a host's details.
    @ObservationIgnored private var pages = 0
    /// A page was shown a moment ago: going back to it soon finds the
    /// connections still there.
    @ObservationIgnored private var lingering = false
    @ObservationIgnored private var stopping: Task<Void, Never>?
    @ObservationIgnored private var foreground = true

    /// How long the connections stay after the last page of 状态 goes, for
    /// a look at a terminal and back.
    static let linger: Duration = .seconds(30)
    static let shownKey = "statusHosts"

    init(core: Core, hosts: HostsModel, defaults: UserDefaults = .standard) {
        self.core = core
        self.hosts = hosts
        self.defaults = defaults
        shown = Set(defaults.stringArray(forKey: Self.shownKey) ?? [])
    }

    /// Whether 状态 shows `host`.
    func isShown(_ host: Host) -> Bool {
        shown.contains(host.publicId)
    }

    func setShown(_ isShown: Bool, for host: Host) {
        guard isShown != self.isShown(host) else {
            return
        }
        if isShown {
            shown.insert(host.publicId)
        } else {
            shown.remove(host.publicId)
        }
        defaults.set(shown.sorted(), forKey: Self.shownKey)
        update()
    }

    /// The hosts 状态 shows, in the order of the host list. Only SSH hosts
    /// connect here.
    var shownHosts: [Host] {
        hosts.hosts.filter { $0.isSsh && shown.contains($0.publicId) }
    }

    /// The SSH hosts 状态 could show.
    var candidates: [Host] {
        hosts.hosts.filter(\.isSsh)
    }

    /// `host`'s monitor, made when first asked for. The pages of 状态 start
    /// and stop it as they show and go, never while drawing.
    func monitor(for host: Host) -> HostMonitor {
        if let monitor = monitors[host.publicId] {
            return monitor
        }
        let monitor = HostMonitor(host: host, core: core)
        monitors[host.publicId] = monitor
        return monitor
    }

    // MARK: When to look

    func pageAppeared() {
        pages += 1
        stopping?.cancel()
        stopping = nil
        lingering = false
        update()
    }

    func pageDisappeared() {
        pages = max(pages - 1, 0)
        guard pages == 0 else {
            return
        }
        lingering = true
        stopping?.cancel()
        stopping = Task { [weak self] in
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled, let self else { return }
            lingering = false
            update()
        }
    }

    /// iOS suspends the app soon after it goes: the connections would drop.
    func wentToBackground() {
        foreground = false
        lingering = false
        stopping?.cancel()
        update()
    }

    func cameForward() {
        foreground = true
        update()
    }

    /// The hosts changed, here or through sync: one edited connects anew,
    /// one deleted stops.
    func hostsChanged() {
        for host in hosts.hosts {
            monitors[host.publicId]?.update(host)
        }
        update()
    }

    private var isActive: Bool {
        foreground && (pages > 0 || lingering)
    }

    private func update() {
        let wanted = Set(shownHosts.map(\.publicId))
        for (id, monitor) in monitors where !wanted.contains(id) {
            monitor.stop()
            monitors[id] = nil
        }
        guard isActive || !monitors.isEmpty else {
            return
        }
        for host in shownHosts {
            let monitor = monitor(for: host)
            if isActive {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
    }
}

/// One host on 状态: its connection, and what its readings say. Each
/// reading is one command on a channel of the connection, every few
/// seconds; the detail page's parts only while it is shown.
@MainActor
@Observable
final class HostMonitor: Identifiable {
    enum State: Equatable {
        /// Not looking: no page of 状态 is shown.
        case idle
        case connecting
        /// The login waits for the user: a host key to trust, a password.
        case asking(Prompt)
        case live
        /// Not a Linux host: `uname -s` when it has one.
        case unsupported(String?)
        case failed(String)
    }

    /// A moment of the charts.
    struct Point: Identifiable, Equatable {
        let at: Date
        let cpu: Double?
        let memory: Double
        let received: Double?
        let transmitted: Double?

        var id: Date { at }
    }

    private(set) var host: Host
    private(set) var state = State.idle
    /// Read once per connection.
    private(set) var system: SystemInfo?
    private(set) var snapshot: HostSnapshot?
    /// Read every half minute.
    private(set) var disks: [DiskUsage]?
    /// The detail page's, every half minute; `nil` where there is no
    /// systemd, or until read.
    private(set) var failedUnits: [String]?
    private(set) var latency: UInt64?
    /// The last few minutes, oldest first.
    private(set) var history: [Point] = []
    /// Why the last reading failed, the connection still up.
    private(set) var readingProblem: String?
    /// Whether the detail page is shown: the readings take its parts too.
    var detailed = false {
        didSet {
            if detailed && !oldValue {
                pause?.cancel()
            }
        }
    }

    /// The host's public id, which never changes.
    let id: String

    @ObservationIgnored private let core: Core
    @ObservationIgnored private var connection: Connection?
    /// Events and readings of an earlier connection are dropped.
    @ObservationIgnored private var attempt = 0
    /// Whether a page wants it running.
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var tracker = ReadingTracker()
    @ObservationIgnored private var users: [UInt32: String] = [:]
    @ObservationIgnored private var disksRead: Date?
    @ObservationIgnored private var servicesRead: Date?
    @ObservationIgnored private var pause: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?

    static let interval: Duration = .seconds(3)
    /// How often the slow parts are read: disks, failed units.
    static let slowInterval: TimeInterval = 30
    /// Three minutes of readings.
    static let historyLength = 60
    /// How soon a connection the network dropped is tried again.
    static let retryDelay: Duration = .seconds(15)

    init(host: Host, core: Core) {
        self.host = host
        self.core = core
        id = host.publicId
    }

    var isAsking: Bool {
        if case .asking = state { return true }
        return false
    }

    /// Connects, unless started already: connected, connecting, waiting
    /// to try again, or failed in a way only the user can try again after
    /// (a login put away, a password refused), which a sync coming in must
    /// not ask about again.
    func start() {
        guard !wanted else {
            return
        }
        wanted = true
        connect()
    }

    /// Ends the connection; what it read stays to be shown.
    func stop() {
        wanted = false
        retry?.cancel()
        retry = nil
        attempt += 1
        connection?.disconnect()
        connection = nil
        pause?.cancel()
        switch state {
        case .connecting, .asking, .live:
            state = .idle
        case .idle, .unsupported, .failed:
            break
        }
    }

    /// Connects again now: after a failure, or to answer a question the
    /// user put away.
    func reconnect() {
        stop()
        start()
    }

    /// The host as saved now. A change to how it logs in connects anew.
    func update(_ host: Host) {
        let old = self.host
        let moved = host.address != old.address || host.port != old.port
        let changed = moved || host.user != old.user || host.auth != old.auth
            || host.route != old.route
        self.host = host
        if changed, wanted {
            reconnect()
        }
    }

    func answer(_ reply: PromptReply) {
        guard case .asking(let prompt) = state, let connection else {
            return
        }
        state = .connecting
        connection.answer(promptId: prompt.id, reply: reply)
    }

    private func connect() {
        attempt += 1
        let attempt = attempt
        retry?.cancel()
        retry = nil
        state = .connecting
        tracker.reset()
        history = []
        latency = nil
        readingProblem = nil
        // Read all of it again: the host may have changed meanwhile, or
        // be another one at the address.
        system = nil
        disksRead = nil
        servicesRead = nil
        let connection: Connection
        do {
            connection = try core.watchHost(id: host.id)
        } catch {
            state = .failed(Describe.store(error))
            return
        }
        self.connection = connection
        Task { [weak self] in
            while let event = await connection.nextEvent() {
                guard let self, self.attempt == attempt else {
                    connection.disconnect()
                    return
                }
                handle(event, on: connection, attempt: attempt)
            }
        }
    }

    private func handle(_ event: ConnectionEvent, on connection: Connection, attempt: Int) {
        switch event {
        case .prompt(let prompt):
            state = .asking(prompt)
        case .connected:
            state = .live
            poll(connection, attempt: attempt)
        case .latency(let milliseconds):
            latency = milliseconds
        case .closed(let failure):
            self.connection = nil
            latency = nil
            guard let failure else {
                state = .idle
                return
            }
            state = .failed(Describe.failure(failure))
            if failure.network, wanted {
                retry = Task { [weak self] in
                    try? await Task.sleep(for: Self.retryDelay)
                    guard !Task.isCancelled, let self else { return }
                    retry = nil
                    if wanted {
                        connect()
                    }
                }
            }
        }
    }

    private func poll(_ connection: Connection, attempt: Int) {
        Task { [weak self] in
            while let self, self.attempt == attempt {
                await read(on: connection, attempt: attempt)
                guard self.attempt == attempt else { return }
                let pause = Task { _ = try? await Task.sleep(for: Self.interval) }
                self.pause = pause
                await pause.value
            }
        }
    }

    private func read(on connection: Connection, attempt: Int) async {
        let now = Date()
        let due = { (last: Date?) in
            last.map { now.timeIntervalSince($0) >= Self.slowInterval } ?? true
        }
        let parts = ReadingParts(
            system: system == nil, disks: due(disksRead), details: detailed,
            services: detailed && due(servicesRead))
        let parsed: HostReading.Parsed
        do {
            let stdout = try await connection.exec(command: HostReading.command(parts)).stdout
            // Some hundreds of KB with the processes: not on the main thread.
            parsed = await Task.detached(priority: .utility) {
                HostReading.parse(String(decoding: stdout, as: UTF8.self))
            }.value
        } catch {
            if self.attempt == attempt {
                readingProblem = Describe.ssh(error)
            }
            return
        }
        guard self.attempt == attempt else {
            return
        }
        switch parsed {
        case .unsupported(let system):
            self.attempt += 1
            connection.disconnect()
            self.connection = nil
            state = .unsupported(system)
        case .reading(let reading):
            apply(reading, parts: parts, at: Date())
        }
    }

    private func apply(_ reading: RawReading, parts: ReadingParts, at date: Date) {
        if let system = reading.system {
            self.system = system
        }
        if let users = reading.users {
            self.users = users
        }
        if let disks = reading.disks {
            self.disks = disks
            disksRead = date
        }
        if parts.services {
            failedUnits = reading.failedUnits
            servicesRead = date
        }
        let snapshot = tracker.update(
            reading, at: date, pageSize: system?.pageSize ?? 4096, users: users)
        self.snapshot = snapshot
        readingProblem = nil
        let main = snapshot.mainInterface
        history.append(
            Point(
                at: date, cpu: snapshot.cpu?.total, memory: snapshot.memory.percent,
                received: main?.received, transmitted: main?.transmitted))
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }
}
