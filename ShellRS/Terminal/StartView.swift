import ShellRSCore
import SwiftUI

/// What a wide window shows with no terminal open: the hosts connected
/// lately, as the desktop's start page.
struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var failure: String?

    /// How many of the latest connected it shows.
    private static let recentShown = 6

    var body: some View {
        let recent = model.hosts.recent.prefix(Self.recentShown)
        Group {
            if recent.isEmpty {
                ContentUnavailableView(
                    "没有打开的终端", systemImage: "terminal",
                    description: Text("在左边点一台主机连接。"))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近连接")
                            .font(.title2.bold())
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12
                        ) {
                            ForEach(recent, id: \.id) { host in
                                Button {
                                    connect(host)
                                } label: {
                                    HostRow(host: host)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(
                                            Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .hoverEffect()
                            }
                        }
                        Text("在左边点一台主机连接。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .alert(
            "出错了", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func connect(_ host: Host) {
        do {
            try model.connect(host)
        } catch {
            failure = Describe.store(error)
        }
    }
}
