import Foundation
import Testing

@testable import ShellRS

/// 状态's reading: the desktop's 系统监控 command and parser, with what the
/// detail page reads besides.
struct HostReadingTests {
    /// What a small Debian VPS answers: the desktop's sample, with the load
    /// average and the detail page's parts.
    static let debian = """
        @@host
        VM236A61A0D4D4D22
        @@arch
        x86_64
        @@os
        Debian GNU/Linux 12 (bookworm)
        @@kernel
        6.1.0-18-amd64
        @@cpu
        model name\t: AMD EPYC-Milan Processor
        @@page
        4096
        @@uptime
        5359162.33 5293480.12
        @@loadavg
        0.20 0.18 0.12 1/80 11206
        @@stat
        cpu  4705 356 584 3699176 2311 0 158 77 0 0
        cpu0 4705 356 584 3699176 2311 0 158 77 0 0
        @@memory
        MemTotal:         996608 kB
        MemFree:          120000 kB
        MemAvailable:     565480 kB
        Buffers:           40000 kB
        Cached:           400000 kB
        SwapTotal:       1048572 kB
        SwapFree:         996144 kB
        @@net
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo:   12345      67    0    0    0     0          0         0    12345      67    0    0    0     0       0          0
          eth0: 987654321  1000    0    0    0     0          0         0 123456789   900    0    0    0     0       0          0
        docker0:       0       0    0    0    0     0          0         0        0     0    0    0    0     0       0          0
        @@route
        Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
        eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
        wg0\t00000000\t00000000\t0001\t0\t0\t50\t80000000\t0\t0\t0
        eth0\t0001A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0
        @@df
        Filesystem     1024-blocks    Used Available Capacity Mounted on
        udev                483152       0    483152       0% /dev
        tmpfs                99664     560     99104       1% /run
        /dev/vda1          9656904 3240180   5994708      36% /
        tmpfs               498304       0    498304       0% /dev/shm
        /dev/vda15          126678   12068    114610      10% /boot/efi
        /dev/loop0           65536   65536         0     100% /snap/core20/2105
        /dev/sdb1         20511312  102400  19343952       1% /mnt/My Data
        /dev/vda1          9656904 3240180   5994708      36% /etc/hosts
        @@diskstats
         254       0 vda 12000 300 800000 9000 5000 2000 400000 7000 0 8000 16000
         254       1 vda1 11000 300 790000 8900 5000 2000 400000 7000 0 7900 15900
           7       0 loop0 50 0 1000 10 0 0 0 0 0 10 10
         259       0 nvme0n1 100 0 2000 10 100 0 4000 10 0 20 20
         259       1 nvme0n1p1 100 0 2000 10 100 0 4000 10 0 20 20
        @@snmp
        Tcp: RtoAlgorithm RtoMin RtoMax MaxConn ActiveOpens PassiveOpens AttemptFails EstabResets CurrEstab InSegs
        Tcp: 1 200 120000 -1 1000 2000 30 40 12 99999
        @@sockstat
        sockets: used 180
        TCP: inuse 9 orphan 0 tw 25 alloc 12 mem 2
        UDP: inuse 3 mem 1
        @@users
        0 root
        33 www-data
        @@processes
        0 1 (systemd) S 0 1 1 0 -1 4194560 9000 0 80 0 120 80 0 0 20 0 1 0 5 170000000 3000 18446744073709551615
        0 2 (kthreadd) S 0 0 0 0 -1 2129984 0 0 0 0 0 0 0 0 20 0 1 0 2 0 0 18446744073709551615
        33 4242 (php-fpm: pool (www)) R 1 4242 4242 0 -1 4194624 500 0 0 0 300 100 0 0 20 0 4 0 900 300000000 5000 18446744073709551615
        @@failed
        nginx.service loaded failed failed A high performance web server
        ● cron.service loaded failed failed Regular background program processing daemon
        """

    private func reading(_ output: String = debian) throws -> RawReading {
        guard case .reading(let reading) = HostReading.parse(output) else {
            Issue.record("read as Linux")
            throw CancellationError()
        }
        return reading
    }

