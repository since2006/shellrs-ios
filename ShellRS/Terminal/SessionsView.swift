import ShellRSCore
import SwiftUI

/// The terminals open: tap one to show it, swipe to close it.
struct SessionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.sessions) { session in
                    Button {
                        model.show(session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("关闭", role: .destructive) {
                            model.close(session)
                        }
                    }
                }
                if !model.sessions.isEmpty {
                    AdSection(placement: .sessions)
                }
            }
            .overlay {
                if model.sessions.isEmpty {
                    VStack(spacing: 0) {
                        ContentUnavailableView(
                            "没有打开的终端", systemImage: "terminal",
                            description: Text("在「主机」里点一台主机连接。"))
                        // Over the plain background of an empty list.
                        AdCard(placement: .sessions, fill: Color(.secondarySystemBackground))
                            .padding()
                    }
                }
            }
            .loadsAd(.sessions)
            .navigationTitle("终端")
        }
    }
}

/// A terminal in the list: its host's mark, colored while it is online and
/// gray otherwise, as the desktop's tabs show it.
private struct SessionRow: View {
    let session: TerminalSession

    var body: some View {
        HStack(spacing: 12) {
            HostMark(host: session.host, dimmed: session.state != .connected)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.host.title)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var status: String {
        switch session.state {
        case .connecting:
            String(localized: "正在连接…")
        case .connected:
            session.latency.map { String(localized: "已连接 · \(String($0)) ms") }
                ?? String(localized: "已连接")
        case .closed(let reason):
            reason ?? String(localized: "已断开连接")
        }
    }
}
