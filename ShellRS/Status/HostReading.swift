import Foundation

/// Which parts a reading asks for besides the load, which every one does.
struct ReadingParts: Equatable, Sendable {
    /// Host name, architecture, system, kernel, CPU model and page size:
    /// once per connection, as they do not change while connected.
    var system = false
    /// Every half minute or so: disks fill slowly, and `df` is the slowest
    /// part of a reading.
    var disks = false
    /// The detail page's: disk I/O, TCP, the users and the processes.
    var details = false
    /// The detail page's, every half minute: systemd's failed units.
    var services = false
}

/// Reading a Linux host for 状态: one command, and the parser for what it
/// prints. The load is the desktop's 系统监控 command (its
/// `src/monitor/linux.rs`), with the load average; the detail page adds disk
/// I/O, TCP, the processes (as the desktop's 进程管理 reads them) and
/// systemd's failed units.
enum HostReading {
    /// The parts asked once per connection.
    private static let system =
        #"echo @@host; uname -n; echo @@arch; uname -m; "#
        + #"echo @@os; (. /etc/os-release && echo "$PRETTY_NAME") 2>/dev/null || uname -sr; "#
        + #"echo @@kernel; uname -r; "#
        + #"echo @@cpu; grep -E "^(model name|Hardware|Processor|cpu model)" /proc/cpuinfo | head -n 1; "#
        + #"echo @@page; getconf PAGESIZE 2>/dev/null; "#

    /// The load, every reading. Shell built-ins only (`read`, `case`,
    /// `echo`), so the one process a reading starts on the host is the `sh`
    /// running it; `/proc/stat` and `/proc/meminfo` are read only as far as
    /// the lines it needs, which come first.
    private static let load =
        #"echo @@uptime; read -r line < /proc/uptime; echo "$line"; "#
        + #"echo @@loadavg; read -r line < /proc/loadavg; echo "$line"; "#
        + #"echo @@stat; while read -r line; do case "$line" in cpu*) echo "$line";; *) break;; esac; "#
        + #"done < /proc/stat; "#
        + #"echo @@memory; while read -r line; do case "$line" in "#
        + #"MemTotal:*|MemFree:*|MemAvailable:*|Buffers:*|Cached:*|SwapTotal:*) echo "$line";; "#
        + #"SwapFree:*) echo "$line"; break;; esac; done < /proc/meminfo; "#
        + #"echo @@net; while read -r line; do echo "$line"; done < /proc/net/dev; "#
        + #"echo @@route; while read -r line; do echo "$line"; done < /proc/net/route; "#

    /// `df -l` keeps to local file systems, so a dead network mount cannot
    /// hold it up; a `df` without `-l` (BusyBox) runs plain.
    private static let disks = #"echo @@df; df -kPl 2>/dev/null || df -kP 2>/dev/null; "#

    /// The most processes a reading lists: some 300 bytes of `/proc` each,
    /// and a command's output keeps 1 MB.
    static let processLimit = 2500

    /// Built-ins again, as the desktop's 进程管理: each process's `stat`
    /// line, with its owner's uid from `status`.
    private static let details =
        #"echo @@diskstats; while read -r line; do echo "$line"; done < /proc/diskstats; "#
        + #"echo @@snmp; while read -r line; do case "$line" in Tcp:*) echo "$line";; esac; "#
        + #"done < /proc/net/snmp; "#
        + #"echo @@sockstat; while read -r line; do echo "$line"; done < /proc/net/sockstat; "#
        + #"echo @@users; while IFS=: read -r name x uid rest; do echo "$uid $name"; done < /etc/passwd; "#
        + #"echo @@processes; n=0; for d in /proc/[0-9]*; do "#
        + #"n=$((n+1)); if test $n -gt \#(processLimit); then break; fi; "#
        + #"read -r stat < $d/stat || continue; uid=; "#
        + #"while read -r key value rest; do case $key in Uid:) uid=$value; break;; esac; done < $d/status; "#
        + #"echo "$uid $stat"; done 2>/dev/null; "#

    /// Only where there is a systemd to ask: no section at all otherwise.
    private static let services =
        #"if command -v systemctl >/dev/null 2>&1; then echo @@failed; "#
        + #"systemctl list-units --state=failed --no-legend --plain --no-pager 2>/dev/null; fi; "#

