import ShellRSCore
import SwiftUI

/// What 状态 pushes in a narrow window.
enum StatusRoute: Hashable {
    /// A host's details, by its public id.
    case host(String)
}

/// The 状态 tab of a narrow window: the list in a stack of its own, a
/// host's details pushed over it.
struct StatusTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.statusPath) {
            StatusList()
                .navigationDestination(for: StatusRoute.self) { route in
                    switch route {
                    case .host(let id):
                        if let host = model.status.shownHosts.first(where: { $0.publicId == id }) {
                            HostStatusView(monitor: model.status.monitor(for: host))
                        } else {
                            ContentUnavailableView(
                                "这台主机已不在状态页", systemImage: "server.rack")
                        }
                    }
                }
        }
    }
}

/// The hosts chosen for 状态, each with its load: tap one for its
/// details. Its container gives it the navigation bar: the 状态 tab or the
/// sidebar.
struct StatusList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.wideWindow) private var wide
    @State private var choosing = false
    @State private var answering: HostMonitor?

    var body: some View {
        let status = model.status
        let hosts = status.shownHosts
        List {
            ForEach(hosts, id: \.publicId) { host in
                let monitor = status.monitor(for: host)
                row(for: monitor)
                    .swipeActions {
                        Button("移除") {
                            status.setShown(false, for: host)
                        }
                        .tint(.gray)
                    }
                    .contextMenu {
                        Button("连接", systemImage: "terminal") {
                            connect(host)
                        }
                        Button("重新读取", systemImage: "arrow.clockwise") {
                            monitor.reconnect()
                        }
                        Divider()
                        Button("不在状态页显示", systemImage: "eye.slash") {
                            status.setShown(false, for: host)
                        }
                    }
            }
        }
        .overlay {
            if hosts.isEmpty {
                ContentUnavailableView {
                    Label("还没有要显示的主机", systemImage: "gauge.with.dots.needle.50percent")
                } description: {
                    Text(
                        status.candidates.isEmpty
                            ? String(localized: "先在「主机」页新建一台 SSH 主机。")
                            : String(localized: "选择主机后，这里显示它们的 CPU、内存、网络和磁盘。目前只支持 Linux 主机。"))
                } actions: {
                    if !status.candidates.isEmpty {
                        Button("选择主机") {
                            choosing = true
                        }
                    }
                }
            }
        }
        .navigationTitle("状态")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !status.candidates.isEmpty {
                    Button {
                        choosing = true
                    } label: {
                        Label("选择主机", systemImage: "checklist")
                    }
                }
            }
        }
        .sheet(isPresented: $choosing) {
            StatusHostPicker()
                .environment(model)
        }
        .sheet(item: $answering) { monitor in
            StatusPrompt(monitor: monitor) { answering = nil }
        }
        .onAppear { status.pageAppeared() }
        .onDisappear { status.pageDisappeared() }
    }

    @ViewBuilder
    /// Each a button, its card in the text's colour rather than the
    /// button's tint (which the card sets): not `.tint(.primary)`, which
    /// what the card presents would take too.
    private func row(for monitor: HostMonitor) -> some View {
        if monitor.isAsking {
            // The login waits: answer before anything else.
            Button {
                answering = monitor
            } label: {
                HostStatusCard(monitor: monitor)
            }
        } else if wide {
            Button {
                model.sheet = .hostStatus(monitor.id)
            } label: {
                HostStatusCard(monitor: monitor)
            }
        } else {
            // A button, not a link: the card's own buttons take the place
            // of the link's chevron.
            Button {
                model.statusPath.append(.host(monitor.id))
            } label: {
                HostStatusCard(monitor: monitor)
            }
        }
    }

    private func connect(_ host: Host) {
        do {
            try model.connect(host)
        } catch {
            model.hostListState.failure = Describe.store(error)
        }
    }
}