    @Test func aDebianHostReadsWhole() throws {
        let reading = try reading()
        #expect(
            reading.system
                == SystemInfo(
                    hostName: "VM236A61A0D4D4D22", arch: "x86_64",
                    os: "Debian GNU/Linux 12 (bookworm)", kernel: "6.1.0-18-amd64",
                    cpuModel: "AMD EPYC-Milan Processor", pageSize: 4096))
        #expect(reading.uptime == 5359162.33)
        #expect(reading.load == LoadAverage(one: 0.2, five: 0.18, fifteen: 0.12, running: 1, tasks: 80))
        #expect(reading.cpu.busy == 4705 + 356 + 584 + 158 + 77)
        #expect(reading.cpu.waiting == 3699176 + 2311)
        #expect(reading.cores.count == 1)
        #expect(reading.memory.total == 996608 * 1024)
        #expect(reading.memory.used == (996608 - 565480) * 1024)
        #expect(reading.memory.swapUsed == (1048572 - 996144) * 1024)
        #expect(reading.interfaces.map(\.name) == ["lo", "eth0", "docker0"])
        #expect(reading.interfaces[1].received == 987654321)
        #expect(reading.interfaces[1].transmitted == 123456789)
        // wg0's route covers half the addresses only.
        #expect(reading.defaultRoute == "eth0")
        #expect(reading.disks?.map(\.mount) == ["/", "/boot/efi", "/mnt/My Data"])
        #expect(reading.disks?.first?.used == 3240180 * 1024)
        // Whole disks only.
        #expect(reading.diskIO?.map(\.name) == ["vda", "nvme0n1"])
        #expect(reading.diskIO?.first?.read == 800000 * 512)
        #expect(reading.diskIO?.first?.written == 400000 * 512)
        #expect(reading.tcp == TcpCounts(established: 12, timeWait: 25, inUse: 9))
        #expect(reading.users?[33] == "www-data")
        // Not the kernel thread; a name may hold spaces and parentheses.
        #expect(reading.processes?.map(\.name) == ["systemd", "php-fpm: pool (www)"])
        let php = try #require(reading.processes?.last)
        #expect((php.pid, php.uid, php.state, php.ticks, php.threads, php.rssPages) == (4242, 33, "R", 400, 4, 5000))
        #expect(reading.failedUnits == ["nginx.service", "cron.service"])
    }

    @Test func partsNotAskedForAreNotThere() throws {
        let light = """
            @@uptime
            100.5 90
            @@stat
            cpu  1 0 1 10 0 0 0 0 0 0
            @@memory
            MemTotal: 1000 kB
            MemFree: 100 kB
            Buffers: 50 kB
            Cached: 250 kB
            """
        let reading = try reading(light)
        #expect(reading.system == nil)
        #expect(reading.disks == nil)
        #expect(reading.diskIO == nil)
        #expect(reading.processes == nil)
        // Where there is no systemd, none: not 「no failed units」.
        #expect(reading.failedUnits == nil)
        // Kernels before 3.14 have no MemAvailable.
        #expect(reading.memory.used == 600 * 1024)
        #expect(reading.memory.swapTotal == 0)
    }

    @Test func aHostWithoutProcSaysWhatItIs() {
        #expect(HostReading.parse("@@unsupported\nDarwin\n") == .unsupported("Darwin"))
        // cmd.exe has nothing to say to `sh -c`.
        #expect(HostReading.parse("") == .unsupported(nil))
    }

    /// Every way a reading can be asked for.
    private var commands: [String] {
        [false, true].flatMap { system in
            [false, true].flatMap { disks in
                [false, true].map { details in
                    HostReading.command(
                        ReadingParts(system: system, disks: disks, details: details, services: details))
                }
            }
        }
    }

    @Test func theCommandsSurviveAnyLoginShell() throws {
        for command in commands {
            #expect(command.hasPrefix("sh -c '") && command.hasSuffix("'"))
            // Inside the single quotes there is nothing for the login shell.
            let script = command.dropFirst("sh -c '".count).dropLast()
            #expect(!script.contains("'"), "\(command)")
            #expect(!script.contains("!"), "\(command)")
            #expect(!script.contains("\n"), "\(command)")
        }
        let light = HostReading.command(ReadingParts())
        #expect(light.contains("@@stat") && light.contains("@@loadavg"))
        for part in ["@@host", "@@df", "@@processes", "@@failed"] {
            #expect(!light.contains(part), "\(part)")
        }
        // The load starts no process of its own.
        for program in ["cat ", "grep ", "head ", "uname -n", "df ", "systemctl"] {
            #expect(!light.contains(program), "\(program)")
        }
    }

    @Test func ratesComeFromTheReadingBefore() throws {
        var tracker = ReadingTracker()
        let start = Date()
        var first = try reading()
        let firstSnapshot = tracker.update(first, at: start, users: first.users ?? [:])
        #expect(firstSnapshot.cpu == nil)
        #expect(firstSnapshot.mainInterface?.name == "eth0")
        #expect(firstSnapshot.mainInterface?.received == nil)
        #expect(firstSnapshot.processes?.first?.cpu == nil)

        // 25 busy ticks of 100 in 2 seconds, of which 5 waiting on disks;
        // 4 KB in; php-fpm took 50 of the core's 100 ticks.
        var second = first
        second.cpu.user += 20
        second.cpu.idle += 70
        second.cpu.iowait += 5
        second.cpu.steal += 5
        second.cores = [second.cpu]
        second.interfaces[1].received += 4096
        second.diskIO?[0].written += 2 * 1024 * 1024
        second.processes?[1].ticks += 50
        let snapshot = tracker.update(second, at: start + 2, users: first.users ?? [:])
        let cpu = try #require(snapshot.cpu)
        #expect(cpu.total == 25)
        #expect(cpu.cores == [25])
        #expect(cpu.iowait == 5)
        #expect(cpu.steal == 5)
        #expect(snapshot.mainInterface?.received == 2048)
        #expect(snapshot.mainInterface?.transmitted == 0)
        #expect(snapshot.diskIO?.first == DiskRate(name: "vda", read: 0, written: 1024 * 1024))
        let busiest = try #require(snapshot.processes?.first)
        #expect(busiest.name == "php-fpm: pool (www)")
        #expect(busiest.user == "www-data")
        #expect(busiest.cpu == 50)
        #expect(busiest.memory == 5000 * 4096)

        // Long after, or across a reboot: no rates.
        first.cpu.user = 1
        #expect(tracker.update(first, at: start + 3, users: [:]).cpu == nil)
        #expect(tracker.update(second, at: start + 60, users: [:]).cpu == nil)
    }
}