    /// What 状态 runs on the host for a reading: `/proc` and `df`, each part
    /// under an `@@` line of its own.
    ///
    /// One line, in single quotes for `sh -c`, so that whatever the login
    /// shell is (bash, zsh, fish, csh) it hands the script to `sh`
    /// untouched: the script has no single quote, and no `!` for csh to
    /// expand.
    static func command(_ parts: ReadingParts) -> String {
        "sh -c 'export LC_ALL=C; if test -r /proc/stat; then "
            + (parts.system ? system : "")
            + load
            + (parts.disks ? disks : "")
            + (parts.details ? details : "")
            + (parts.services ? services : "")
            + "else echo @@unsupported; uname -s; fi'"
    }

    /// What the command's output said.
    enum Parsed: Equatable, Sendable {
        case reading(RawReading)
        /// Not a Linux host. Holds `uname -s` when the host has one:
        /// 「Darwin」.
        case unsupported(String?)
    }

    static func parse(_ output: String) -> Parsed {
        var sections: [String: [Substring]] = [:]
        var current: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.hasSuffix("\r") ? line.dropLast() : line
            if line.hasPrefix("@@") {
                let name = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                current = name
                if sections[name] == nil {
                    sections[name] = []
                }
            } else if let current {
                sections[current, default: []].append(line)
            }
        }
        func section(_ name: String) -> [Substring] {
            sections[name] ?? []
        }
        func first(_ name: String) -> String? {
            section(name)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }

