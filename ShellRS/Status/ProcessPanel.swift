import SwiftUI

/// A host's processes, over the 状态 list or a host's details: a popover
/// where there is room, a sheet on a phone. A table whose CPU and 内存
/// headings choose which column sorts it, biggest first. While it shows,
/// the readings take the processes.
struct ProcessPanel: View {
    let monitor: HostMonitor

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var order = Order.cpu

    enum Order: Hashable {
        case cpu
        case memory
    }

    /// The figures' columns: as wide as 「157.1%」 and 「5.96 GB」.
    static let cpuWidth: CGFloat = 64
    static let memoryWidth: CGFloat = 76

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("进程")
                                .font(.headline)
                            Text(verbatim: subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        // Not the colour of what presents it: a card's row is a button,
        // which colours what it holds with the tint.
        .foregroundStyle(Color.primary)
        .frame(minWidth: 320, idealWidth: 420, minHeight: 360, idealHeight: 560)
        .presentationDetents([.medium, .large])
        .onAppear {
            model.status.pageAppeared()
            monitor.showDetails()
        }
        .onDisappear {
            monitor.hideDetails()
            model.status.pageDisappeared()
        }
    }

    /// 「web-01 · 共 268 个」.
    private var subtitle: String {
        guard let count = monitor.snapshot?.processes?.count else {
            return monitor.host.title
        }
        return "\(monitor.host.title) · \(String(localized: "共 \(count) 个"))"
    }

    @ViewBuilder
    private var content: some View {
        if let processes = monitor.snapshot?.processes {
            // They come by CPU.
            let sorted =
                order == .cpu
                ? processes
                : processes.sorted { ($0.memory, $0.cpu ?? 0) > ($1.memory, $1.cpu ?? 0) }
            List {
                Section {
                    ForEach(sorted) { process in
                        ProcessRow(process: process, order: order)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    header
                } footer: {
                    Text("CPU 按单个核计，多线程的进程可以超过一个核；内存为常驻内存。")
                }
            }
            .listStyle(.plain)
        } else if monitor.state == .live || monitor.state == .connecting {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("读不到进程", systemImage: "list.bullet.rectangle")
            } description: {
                StatusLine(monitor: monitor)
            }
        }
    }

    /// The table's headings, staying at the top as it scrolls.
    private var header: some View {
        HStack(spacing: 8) {
            Text("名称")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            sort(.cpu, Text(verbatim: "CPU"))
                .frame(width: Self.cpuWidth, alignment: .trailing)
            sort(.memory, Text("内存"))
                .frame(width: Self.memoryWidth, alignment: .trailing)
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }

    /// A heading that sorts by its column: the one sorting in the tint,
    /// with its arrow.
    private func sort(_ column: Order, _ title: Text) -> some View {
        let active = order == column
        return Button {
            order = column
        } label: {
            HStack(spacing: 2) {
                title
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(active ? 1 : 0)
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityHint(Text("按此列从大到小排列"))
    }
}

/// A process in the table: its name and who runs it, then what it takes,
/// the column sorting by stronger.
private struct ProcessRow: View {
    let process: ProcessLoad
    let order: ProcessPanel.Order

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: process.name)
                    .lineLimit(1)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            figure(process.cpu.map(StatusFormat.percent) ?? "—", sorting: order == .cpu)
                .frame(width: ProcessPanel.cpuWidth, alignment: .trailing)
            figure(StatusFormat.bytes(process.memory), sorting: order == .memory)
                .frame(width: ProcessPanel.memoryWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, sorting: Bool) -> some View {
        Text(verbatim: value)
            .font(.subheadline.weight(sorting ? .semibold : .regular))
            .foregroundStyle(sorting ? Color.primary : Color.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
