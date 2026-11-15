import ShellRSCore
import SwiftUI

/// A host's details on 状态, as someone looking after it would want them at
/// a glance: how busy the CPU is and on what, the load, memory and swap,
/// each network interface and TCP, the disks filling and how hard they
/// work, the services that failed, and what the host is. The processes are
/// a panel of their own, from the toolbar.
struct HostStatusView: View {
    let monitor: HostMonitor
    /// Closes it, when it is shown over a wide window rather than pushed.
    var done: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var answering = false
    @State private var showsProcesses = false

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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsProcesses = true
                } label: {
                    Label("查看进程", systemImage: "list.bullet.rectangle")
                }
                .disabled(monitor.state != .live)
                .popover(isPresented: $showsProcesses) {
                    ProcessPanel(monitor: monitor)
                        .environment(model)
                }
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
            monitor.showDetails()
        }
        .onDisappear {
            monitor.hideDetails()
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
            if let cpu = snapshot.cpu {
                hero(percent: cpu.total) {
                    GridRow {
                        StatTile(title: "用户", value: StatusFormat.percent(cpu.user))
                        StatTile(title: "系统", value: StatusFormat.percent(cpu.system))
                    }
                    GridRow {
                        StatTile(
                            title: "I/O 等待", value: StatusFormat.percent(cpu.iowait),
                            note: cpu.iowait >= 10)
                        StatTile(
                            title: "虚拟机窃取", value: StatusFormat.percent(cpu.steal),
                            note: cpu.steal >= 10)
                    }
                }
            }
            HistoryChart(
                points: monitor.history,
                series: [.init(name: "CPU", color: .accentColor, value: { $0.cpu })],
                percent: true, format: { StatusFormat.percent($0) })
            if let load = snapshot.load {
                loadAverage(load, cores: snapshot.coreCount)
                if let running = load.running, let tasks = load.tasks {
                    figure("进程", String(localized: "\(String(running)) 运行 / 共 \(String(tasks))"))
                }
            }
            if let cores = snapshot.cpu?.cores, cores.count > 1 {
                CoreBars(cores: cores)
                    .padding(.vertical, 4)
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
            hero(percent: memory.percent) {
                GridRow {
                    StatTile(title: "已用", value: StatusFormat.bytes(memory.used))
                    StatTile(title: "总共", value: StatusFormat.bytes(memory.total))
                }
                GridRow {
                    StatTile(title: "可用", value: StatusFormat.bytes(memory.available))
                    StatTile(title: "缓存", value: StatusFormat.bytes(memory.buffers + memory.cached))
                }
            }
            HistoryChart(
                points: monitor.history,
                series: [.init(name: String(localized: "内存"), color: .accentColor, value: { $0.memory })],
                percent: true, format: { StatusFormat.percent($0) })
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
            if let tcp = snapshot.tcp, tcp.established != nil || tcp.timeWait != nil {
                Grid(alignment: .leading, horizontalSpacing: 16) {
                    GridRow {
                        StatTile(title: "TCP 已建立", value: tcp.established?.formatted() ?? "—")
                        StatTile(title: "TIME_WAIT", value: tcp.timeWait?.formatted() ?? "—")
                    }
                }
                .padding(.vertical, 2)
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
                    HStack(spacing: 12) {
                        Label {
                            Text(verbatim: StatusFormat.rate(disk.read))
                        } icon: {
                            Text("读")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Label {
                            Text(verbatim: StatusFormat.rate(disk.written))
                        } icon: {
                            Text("写")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .labelStyle(CompactLabelStyle())
                    .monospacedDigit()
                } label: {
                    Label {
                        // How busy, as the card's I/O ring has the busiest.
                        HStack(spacing: 6) {
                            Text(verbatim: disk.name)
                            if let busy = disk.busy {
                                let severity = Severity(percent: busy)
                                Text("繁忙 \(StatusFormat.percent(busy))")
                                    .font(.caption)
                                    .foregroundStyle(severity == .normal ? Color.secondary : severity.color)
                                    .monospacedDigit()
                            }
                        }
                    } icon: {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(.secondary)
                    }
                }
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

    /// What a section leads with, as the desktop's 系统监控 does: the share
    /// as a ring, and its parts as tiles beside it.
    private func hero(percent: Double?, @ViewBuilder tiles: () -> some View) -> some View {
        HStack(spacing: 20) {
            RingGauge(percent: percent, diameter: 84, lineWidth: 9)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                tiles()
            }
        }
        .padding(.vertical, 6)
    }

    /// The load over the last one, five and fifteen minutes, marked where
    /// it is more than the cores can take.
    private func loadAverage(_ load: LoadAverage, cores: Int) -> some View {
        let over = { (value: Double) in cores > 0 && value >= Double(cores) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("负载")
                .font(.subheadline)
            Grid(alignment: .leading, horizontalSpacing: 16) {
                GridRow {
                    StatTile(title: "1 分钟", value: StatusFormat.load(load.one), note: over(load.one))
                    StatTile(title: "5 分钟", value: StatusFormat.load(load.five), note: over(load.five))
                    StatTile(title: "15 分钟", value: StatusFormat.load(load.fifteen), note: over(load.fifteen))
                }
            }
        }
        .padding(.vertical, 2)
    }

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