        let (cpu, cores) = parseStat(section("stat"))
        guard let cpu else {
            // A shell other than sh's (cmd.exe) prints nothing we know.
            return .unsupported(first("unsupported"))
        }
        var reading = RawReading(cpu: cpu, cores: cores)
        if sections["host"] != nil {
            reading.system = SystemInfo(
                hostName: first("host") ?? "",
                arch: first("arch") ?? "",
                os: first("os") ?? "Linux",
                kernel: first("kernel") ?? "",
                cpuModel: first("cpu")
                    .flatMap { line in
                        line.firstIndex(of: ":").map {
                            line[line.index(after: $0)...].trimmingCharacters(in: .whitespaces)
                        }
                    } ?? "",
                pageSize: first("page").flatMap { UInt64($0) })
        }
        reading.uptime = first("uptime")
            .flatMap { $0.split(separator: " ").first }
            .flatMap { TimeInterval($0) }
        reading.load = first("loadavg").flatMap(parseLoad)
        reading.memory = parseMemory(section("memory"))
        reading.interfaces = parseInterfaces(section("net"))
        reading.defaultRoute = parseDefaultRoute(section("route"))
        if sections["df"] != nil {
            reading.disks = parseDisks(section("df"))
        }
        if sections["diskstats"] != nil {
            reading.diskIO = parseDiskStats(section("diskstats"))
        }
        if sections["snmp"] != nil || sections["sockstat"] != nil {
            reading.tcp = parseTcp(snmp: section("snmp"), sockstat: section("sockstat"))
        }
        if sections["users"] != nil {
            reading.users = parseUsers(section("users"))
        }
        if sections["processes"] != nil {
            reading.processes = section("processes").compactMap(parseProcess)
        }
        if sections["failed"] != nil {
            reading.failedUnits = parseFailedUnits(section("failed"))
        }
        return .reading(reading)
    }

    /// `/proc/stat`'s `cpu` lines: the machine, then each core.
    static func parseStat(_ lines: [Substring]) -> (CpuTimes?, [CpuTimes]) {
        var total: CpuTimes?
        var cores: [CpuTimes] = []
        for line in lines {
            var fields = line.split(separator: " ").makeIterator()
            guard let name = fields.next() else { continue }
            // user nice system idle iowait irq softirq steal; guest time is
            // already counted in user.
            var ticks: [UInt64] = []
            while ticks.count < 8, let field = fields.next() {
                if let tick = UInt64(field) {
                    ticks.append(tick)
                }
            }
            guard ticks.count >= 4 else { continue }
            func tick(_ index: Int) -> UInt64 { index < ticks.count ? ticks[index] : 0 }
            let times = CpuTimes(
                user: tick(0), nice: tick(1), system: tick(2), idle: tick(3), iowait: tick(4),
                irq: tick(5), softirq: tick(6), steal: tick(7))
            if name == "cpu" {
                total = times
            } else if name.hasPrefix("cpu") {
                cores.append(times)
            }
        }
        return (total, cores)
    }

    /// `/proc/loadavg`: 「0.20 0.18 0.12 1/80 11206」.
    static func parseLoad(_ line: String) -> LoadAverage? {
        let fields = line.split(separator: " ")
        guard fields.count >= 3, let one = Double(fields[0]), let five = Double(fields[1]),
            let fifteen = Double(fields[2])
        else {
            return nil
        }
        var load = LoadAverage(one: one, five: five, fifteen: fifteen)
        if fields.count >= 4 {
            let tasks = fields[3].split(separator: "/")
            if tasks.count == 2 {
                load.running = Int(tasks[0])
                load.tasks = Int(tasks[1])
            }
        }
        return load
    }

    /// `/proc/meminfo`, whose sizes are in KiB.
    static func parseMemory(_ lines: [Substring]) -> Memory {
        var values: [String: UInt64] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard let kib = line[line.index(after: colon)...].split(separator: " ").first
                .flatMap({ UInt64($0) })
            else { continue }
            values[name] = kib * 1024
        }
        func value(_ name: String) -> UInt64 { values[name] ?? 0 }
        let total = value("MemTotal")
        // Kernels before 3.14 have no MemAvailable; free, buffers and cache
        // come closest.
        let available =
            values["MemAvailable"] ?? (value("MemFree") + value("Buffers") + value("Cached"))
        return Memory(
            total: total, available: min(available, total), free: value("MemFree"),
            buffers: value("Buffers"), cached: value("Cached"), swapTotal: value("SwapTotal"),
            swapFree: min(value("SwapFree"), value("SwapTotal")))
    }

    /// `/proc/net/dev`: received bytes first, transmitted bytes ninth.
    static func parseInterfaces(_ lines: [Substring]) -> [InterfaceCounters] {
        lines.compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let counters = line[line.index(after: colon)...].split(separator: " ").map {
                UInt64($0)
            }
            guard counters.count >= 9, let received = counters[0], let transmitted = counters[8],
                !counters.contains(nil)
            else {
                return nil
            }
            return InterfaceCounters(
                name: line[..<colon].trimmingCharacters(in: .whitespaces), received: received,
                transmitted: transmitted)
        }
    }

    /// `/proc/net/route`: the interface of the route to everywhere
    /// (destination and mask all zeros), the lowest metric when there are
    /// several.
    static func parseDefaultRoute(_ lines: [Substring]) -> String? {
        lines.compactMap { line -> (UInt32, String)? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 8, fields[1] == "00000000", fields[7] == "00000000" else {
                return nil
            }
            return (UInt32(fields[6]) ?? .max, String(fields[0]))
        }
        .min { $0 < $1 }?.1
    }

    /// `df -kP`, without what is not a disk: memory file systems, the
    /// kernel's own, snaps and container layers.
    static func parseDisks(_ lines: [Substring]) -> [DiskUsage] {
        var disks: [DiskUsage] = []
        for line in lines {
            let fields = line.split(separator: " ")
            guard fields.count >= 6 else { continue }
            // The heading has no numbers.
            guard let total = UInt64(fields[1]).map({ $0 * 1024 }),
                let used = UInt64(fields[2]).map({ $0 * 1024 }),
                let available = UInt64(fields[3]).map({ $0 * 1024 })
            else { continue }
            // A mount point can hold spaces.
            let mount = fields[5...].joined(separator: " ")
            guard total > 0, isDisk(source: String(fields[0]), mount: mount),
                !disks.contains(where: { $0.mount == mount })
            else { continue }
            disks.append(DiskUsage(mount: mount, total: total, used: used, available: available))
        }
        return disks
    }

    /// The desktop's, and the files a container has mounted from its host
    /// (Docker's `/etc/hosts`, `/etc/hostname`, `/etc/resolv.conf`), which
    /// `df` lists with the host's disk.
    static func isDisk(source: String, mount: String) -> Bool {
        let notDisks: Set = ["tmpfs", "devtmpfs", "udev", "overlay", "shm", "none", "run", "efivarfs"]
        let systemMounts = ["/dev", "/run", "/sys", "/proc", "/snap/", "/var/lib/docker/", "/etc/"]
        return !notDisks.contains(source) && !source.hasPrefix("/dev/loop")
            && !systemMounts.contains { mount.hasPrefix($0) }
    }

    /// `/proc/diskstats`, whole disks only: a partition's I/O is its disk's
    /// too, and loop and RAM devices are no disks.
    static func parseDiskStats(_ lines: [Substring]) -> [DiskCounters] {
        lines.compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count >= 10, isWholeDisk(String(fields[2])),
                let read = UInt64(fields[5]), let written = UInt64(fields[9])
            else {
                return nil
            }
            // Sectors of 512 bytes, whatever the disk's own.
            return DiskCounters(name: String(fields[2]), read: read * 512, written: written * 512)
        }
    }

    /// `sda`, `vdb`, `xvda`, `nvme0n1`, `mmcblk0`, `md0`: not `sda1`,
    /// `nvme0n1p1`, `loop0` or `dm-0` (on top of a disk already counted).
    static func isWholeDisk(_ name: String) -> Bool {
        func rest(after prefix: String) -> Substring? {
            name.hasPrefix(prefix) ? name.dropFirst(prefix.count) : nil
        }
        func letters(_ text: Substring) -> Bool {
            !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isLowercase }
        }
        func digits(_ text: Substring) -> Bool {
            !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
        }
        for prefix in ["xvd", "sd", "vd", "hd"] {
            if let rest = rest(after: prefix) {
                return letters(rest)
            }
        }
        if let rest = rest(after: "nvme") {
            let parts = rest.split(separator: "n", omittingEmptySubsequences: false)
            return parts.count == 2 && digits(parts[0]) && digits(parts[1])
        }
        if let rest = rest(after: "mmcblk") {
            return digits(rest)
        }
        if let rest = rest(after: "md") {
            return digits(rest)
        }
        return false
    }

    /// `/proc/net/snmp`'s two `Tcp:` lines, names then values, and
    /// `/proc/net/sockstat`'s `TCP:` line.
    static func parseTcp(snmp: [Substring], sockstat: [Substring]) -> TcpCounts {
        var counts = TcpCounts()
        let tcp = snmp.filter { $0.hasPrefix("Tcp:") }.map { $0.split(separator: " ").dropFirst() }
        if tcp.count >= 2 {
            for (name, value) in zip(tcp[0], tcp[1]) where name == "CurrEstab" {
                counts.established = Int(value)
            }
        }
        if let line = sockstat.first(where: { $0.hasPrefix("TCP:") }) {
            let fields = Array(line.split(separator: " ").dropFirst())
            for index in stride(from: 0, to: fields.count - 1, by: 2) {
                switch fields[index] {
                case "inuse": counts.inUse = Int(fields[index + 1])
                case "tw": counts.timeWait = Int(fields[index + 1])
                default: break
                }
            }
        }
        return counts
    }

    /// `/etc/passwd` as the command prints it: 「0 root」.
    static func parseUsers(_ lines: [Substring]) -> [UInt32: String] {
        var users: [UInt32: String] = [:]
        for line in lines {
            let fields = line.split(separator: " ", maxSplits: 1)
            if fields.count == 2, let uid = UInt32(fields[0]), users[uid] == nil {
                users[uid] = String(fields[1])
            }
        }
        return users
    }

    /// `PF_KTHREAD` in a `stat` line's flags: a kernel thread, which has no
    /// program to look at.
    private static let kernelThread: UInt64 = 0x0020_0000

    /// 「1000 4242 (my prog) S 1 …」: the owner's uid, then the process's
    /// `/proc/<pid>/stat`, whose name may hold spaces and parentheses.
    static func parseProcess(_ line: Substring) -> ProcessSample? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"),
            open < close
        else {
            return nil
        }
        let head = line[..<open].split(separator: " ")
        guard head.count == 2, let uid = UInt32(head[0]), let pid = Int32(head[1]) else {
            return nil
        }
        let name = String(line[line.index(after: open)..<close])
        // From the state on: field 3 of `proc(5)` at index 0.
        let fields = line[line.index(after: close)...].split(separator: " ")
        func number(_ field: Int) -> UInt64? {
            let index = field - 3
            return index < fields.count ? UInt64(fields[index]) : nil
        }
        guard fields.count > 21, let utime = number(14), let stime = number(15),
            let flags = number(9), let threads = number(20), let rss = number(24)
        else {
            return nil
        }
        if flags & kernelThread != 0 {
            return nil
        }
        return ProcessSample(
            pid: pid, uid: uid, name: name, state: fields[0].first ?? "?", ticks: utime + stime,
            threads: Int(threads), rssPages: rss)
    }

    /// `systemctl list-units --state=failed --plain`: the unit first, after
    /// the 「●」 older ones put before it.
    static func parseFailedUnits(_ lines: [Substring]) -> [String] {
        lines.compactMap { line in
            line.split(separator: " ").first { $0 != "●" && $0 != "*" }.map(String.init)
        }
    }
}

