import ShellRSCore
import SwiftUI

/// A host's details on 状态, as someone looking after it would want them at
/// a glance: how busy the CPU is and on what, the load, memory and swap,
/// each network interface and TCP, the disks filling and how hard they
/// work, the busiest processes, the services that failed, and what the
/// host is.
struct HostStatusView: View {
    let monitor: HostMonitor
    /// Closes it, when it is shown over a wide window rather than pushed.
    var done: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var processOrder = ProcessOrder.cpu
    @State private var answering = false
    @State private var showsCores = false
    @State private var showsAllProcesses = false

    enum ProcessOrder: Hashable {
        case cpu
        case memory
    }

    /// How many of the busiest processes show, until asked for more.
    private static let processesShown = 8
    private static let processesMore = 30

    var body: some View {
        List {
            header
            if case .unsupported = monitor.state {
                // Nothing more to read.
            } else if let snapshot = monitor.snapshot {
                cpu(snapshot)
                memory(snapshot)
                network(snapshot)
                disks(snapshot)
                processes(snapshot)
                services
                system(snapshot)
            } else if monitor.state == .live || monitor.state == .connecting {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(monitor.host.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: done)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openTerminal()
                } label: {
                    Label("打开终端", systemImage: "terminal")
                }
            }
        }
        .sheet(isPresented: $answering) {
            StatusPrompt(monitor: monitor) { answering = false }
        }
        .onAppear {
            model.status.pageAppeared()
            monitor.detailed = true
        }
        .onDisappear {
            monitor.detailed = false
            model.status.pageDisappeared()
        }
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack(spacing: 12) {
                HostMark(host: monitor.host, dimmed: monitor.state != .live, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.host.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    StatusLine(monitor: monitor)
                        .font(.subheadline)
                }
            }
            switch monitor.state {
            case .asking:
                Button("处理…") { answering = true }
            case .failed, .unsupported:
                Button("重新连接") { monitor.reconnect() }
            case .idle, .connecting, .live:
                EmptyView()
            }
        }
    }

    private func cpu(_ snapshot: HostSnapshot) -> some View {
        Section {
            HistoryChart(
                points: monitor.history,
                series: [.init(name: "CPU", color: .accentColor, value: { $0.cpu })],
                percent: true, format: { StatusFormat.percent($0) })
            if let cpu = snapshot.cpu {
                MeterRow(title: String(localized: "使用率"), percent: cpu.total)
                figure("用户", StatusFormat.percent(cpu.user))
                figure("系统", StatusFormat.percent(cpu.system))
                figure("I/O 等待", StatusFormat.percent(cpu.iowait), note: cpu.iowait >= 10)
                figure("虚拟机窃取", StatusFormat.percent(cpu.steal), note: cpu.steal >= 10)
            }
            if let load = snapshot.load {
                figure("负载（1、5、15 分钟）", StatusFormat.load(load),
                       note: snapshot.coreCount > 0 && load.one >= Double(snapshot.coreCount))
                if let running = load.running, let tasks = load.tasks {
                    figure("进程", String(localized: "\(String(running)) 运行 / 共 \(String(tasks))"))
                }
            }
            if let cores = snapshot.cpu?.cores, cores.count > 1 {
                DisclosureGroup(isExpanded: $showsCores) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                        MeterRow(title: String(localized: "核 \(String(index))"), percent: load)
                    }
                } label: {
                    Text("每个核")
                }
            }
        } header: {
            HStack {
                Text(verbatim: "CPU")
                Spacer()
                if snapshot.coreCount > 0 {
                    Text("\(snapshot.coreCount) 核")
                }
            }
        } footer: {
            if let cpu = snapshot.cpu, cpu.iowait >= 10 || cpu.steal >= 10 {
                Text("I/O 等待高说明磁盘跟不上；虚拟机窃取高说明宿主机超售，CPU 被别的虚拟机占用。")
            } else if let load = snapshot.load, snapshot.coreCount > 0,
                load.one >= Double(snapshot.coreCount)
            {
                Text("1 分钟负载已超过核数，有进程在排队等 CPU 或磁盘。")
            }
        }
    }

    private func memory(_ snapshot: HostSnapshot) -> some View {
        let memory = snapshot.memory
        return Section("内存") {
            HistoryChart(
                points: monitor.history,
                series: [.init(name: String(localized: "内存"), color: .accentColor, value: { $0.memory })],
                percent: true, format: { StatusFormat.percent($0) })
            MeterRow(
                title: String(localized: "物理内存"), percent: memory.percent,
                detail: "\(StatusFormat.bytes(memory.used)) / \(StatusFormat.bytes(memory.total))")
            figure("可用", StatusFormat.bytes(memory.available))
            figure("缓存", StatusFormat.bytes(memory.buffers + memory.cached))
            if memory.swapTotal > 0 {
                MeterRow(
                    title: String(localized: "交换空间"), percent: memory.swapPercent,
                    detail:
                        "\(StatusFormat.bytes(memory.swapUsed)) / \(StatusFormat.bytes(memory.swapTotal))")
            } else {
                figure("交换空间", String(localized: "未启用"))
            }
        }
    }

    private func network(_ snapshot: HostSnapshot) -> some View {
        Section {
            if let main = snapshot.mainInterface {
                HistoryChart(
                    points: monitor.history,
                    series: [
                        .init(name: String(localized: "接收"), color: .received, value: { $0.received }),
                        .init(name: String(localized: "发送"), color: .transmitted, value: { $0.transmitted }),
                    ],
                    format: { StatusFormat.rate($0) })
                Text("图表为主网卡 \(main.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let interfaces = snapshot.busyInterfaces
            if interfaces.isEmpty {
                Text("没有在用的网卡")
                    .foregroundStyle(.secondary)
            }
            ForEach(interfaces, id: \.name) { interface in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        rate(interface.received, systemImage: "arrow.down", color: .received)
                        rate(interface.transmitted, systemImage: "arrow.up", color: .transmitted)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: interface.name)
                        Text("累计 \(StatusFormat.bytes(interface.bytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let tcp = snapshot.tcp {
                if let established = tcp.established {
                    figure("TCP 已建立连接", established.formatted())
                }
                if let timeWait = tcp.timeWait {
                    figure("TIME_WAIT", timeWait.formatted())
                }
            }
        } header: {
            Text("网络")
        }
    }

    @ViewBuilder
    private func disks(_ snapshot: HostSnapshot) -> some View {
        let disks = monitor.disks ?? []
        Section("磁盘") {
            if disks.isEmpty {
                Text(monitor.disks == nil ? String(localized: "正在读取…") : String(localized: "没有读到磁盘"))
                    .foregroundStyle(.secondary)
            }
            ForEach(disks, id: \.mount) { disk in
                MeterRow(
                    title: disk.mount, percent: disk.percent,
                    detail: "\(StatusFormat.size(disk.used)) / \(StatusFormat.size(disk.used + disk.available))")
            }
            ForEach(snapshot.diskIO ?? [], id: \.name) { disk in
                LabeledContent {
                    Text("读 \(StatusFormat.rate(disk.read))  写 \(StatusFormat.rate(disk.written))")
                        .monospacedDigit()
                } label: {
                    Text(verbatim: disk.name)
                }
            }
        }
    }

    @ViewBuilder
    private func processes(_ snapshot: HostSnapshot) -> some View {
        if let processes = snapshot.processes {
            let sorted =
                processOrder == .cpu
                ? processes
                : processes.sorted { $0.memory > $1.memory }
            Section {
                Picker("排列方式", selection: $processOrder) {
                    Text(verbatim: "CPU").tag(ProcessOrder.cpu)
                    Text("内存").tag(ProcessOrder.memory)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                ForEach(sorted.prefix(showsAllProcesses ? Self.processesMore : Self.processesShown)) {
                    process in
                    ProcessRow(process: process)
                }
                if processes.count > Self.processesShown {
                    Button(showsAllProcesses ? String(localized: "收起") : String(localized: "显示更多")) {
                        showsAllProcesses.toggle()
                    }
                }
            } header: {
                HStack {
                    Text("进程")
                    Spacer()
                    Text("共 \(processes.count) 个")
                }
            } footer: {
                Text("CPU 按单个核计，多线程的进程可以超过一个核；内存为常驻内存。")
            }
        }
    }

    @ViewBuilder
    private var services: some View {
        if let failed = monitor.failedUnits {
            Section("服务") {
                if failed.isEmpty {
                    Label("没有失败的服务", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(failed, id: \.self) { unit in
                        Label {
                            Text(verbatim: unit)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private func system(_ snapshot: HostSnapshot) -> some View {
        Section("系统") {
            if let system = monitor.system {
                figure("主机名", system.hostName)
                figure("系统", system.os)
                if !system.kernel.isEmpty {
                    figure("内核", system.kernel)
                }
                figure("架构", system.arch)
                if !system.cpuModel.isEmpty {
                    figure("CPU 型号", system.cpuModel)
                }
            }
            if let uptime = snapshot.uptime {
                figure("运行时长", StatusFormat.uptime(uptime))
            }
            figure("地址", monitor.host.subtitle)
        }
    }

    // MARK: Parts

    /// A figure's row: its name, the value, and a mark when it is worth a
    /// second look.
    private func figure(_ title: LocalizedStringKey, _ value: String, note: Bool = false) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                if note {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Text(verbatim: value)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        } label: {
            Text(title)
        }
    }

    private func rate(_ value: Double?, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .imageScale(.small)
            Text(verbatim: StatusFormat.rate(value))
                .monospacedDigit()
        }
    }

    private func openTerminal() {
        do {
            done?()
            try model.connect(monitor.host)
        } catch {
            model.hostListState.failure = Describe.store(error)
        }
    }
}

/// A process as the detail page lists it: its name, who runs it, and what
/// it takes.
private struct ProcessRow: View {
    let process: ProcessLoad

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: process.name)
                    .lineLimit(1)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: process.cpu.map(StatusFormat.percent) ?? "—")
                    .foregroundStyle(Severity(percent: process.cpu ?? 0) == .normal ? Color.primary : .orange)
                Text(verbatim: StatusFormat.bytes(process.memory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }

    /// 「PID 4242 · www-data · 4 线程」, and the state when it is one worth
    /// knowing.
    private var details: String {
        var parts = ["PID \(process.pid)", process.user]
        if process.threads > 1 {
            parts.append(String(localized: "\(process.threads) 线程"))
        }
        switch process.state {
        case "D": parts.append(String(localized: "等待磁盘"))
        case "Z": parts.append(String(localized: "僵尸进程"))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

extension Describe {
    /// Why 状态 reads nothing of a host, in the desktop's words.
    static func unsupportedSystem(_ system: String?) -> String {
        if let system {
            String(localized: "暂不支持 \(system) 的监控，目前只支持 Linux 主机。")
        } else {
            String(localized: "暂不支持这台主机的监控，目前只支持 Linux 主机。")
        }
    }
}
