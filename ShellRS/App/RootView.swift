import SwiftUI

/// The app's tabs, with the terminal shown over them.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            HostListView()
                .tabItem { Label("主机", systemImage: "server.rack") }
            SessionsView()
                .tabItem { Label("终端", systemImage: "terminal") }
                .badge(model.sessions.count)
            CredentialListView()
                .tabItem { Label("凭据", systemImage: "key") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .fullScreenCover(item: $model.shownSession) { session in
            TerminalScreen(session: session)
                .environment(model)
        }
    }
}

/// Settings come with sync; for now, what the app is.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("版本", value: Self.version)
                }
            }
            .navigationTitle("设置")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