/// One look at a host: its counters at that moment, and the parts read less
/// often when this reading asked for them.
struct RawReading: Equatable, Sendable {
    /// Read once per connection.
    var system: SystemInfo?
    var uptime: TimeInterval?
    var load: LoadAverage?
    /// CPU time since boot: the whole machine, then each core.
    var cpu: CpuTimes
    var cores: [CpuTimes]
    var memory = Memory()
    var interfaces: [InterfaceCounters] = []
    /// The interface the default route goes out of: the host's main one.
    var defaultRoute: String?
    /// Read every half minute or so.
    var disks: [DiskUsage]?
    /// The detail page's.
    var diskIO: [DiskCounters]?
    var tcp: TcpCounts?
    var users: [UInt32: String]?
    var processes: [ProcessSample]?
    /// `nil` where there is no systemd.
    var failedUnits: [String]?
}

/// What does not change while connected.
struct SystemInfo: Equatable, Sendable {
    var hostName: String
    var arch: String
    /// The distribution's own name, 「Debian GNU/Linux 12 (bookworm)」.
    var os: String
    var kernel: String
    var cpuModel: String
    /// What `rss` counts in; 4 KiB on most hosts.
    var pageSize: UInt64?
}

/// CPU time since boot, in the kernel's ticks.
struct CpuTimes: Equatable, Sendable {
    var user: UInt64 = 0
    var nice: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var iowait: UInt64 = 0
    var irq: UInt64 = 0
    var softirq: UInt64 = 0
    var steal: UInt64 = 0