/// A host on 状态: its mark and name, how it is doing, its processes and a
/// terminal a tap away, its CPU (or its load), memory and main disk as
/// rings, and beside them its network.
struct HostStatusCard: View {
    let monitor: HostMonitor
    @Environment(AppModel.self) private var model
    /// The load's three rings in the CPU's place, on every card: a tap on
    /// either swaps them, and it stays so.
    @AppStorage("statusShowsLoad") private var showsLoad = false
    /// The swap's ring in the memory's, so too: where there is swap.
    @AppStorage("statusShowsSwap") private var showsSwap = false
    /// How busy the disks are in the place of how full the main one is.
    @AppStorage("statusShowsDiskBusy") private var showsDiskBusy = false
    @State private var showsProcesses = false
    /// Too narrow for the buttons beside the name, as in a sidebar: they go
    /// at the bottom, with the load.
    @State private var narrow = false

    private nonisolated static let narrowWidth: CGFloat = 280

    /// How a card lays out its figures, the first that fits: the network
    /// beside the rings or under them, the rings as far apart as fits. The
    /// same on every card in a list, which all make room for three rings.
    private enum Arrangement: Hashable {
        case beside(gap: CGFloat)
        case under(gap: CGFloat)
    }

    private static let arrangements: [Arrangement] =
        [22, 14, 8].map(Arrangement.beside) + [22, 14, 10, 6, 2].map(Arrangement.under)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HostMark(host: monitor.host, dimmed: dimmed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.host.title)
                        .font(.headline)
                        .lineLimit(1)
                    StatusLine(monitor: monitor)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if !narrow {
                    actions
                }
            }
            if let snapshot = monitor.snapshot, !hidesFigures {
                // One list of the arrangements: `ViewThatFits` takes the
                // ids of both kinds together, and needs each its own.
                ViewThatFits(in: .horizontal) {
                    ForEach(Self.arrangements, id: \.self) { arrangement in
                        switch arrangement {
                        case .beside(let gap):
                            HStack(alignment: .center, spacing: 12) {
                                rings(snapshot, gap: gap)
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 4) {
                                    network(snapshot, axis: .vertical)
                                    load(snapshot)
                                }
                                .fixedSize()
                            }
                        case .under(let gap):
                            // The load under the rates, not beside them: a
                            // line of both is wider than a sidebar, and would
                            // count against the rings' gap.
                            VStack(alignment: .leading, spacing: 10) {
                                rings(snapshot, gap: gap)
                                VStack(alignment: .leading, spacing: 4) {
                                    network(snapshot, axis: .horizontal)
                                    if !narrow {
                                        load(snapshot)
                                    }
                                }
                            }
                        }
                    }
                }
                .opacity(dimmed ? 0.5 : 1)
            }
            if narrow {
                HStack(spacing: 8) {
                    if let snapshot = monitor.snapshot, !hidesFigures {
                        load(snapshot)
                            .opacity(dimmed ? 0.5 : 1)
                    }
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(.vertical, 4)
        // The colour itself: the row's button colours its label with the
        // tint, and `.primary` would be the tint's.
        .foregroundStyle(Color.primary)
        .onGeometryChange(for: Bool.self) { $0.size.width < Self.narrowWidth } action: {
            narrow = $0
        }
        .sensoryFeedback(.selection, trigger: [showsLoad, showsSwap, showsDiskBusy])
    }

    /// The host's processes in a panel, and a terminal on it.
    private var actions: some View {
        HStack(spacing: 4) {
            CardButton(title: "查看进程", systemImage: "list.bullet.rectangle") {
                showsProcesses = true
            }
            // Nothing to read on a host not connected, or not Linux.
            .disabled(monitor.state != .live)
            .popover(isPresented: $showsProcesses) {
                ProcessPanel(monitor: monitor)
                    .environment(model)
            }
            CardButton(title: "打开终端", systemImage: "terminal") {
                do {
                    try model.connect(monitor.host)
                } catch {
                    model.hostListState.failure = Describe.store(error)
                }
            }
        }
    }

    /// The rings `gap` apart, taking the room of three so that every card
    /// in the list chooses the same gap and its rings line up with the
    /// others'.
    private func rings(_ snapshot: HostSnapshot, gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            flipping($showsLoad, hints: (Text("轻点改为显示负载"), Text("轻点改为显示 CPU"))) {
                RingTile(title: "CPU", percent: snapshot.cpu?.total, swaps: true)
            } back: {
                LoadTile(load: snapshot.load, cores: snapshot.coreCount, swaps: true)
            }
            let memory = snapshot.memory
            if memory.swapTotal > 0 {
                flipping($showsSwap, hints: (Text("轻点改为显示交换空间"), Text("轻点改为显示内存"))) {
                    RingTile(title: String(localized: "内存"), percent: memory.percent, swaps: true)
                } back: {
                    RingTile(title: String(localized: "交换"), percent: memory.swapPercent, swaps: true)
                }
            } else {
                // No swap to show: the memory alone, a tap on it the card's.
                RingTile(title: String(localized: "内存"), percent: memory.percent)
            }
            if let disk = mainDisk {
                let title = String(localized: "磁盘 \(disk.mount)")
                if snapshot.diskIO != nil {
                    flipping(
                        $showsDiskBusy, hints: (Text("轻点改为显示磁盘繁忙程度"), Text("轻点改为显示磁盘空间"))
                    ) {
                        RingTile(title: title, percent: disk.percent, swaps: true)
                    } back: {
                        // The busiest disk's: on most hosts, the one there is.
                        RingTile(title: "I/O", percent: snapshot.diskBusy, swaps: true)
                    }
                } else {
                    RingTile(title: title, percent: disk.percent)
                }
            }
        }
        .frame(width: 3 * 56 + 2 * gap, alignment: .leading)
    }

    /// A ring that turns over to another on a tap, like a card: every
    /// card's together, each with its own animation, whichever was tapped.
    /// The hints say what a tap shows: the back's, then the front's.
    private func flipping<Front: View, Back: View>(
        _ showsBack: Binding<Bool>, hints: (back: Text, front: Text),
        @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back
    ) -> some View {
        Button {
            showsBack.wrappedValue.toggle()
        } label: {
            Flip(showsBack: showsBack.wrappedValue, front: front, back: back)
                .animation(.easeInOut(duration: 0.5), value: showsBack.wrappedValue)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityHint(showsBack.wrappedValue ? hints.front : hints.back)
    }

    /// Not connected now: what was read last is no longer the host's.
    private var dimmed: Bool {
        monitor.state != .live
    }

    /// The figures say nothing about a host that is not Linux, or never got in.
    private var hidesFigures: Bool {
        switch monitor.state {
        case .unsupported: true
        default: false
        }
    }

    /// `/`, or the biggest disk where there is none.
    private var mainDisk: DiskUsage? {
        let disks = monitor.disks ?? []
        return disks.first { $0.mount == "/" } ?? disks.max { $0.total < $1.total }
    }

    /// The main interface's rates, down over up beside the rings, side by
    /// side under them.
    @ViewBuilder
    private func network(_ snapshot: HostSnapshot, axis: Axis) -> some View {
        if let interface = snapshot.mainInterface {
            let layout = axis == .vertical
                ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                rate(interface.received, systemImage: "arrow.down", color: .received)
                rate(interface.transmitted, systemImage: "arrow.up", color: .transmitted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    "接收 \(StatusFormat.rate(interface.received))，发送 \(StatusFormat.rate(interface.transmitted))"
                ))
        }
    }

    /// 「↓ 10.7 M/s」, the unit smaller and fainter. As wide whatever the
    /// rate, its figure right-aligned and its unit left: a rate going from
    /// 2 K/s to 900 B/s moves nothing, and never wraps.
    private func rate(_ value: Double?, systemImage: String, color: Color) -> some View {
        let rate = StatusFormat.compactRate(value)
        return HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ZStack(alignment: .trailing) {
                    Text(verbatim: "00.0").hidden()
                    Text(verbatim: rate.number)
                }
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                ZStack(alignment: .leading) {
                    ForEach(StatusFormat.rateUnits, id: \.self) { unit in
                        Text(verbatim: unit).hidden()
                    }
                    Text(verbatim: rate.unit)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// The last minute's load: the five and fifteen are on the details.
    /// There with the load's rings too, so that turning them over moves
    /// nothing else.
    @ViewBuilder
    private func load(_ snapshot: HostSnapshot) -> some View {
        if let load = snapshot.load {
            Text("负载 \(StatusFormat.load(load.one))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// One of a card's buttons: an icon in the tint, faint when it cannot be
/// used, a finger's room around it.
private struct CardButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

/// An icon and its text close together, for figures in a row.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

/// How a host on 状态 is doing, in a line: connected and how quickly, or
/// why not.
struct StatusLine: View {
    let monitor: HostMonitor

    var body: some View {
        switch monitor.state {
        case .idle, .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在连接…")
            }
            .foregroundStyle(.secondary)
        case .asking(let prompt):
            Label(Self.asking(prompt), systemImage: "key.fill")
                .foregroundStyle(.orange)
        case .live:
            if let problem = monitor.readingProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // Until the CPU is in, which takes a second reading (the
                    // network's speeds too): what the card has is half of it.
                    LiveDot(reading: monitor.snapshot?.cpu == nil)
                        // Its middle about the middle of the text's first line.
                        .alignmentGuide(.firstTextBaseline) { $0.height + 1 }
                    // On one line where it fits, else the uptime on a line
                    // of its own: never broken in the middle of it.
                    ViewThatFits(in: .horizontal) {
                        Text(([connection] + uptime).joined(separator: " · "))
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(connection)
                                .lineLimit(1)
                            ForEach(uptime, id: \.self) { uptime in
                                Text(uptime)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        case .unsupported(let system):
            Text(Describe.unsupportedSystem(system))
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    /// 「在线 · 23 ms」.
    private var connection: String {
        var parts = [String(localized: "在线")]
        if let latency = monitor.latency {
            parts.append(String(localized: "\(String(latency)) ms"))
        }
        return parts.joined(separator: " · ")
    }

    /// 「运行 62d 3h」, once read.
    private var uptime: [String] {
        guard let uptime = monitor.snapshot?.uptime else {
            return []
        }
        return [String(localized: "运行 \(StatusFormat.shortUptime(uptime))")]
    }

    static func asking(_ prompt: Prompt) -> String {
        switch prompt.kind {
        case .unknownHost:
            String(localized: "首次连接，轻点确认主机密钥")
        case .hostKeyChanged:
            String(localized: "主机密钥已变更，轻点查看")
        case .password, .keyboardInteractive:
            String(localized: "需要登录，轻点输入密码")
        case .passphrase:
            String(localized: "需要私钥口令，轻点输入")
        }
    }
}

/// The dot before 「在线」: green once the readings are in, orange and
/// breathing while they are on their way.
private struct LiveDot: View {
    let reading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reading {
            dot(.orange)
                .phaseAnimator([false, true]) { dot, faint in
                    dot
                        .opacity(faint ? 0.25 : 1)
                        .scaleEffect(faint && !reduceMotion ? 0.7 : 1)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
                .accessibilityLabel(Text("正在读取…"))
        } else {
            dot(.green)
                .accessibilityHidden(true)
        }
    }

    private func dot(_ color: Color) -> some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(color)
    }
}

/// What a host's login asks, for 状态: answered here, it goes on reading.
struct StatusPrompt: View {
    let monitor: HostMonitor
    let done: () -> Void

    var body: some View {
        if case .asking(let prompt) = monitor.state {
            PromptSheet(prompt: prompt) { reply in
                monitor.answer(reply)
                done()
            }
            .id(prompt.id)
        } else {
            // Answered or gone meanwhile.
            Color.clear
                .onAppear(perform: done)
        }
    }
}

/// Which hosts 状态 shows: this device's own choice.
struct StatusHostPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let status = model.status
        let hosts = status.candidates.filter { $0.matches(query) }
        NavigationStack {
            List {
                Section {
                    ForEach(hosts, id: \.id) { host in
                        Button {
                            status.setShown(!status.isShown(host), for: host)
                        } label: {
                            HStack {
                                HostRow(host: host)
                                Spacer()
                                if status.isShown(host) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityAddTraits(status.isShown(host) ? .isSelected : [])
                    }
                } footer: {
                    Text("在状态页查看所选主机的 CPU、内存、网络和磁盘，只支持 Linux 主机。选择只保存在这台设备上。")
                }
            }
            .searchable(text: $query, prompt: "搜索主机")
            .overlay {
                if hosts.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("选择主机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
