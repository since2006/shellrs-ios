import ShellRSCore
import SwiftUI

/// What can be pushed in the settings.
enum SettingsRoute: Hashable {
    case sync
}

/// The settings: the ads, sync, and what the app is.
struct SettingsView: View {
    /// Closes them, when they are shown over a wide window rather than in
    /// a tab.
    var done: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.settingsPath) {
            Form {
                if model.ads.isAvailable {
                    AdsSection()
                }
                Section {
                    NavigationLink(value: SettingsRoute.sync) {
                        LabeledContent {
                            SyncSummary(sync: model.sync)
                        } label: {
                            Label("云同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                    }
                }
                Section("外观") {
                    Picker("模式", selection: $model.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }
                Section("终端") {
                    Stepper(
                        value: $model.fontSize, in: AppModel.fontSizes, step: 1
                    ) {
                        LabeledContent("字号") {
                            Text("\(Int(model.fontSize)) pt")
                                .monospacedDigit()
                        }
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: Self.version)
                    Link(destination: Self.source) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(verbatim: "GitHub")
                                Image(systemName: "arrow.up.right.square")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        } label: {
                            Text("源代码")
                                .foregroundStyle(Color.primary)
                        }
                    }
                    Link(destination: Self.website) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(verbatim: "shellrs.com")
                                Image(systemName: "arrow.up.right.square")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        } label: {
                            Text("官网")
                                .foregroundStyle(Color.primary)
                        }
                    }
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
                }
            }
        }
    }

    private static let website = URL(string: "https://shellrs.com")!
    private static let source = URL(string: "https://github.com/since2006/shellrs-ios")!

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// The ads: buying them away, restoring that, and changing the answer
/// given to the consent form where the law asks for one.
private struct AdsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let purchases = model.purchases
        Section {
            if purchases.configuration.isConfigured {
                if purchases.adsRemoved {
                    Label("已去除广告", systemImage: "checkmark.seal.fill")
                } else {
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        LabeledContent {
                            if let price = purchases.product?.displayPrice {
                                Text(price)
                            }
                        } label: {
                            Text("去除广告")
                        }
                    }
                    .disabled(purchases.working || purchases.adRemoval == .unknown)
                }
                Button("恢复购买") {
                    Task { await purchases.restore() }
                }
                .disabled(purchases.working)
            }
            if model.ads.privacyOptionsRequired, !purchases.adsRemoved {
                Button("广告隐私选项") {
                    Task { await model.ads.presentPrivacyOptions() }
                }
            }
            if let notice = purchases.notice {
                Text(notice).font(.footnote)
            }
        } footer: {
            Text("ShellRS 的全部功能免费，广告用来支持开发。去除广告是一次性购买，同一 Apple 账户的设备都可以恢复。")
        }
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