    var busy: UInt64 { user + nice + system + irq + softirq + steal }
    var waiting: UInt64 { idle + iowait }
    var total: UInt64 { busy + waiting }
}

struct LoadAverage: Equatable, Sendable {
    var one: Double
    var five: Double
    var fifteen: Double
    /// Running now, of all the tasks there are.
    var running: Int?
    var tasks: Int?
}

/// In bytes.
struct Memory: Equatable, Sendable {
    var total: UInt64 = 0
    var available: UInt64 = 0
    var free: UInt64 = 0
    var buffers: UInt64 = 0
    var cached: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapFree: UInt64 = 0

    var used: UInt64 { total - available }
    var swapUsed: UInt64 { swapTotal - swapFree }
    var percent: Double { share(used, of: total) }
    var swapPercent: Double { share(swapUsed, of: swapTotal) }
}

/// Bytes through a network interface since it came up.
struct InterfaceCounters: Equatable, Sendable {
    var name: String
    var received: UInt64
    var transmitted: UInt64
}

/// A mounted file system, in bytes.
struct DiskUsage: Equatable, Sendable {
    var mount: String
    var total: UInt64
    var used: UInt64
    var available: UInt64

    /// As `df` counts it: the share taken of the space ordinary users can
    /// have, which leaves out what is reserved for root.
    var percent: Double { share(used, of: used + available) }
}

