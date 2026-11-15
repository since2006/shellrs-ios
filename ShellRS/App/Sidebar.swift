import ShellRSCore
import SwiftUI

/// The sidebar of a wide window: its pages, as an admin console's menu,
/// and what sync waits for below them.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(
            selection: Binding(
                get: { model.tab },
                set: { if let tab = $0 { model.tab = tab } })
        ) {
            Label("状态", systemImage: "gauge.with.dots.needle.50percent")
                .tag(AppTab.status)
            Label("主机", systemImage: "server.rack")
                .tag(AppTab.hosts)
            Label("终端", systemImage: "terminal")
                .badge(model.sessions.count)
                .tag(AppTab.terminals)
            Label("凭据", systemImage: "key")
                .tag(AppTab.credentials)
            Label("设置", systemImage: model.sync.attention == nil ? "gear" : "gear.badge")
                .symbolRenderingMode(.multicolor)
                .tag(AppTab.settings)
        }
        .navigationTitle(Text(verbatim: "ShellRS"))
        .safeAreaInset(edge: .bottom) {
            if let attention = model.sync.attention {
                SyncBanner(attention: attention)
            }
        }
    }
}

/// What sync waits for the user to settle, where a narrow window would
/// alert: a wide one usually has a terminal open, typed into.
private struct SyncBanner: View {
    let attention: Attention
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(Describe.attention(attention))
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            Button("处理…") {
                model.reviewSync()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
