import ShellRSCore
import SwiftUI

/// What can be pushed in the settings.
enum SettingsRoute: Hashable {
    case sync
}

/// The settings: sync, and what the app is.
struct SettingsView: View {
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
                Section {
                    LabeledContent("版本", value: Self.version)
                }
            }
            .navigationTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .sync:
                    SyncView(sync: model.sync)
                }
            }
        }
    }

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