/// Bytes read from and written to a disk since boot.
struct DiskCounters: Equatable, Sendable {
    var name: String
    var read: UInt64
    var written: UInt64
}

struct TcpCounts: Equatable, Sendable {
    var established: Int?
    var timeWait: Int?
    /// Every TCP socket open, listening ones included.
    var inUse: Int?
}

/// A process as `/proc` has it at one moment.
struct ProcessSample: Equatable, Sendable {
    var pid: Int32
    var uid: UInt32
    var name: String
    /// `R` running, `S` sleeping, `D` waiting on a disk, `Z` a zombie…
    var state: Character
    /// The CPU time it used, in the kernel's ticks.
    var ticks: UInt64
    var threads: Int
    var rssPages: UInt64
}

func share(_ part: UInt64, of whole: UInt64) -> Double {
    whole == 0 ? 0 : Double(part) * 100 / Double(whole)
}

// MARK: Snapshots

/// The load the pages show: a reading, and how it moved since the one
/// before.
struct HostSnapshot: Equatable, Sendable {
    var uptime: TimeInterval?
    var load: LoadAverage?
    var coreCount: Int
    /// Percent busy since the reading before; `nil` for the first.
    var cpu: CpuLoad?
    var memory: Memory
    var interfaces: [InterfaceRate]
    var defaultRoute: String?
    /// The detail page's; `nil` when the reading had none.
    var diskIO: [DiskRate]?
    var tcp: TcpCounts?
    /// Busiest first; `nil` when the reading had none.
    var processes: [ProcessLoad]?

    /// The interfaces worth a row: not loopback, and not one that never
    /// carried a byte.
    var busyInterfaces: [InterfaceRate] {
        interfaces.filter { !$0.idle }
    }

    /// The host's main interface: where the default route goes out, or else
    /// the one that carried the most.
    var mainInterface: InterfaceRate? {
        let busy = busyInterfaces
        return busy.first { $0.name == defaultRoute } ?? busy.max { $0.bytes < $1.bytes }
    }
}

struct CpuLoad: Equatable, Sendable {
    var total: Double
    var user: Double
    var system: Double
    /// Waiting on disks: high when they are the bottleneck.
    var iowait: Double
    /// Taken by the hypervisor for other guests: high on an oversold VPS.
    var steal: Double
    var cores: [Double]
}

/// Bytes per second through a network interface since the reading before;
/// `nil` for the first.
struct InterfaceRate: Equatable, Sendable {
    var name: String
    var received: Double?
    var transmitted: Double?
    /// Bytes both ways since the interface came up.
    var bytes: UInt64
    /// Loopback, or never carried a byte: not worth a row.
    var idle: Bool
}

struct DiskRate: Equatable, Sendable {
    var name: String
    /// Bytes per second.
    var read: Double
    var written: Double
}

struct ProcessLoad: Equatable, Sendable, Identifiable {
    var pid: Int32
    var name: String
    var user: String
    var state: Character
    /// Percent of one core, as `top` counts it: 200 is two cores' worth.
    var cpu: Double?
    /// Resident memory, in bytes.
    var memory: UInt64
    var threads: Int

    var id: Int32 { pid }
}

/// Turns readings into snapshots. Rates need the reading before, which is
/// what this keeps.
struct ReadingTracker: Sendable {
    /// Readings further apart than this are no base for rates: what they
    /// would show is an average over minutes, not what the host is doing.
    static let stale: TimeInterval = 15

    private var last: (reading: RawReading, at: Date)?

    mutating func reset() {
        last = nil
    }

    /// `pageSize` and `users` are what the reading's processes are counted
    /// with, from this or an earlier reading.
    mutating func update(
        _ reading: RawReading, at date: Date, pageSize: UInt64 = 4096,
        users: [UInt32: String] = [:]
    ) -> HostSnapshot {
        let before = last.flatMap { last -> (RawReading, TimeInterval)? in
            let elapsed = date.timeIntervalSince(last.at)
            return elapsed > 0 && elapsed <= Self.stale ? (last.reading, elapsed) : nil
        }
        last = (reading, date)
        return Self.snapshot(reading, before: before, pageSize: pageSize, users: users)
    }

