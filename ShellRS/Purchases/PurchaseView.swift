import SwiftUI

struct PurchaseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            PurchaseContent(purchases: model.purchases)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { model.purchases.presentationRequested = false }
                    }
                }
        }
    }
}

/// Shared by the purchase sheet and settings navigation, with the same observable state.
struct PurchaseContent: View {
    let purchases: PurchaseModel

    var body: some View {
        Form {
            Section {
                PurchaseStatus(purchases: purchases)
                if purchases.usingOfflineCache {
                    Text("暂时无法刷新验证，沿用本机已验证的授权")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if purchases.state != .lifetime {
                Section {
                    Text("30 天全功能免费试用")
                        .font(.headline)
                    Text("无需收费，无需注册账号。试用期间可使用全部功能，不会自动扣费。也可以先体验完全开源&免费的桌面版（macOS、Windows、Linux），请到官网下载。")
                    if purchases.state == .notStarted {
                        Button {
                            Task { await purchases.purchase(purchases.configuration.trialID) }
                        } label: {
                            if let trial = purchases.trialProduct {
                                Text("领取 30 天试用 · \(trial.displayPrice)")
                            } else {
                                Text("领取 30 天免费试用")
                            }
                        }
                        .disabled(purchases.working || purchases.trialProduct == nil)
                    }
                }
                Section {
                    if let product = purchases.lifetimeProduct {
                        Button("永久解锁 · \(product.displayPrice)") {
                            Task { await purchases.purchase(product.id) }
                        }
                        .disabled(purchases.working)
                    } else {
                        Text("永久解锁价格暂不可用")
                            .foregroundStyle(.secondary)
                    }
                    Text("一次性非消耗型购买，永久解锁此 App 的 iPhone 与 iPad 版本，不自动扣费。macOS、Windows 和 Linux 桌面端永久免费。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("恢复购买") { Task { await purchases.restore() } }
                    .disabled(purchases.working)
                Button("刷新授权与商品") {
                    Task {
                        await purchases.refresh()
                        await purchases.loadProducts()
                    }
                }
                .disabled(purchases.working || purchases.loadingProducts)
                if purchases.working || purchases.loadingProducts {
                    ProgressView()
                }
                if let failure = purchases.productFailure {
                    Text(failure).foregroundStyle(.secondary)
                }
                if let notice = purchases.notice {
                    Text(notice).accessibilityAddTraits(.updatesFrequently)
                }
            } footer: {
                Text("试用及购买使用当前 App Store 账户，可在同一账户的设备上恢复。到期后仍可管理主机和访问设置。")
            }
        }
        .navigationTitle("试用与解锁")
        .task {
            if purchases.products.isEmpty { await purchases.loadProducts() }
        }
    }
}

struct PurchaseStatus: View {
    let purchases: PurchaseModel

    var body: some View {
        switch purchases.state {
        case .loading:
            Label("正在读取购买记录…", systemImage: "hourglass")
        case .notStarted:
            Label("尚未领取试用", systemImage: "gift")
        case .trialActive(_, let expires, let remaining):
            VStack(alignment: .leading, spacing: 6) {
                Label("试用剩余 \(max(1, Int(ceil(remaining / 86400)))) 天", systemImage: "clock")
                Text("到期时间：\(expires.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .trialExpired:
            Label("30 天试用已到期", systemImage: "clock.badge.exclamationmark")
        case .lifetime:
            Label("已永久解锁", systemImage: "checkmark.seal")
        case .verificationUnavailable:
            Label("暂时无法验证购买，请刷新或恢复购买", systemImage: "exclamationmark.icloud")
        }
    }
}
