import ShellRSCore
import SwiftUI

/// The app's tabs, with the terminal shown over them.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            HostListView()
                .tabItem { Label("主机", systemImage: "server.rack") }
                .tag(AppTab.hosts)
            SessionsView()
                .tabItem { Label("终端", systemImage: "terminal") }
                .badge(model.sessions.count)
                .tag(AppTab.terminals)
            CredentialListView()
                .tabItem { Label("凭据", systemImage: "key") }
                .tag(AppTab.credentials)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
                .badge(model.sync.attention == nil ? 0 : 1)
                .tag(AppTab.settings)
        }
        .fullScreenCover(item: $model.shownSession) { session in
            TerminalScreen(session: session)
                .environment(model)
        }
        .alert(
            "同步",
            isPresented: Binding(
                get: {
                    model.sync.notice != nil && !model.sync.pageShown
                        && model.shownSession == nil
                },
                set: { if !$0 { model.sync.notice = nil } }),
            presenting: model.sync.notice
        ) { _ in
            Button("处理…") {
                model.reviewSync()
            }
            Button("稍后", role: .cancel) {}
        } message: { attention in
            Text(Describe.attention(attention))
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                model.cameForward()
            case .background:
                model.sync.goingToBackground()
            default:
                break
            }
        }
    }
}