    private static func snapshot(
        _ reading: RawReading, before: (RawReading, TimeInterval)?, pageSize: UInt64,
        users: [UInt32: String]
    ) -> HostSnapshot {
        let cpu = before.flatMap { before in
            cpuLoad(reading.cpu, before.0.cpu).map { load in
                var load = load
                // Per core only when the cores are the same ones as before.
                if reading.cores.count == before.0.cores.count {
                    load.cores = zip(reading.cores, before.0.cores).map {
                        cpuLoad($0, $1)?.total ?? 0
                    }
                }
                return load
            }
        }
        let interfaces = reading.interfaces.map { interface in
            let then = before.flatMap { before in
                before.0.interfaces.first { $0.name == interface.name }.map { ($0, before.1) }
            }
            return InterfaceRate(
                name: interface.name,
                received: then.flatMap { rate(interface.received, $0.0.received, $0.1) },
                transmitted: then.flatMap { rate(interface.transmitted, $0.0.transmitted, $0.1) },
                bytes: interface.received &+ interface.transmitted,
                idle: interface.name == "lo"
                    || (interface.received == 0 && interface.transmitted == 0))
        }
        let diskIO = reading.diskIO.map { disks in
            disks.compactMap { disk -> DiskRate? in
                guard let before, let then = before.0.diskIO?.first(where: { $0.name == disk.name }),
                    let read = rate(disk.read, then.read, before.1),
                    let written = rate(disk.written, then.written, before.1)
                else {
                    return nil
                }
                return DiskRate(name: disk.name, read: read, written: written)
            }
        }
        let processes = reading.processes.map { processes in
            let coreCount = Double(max(reading.cores.count, 1))
            let elapsed = before.flatMap { before -> (ticks: UInt64, then: [Int32: UInt64])? in
                guard let then = before.0.processes, reading.cpu.total > before.0.cpu.total else {
                    return nil
                }
                return (
                    reading.cpu.total - before.0.cpu.total,
                    Dictionary(then.map { ($0.pid, $0.ticks) }, uniquingKeysWith: { a, _ in a })
                )
            }
            return processes.map { process in
                // A tick of every core's goes by for each of one core's.
                let cpu = elapsed.flatMap { elapsed -> Double? in
                    guard let then = elapsed.then[process.pid], process.ticks >= then else {
                        return nil
                    }
                    return Double(process.ticks - then) * 100 * coreCount / Double(elapsed.ticks)
                }
                return ProcessLoad(
                    pid: process.pid, name: process.name,
                    user: users[process.uid] ?? String(process.uid), state: process.state,
                    cpu: cpu, memory: process.rssPages * pageSize, threads: process.threads)
            }
            .sorted { ($0.cpu ?? 0, $0.memory) > ($1.cpu ?? 0, $1.memory) }
        }
        return HostSnapshot(
            uptime: reading.uptime, load: reading.load, coreCount: reading.cores.count, cpu: cpu,
            memory: reading.memory, interfaces: interfaces, defaultRoute: reading.defaultRoute,
            diskIO: diskIO, tcp: reading.tcp, processes: processes)
    }

    /// A counter that went down was reset: the interface came up again, or
    /// the host rebooted.
    private static func rate(_ now: UInt64, _ then: UInt64, _ seconds: TimeInterval) -> Double? {
        now >= then ? Double(now - then) / seconds : nil
    }

    /// `nil` when the counters went down, which they only do across a
    /// reboot.
    private static func cpuLoad(_ now: CpuTimes, _ then: CpuTimes) -> CpuLoad? {
        guard now.busy >= then.busy, now.waiting >= then.waiting, now.user >= then.user,
            now.system >= then.system, now.iowait >= then.iowait, now.steal >= then.steal
        else {
            return nil
        }
        let total = Double(now.total - then.total)
        guard total > 0 else { return nil }
        func part(_ value: KeyPath<CpuTimes, UInt64>) -> Double {
            Double(now[keyPath: value] - then[keyPath: value]) * 100 / total
        }
        return CpuLoad(
            total: part(\.busy), user: part(\.user) + part(\.nice), system: part(\.system),
            iowait: part(\.iowait), steal: part(\.steal), cores: [])
    }
}
