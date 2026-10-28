import ShellRSCore
import SwiftUI

/// What can be pushed in the settings.
enum SettingsRoute: Hashable {
    case sync
    case licenses
}

/// The settings: sync, and what the app is.
struct SettingsView: View {
    /// Closes them, when they are shown over a wide window rather than in
    /// a tab.
    var done: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.settingsPath) {
            Form {
                Section {
                    NavigationLink(value: SettingsRoute.sync) {
                        LabeledContent {
                            SyncSummary(sync: model.sync)
                        } label: {
                            Label("云同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: Self.version)
                    Link(destination: Self.website) {
                        LabeledContent {
                            Text(verbatim: "shellrs.com")
                        } label: {
                            Text("官网")
                                .foregroundStyle(Color.primary)
                        }
                    }
                    NavigationLink("开源许可", value: SettingsRoute.licenses)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                if let done {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: done)
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .sync:
                    SyncView(sync: model.sync)
                case .licenses:
                    LicensesView()
                }
            }
        }
    }

    private static let website = URL(string: "https://shellrs.com")!

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Sync in a word, beside its row.
private struct SyncSummary: View {
    let sync: SyncModel

    var body: some View {
        if sync.attention != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("需要处理"))
        } else if sync.location == nil {
            Text("未开启")
        } else if sync.syncing {
            Text("正在同步…")
        } else if case .failed = sync.phase {
            Text("未能同步")
                .foregroundStyle(.red)
        } else {
            Text("已开启")
        }
    }
}
