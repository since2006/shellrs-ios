import ShellRSCore
import SwiftUI

/// The saved hosts: tap one to connect, swipe to edit or delete.
struct HostListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: HostEditor.Subject?
    @State private var deleting: Host?
    @State private var failure: String?

    var body: some View {
        @Bindable var hosts = model.hosts
        NavigationStack {
            List {
                ForEach(hosts.hosts, id: \.id) { host in
                    Button {
                        model.connect(host)
                    } label: {
                        HostRow(host: host)
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            deleting = host
                        }
                        Button("编辑") {
                            editing = .edit(host)
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button("编辑", systemImage: "pencil") {
                            editing = .edit(host)
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            deleting = host
                        }
                    }
                }
            }
            .overlay {
                if hosts.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("还没有主机", systemImage: "server.rack")
                    } description: {
                        Text("新建一台主机，或在设置里加入电脑上的云同步。")
                    } actions: {
                        Button("新建主机") {
                            editing = .new
                        }
                    }
                }
            }
            .navigationTitle("主机")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新建主机", systemImage: "plus") {
                        editing = .new
                    }
                }
            }
            .sheet(item: $editing) { subject in
                HostEditor(subject: subject)
            }
            .confirmationDialog(
                deleting.map { String(localized: "删除「\($0.title)」？") } ?? "",
                isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { host in
                Button("删除", role: .destructive) {
                    do {
                        try hosts.delete(host)
                    } catch {
                        failure = Describe.store(error)
                    }
                }
            } message: { _ in
                Text("已打开的终端不受影响。")
            }
            .alert(
                "出错了", isPresented: Binding(
                    get: { failure != nil || hosts.problem != nil },
                    set: { if !$0 { failure = nil; hosts.problem = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(failure ?? hosts.problem ?? "")
            }
        }
    }
}

/// A host in the list: its mark, name and where it is.
struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 12) {
            HostMark(host: host)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.title)
                    .font(.body)
                    .lineLimit(1)
                Text(host.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The host's colored mark: its system's brand color once it is known,
/// else the color its address picks. Always in color; gray is for offline.
struct HostMark: View {
    let host: Host
    var dimmed = false

    var body: some View {
        let background = Color(rgb: host.os?.brandColor ?? host.markColor)
        let foreground = host.os?.brandForeground.map { Color(rgb: $0) } ?? .white
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(dimmed ? Color.gray : background)
            .frame(width: 36, height: 36)
            .overlay {
                Text(initial)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .white : foreground)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let letter = (host.os?.name ?? host.title).first.map(String.init) ?? "?"
        return letter.uppercased()
    }
}

extension Color {
    /// A color as the core gives it: 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255)
    }
}
