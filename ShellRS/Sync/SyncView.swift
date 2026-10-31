import ShellRSCore
import SwiftUI

/// 云同步: how to turn it on while it is off; this device, where sync
/// goes, the other devices, the sync password and turning it off while
/// it is on. Errors only show here, as on the desktop.
struct SyncView: View {
    let sync: SyncModel

    /// What opens over the page.
    enum Sheet: Identifiable {
        case setUp(RemoteKind)
        case signIn(SyncLocation)
        case password(PasswordStep)

        var id: String {
            switch self {
            case .setUp(.webDav): "set-up-webdav"
            case .setUp(.s3): "set-up-s3"
            case .signIn: "sign-in"
            case .password: "password"
            }
        }
    }

    /// The deletions a round would make, for the user to agree to.
    struct MassDelete {
        let count: UInt32
        let of: UInt32
    }

    /// A job that failed, in words.
    struct Trouble {
        let title: String
        let reason: String
    }

    @Environment(AppModel.self) private var model
    @State private var nestedSheet: Sheet?
    private var sheet: Sheet? {
        get { nestedSheet }
        nonmutating set {
            if model.showingSettings {
                nestedSheet = newValue
            } else {
                model.sheet = newValue.map(AppSheet.sync)
            }
        }
    }
    @State private var confirmingRejoin = false
    @State private var massDelete: MassDelete?
    @State private var removing: SyncDevice?
    @State private var turningOff = false
    @State private var trouble: Trouble?

    var body: some View {
        Form {
            if let location = sync.location {
                thisDevice
                place(location)
                others
                Section {
                    Button("更换同步密码…") {
                        sheet = .password(PasswordStep(purpose: .change, location: nil, login: nil))
                    }
                    .disabled(sync.jobRunning)
                } header: {
                    Text("同步密码")
                } footer: {
                    Text("数据密钥一起换新，已移除的设备即使知道旧密码也读不了之后的数据。别的设备下次同步时要输入新密码。")
                }
                Section {
                    Button("关闭同步…", role: .destructive) {
                        turningOff = true
                    }
                    .disabled(sync.jobRunning)
                } footer: {
                    Text("这台设备上的数据保留不动，之后的改动不再同步。")
                }
            } else {
                setUp
            }
        }
        .navigationTitle("云同步")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $nestedSheet) { sheet in
            SyncSheetView(sync: sync, sheet: sheet, close: close)
        }
        .alert("重新加入同步？", isPresented: $confirmingRejoin) {
            Button("重新加入") {
                sync.rejoin()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("另一台设备把这台设备移出了同步。重新加入会把这台设备的数据再写回同步文件夹。")
        }
        .alert(
            massDelete.map { String(localized: "在所有设备上删除 \(Int($0.count)) 条记录？") } ?? "",
            isPresented: Binding(
                get: { massDelete != nil }, set: { if !$0 { massDelete = nil } }),
            presenting: massDelete
        ) { _ in
            Button("删除", role: .destructive) {
                sync.allowMassDeletes()
            }
            Button("取消", role: .cancel) {}
        } message: { deletes in
            Text("共 \(Int(deletes.of)) 条记录。如果不是你删的，选「取消」，同步会暂停，直到你确认。")
        }
        .confirmation(
            Text(verbatim: removing.map { String(localized: "移除“\($0.name)”？") } ?? ""),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { device in
            Button("移除", role: .destructive) {
                Task { await remove(device) }
            }
        } message: { _ in
            Text("它在同步文件夹里的文件会被删除。如果设备丢失了，接着更换同步密码。")
        }
        .confirmation(Text("关闭同步？"), isPresented: $turningOff) {
            Button("关闭同步", role: .destructive) {
                Task { await turnOff(deleteFile: false) }
            }
            Button("关闭同步并删除这台设备的同步文件", role: .destructive) {
                Task { await turnOff(deleteFile: true) }
            }
        } message: {
            Text("这台设备上的数据保留不动，之后的改动不再同步。")
        }
        .alert(
            trouble?.title ?? "",
            isPresented: Binding(get: { trouble != nil }, set: { if !$0 { trouble = nil } }),
            presenting: trouble
        ) { _ in
            Button("好") {}
        } message: { trouble in
            Text(trouble.reason)
        }
        .onAppear {
            sync.pageShown = true
            sync.notice = nil
        }
        .onDisappear {
            sync.pageShown = false
        }
        .onChange(of: sync.reviewRequested, initial: true) { _, requested in
            if requested {
                sync.reviewRequested = false
                review()
            }
        }
    }

    // MARK: Off

    private var setUp: some View {
        Section {
            Button {
                sheet = .setUp(.webDav)
            } label: {
                OptionRow(
                    title: "WebDAV", detail: "Nextcloud、群晖等支持 WebDAV 的网盘或服务器。",
                    symbol: "server.rack")
            }
            .tint(.primary)
            Button {
                sheet = .setUp(.s3)
            } label: {
                OptionRow(
                    title: "S3 存储桶",
                    detail: "AWS S3，或 Cloudflare R2、MinIO、阿里云 OSS、腾讯云 COS 等兼容 S3 的对象存储。",
                    symbol: "shippingbox")
            }
            .tint(.primary)
        } header: {
            Text("开启同步")
        } footer: {
            Text("在几台设备之间同步数据，数据使用端到端加密（E2EE）：离开这台设备前就已加密，远端只有密文，只有拥有密码的设备能解开。")
        }
    }

    // MARK: On

    private var thisDevice: some View {
        Section {
            LabeledContent("状态") {
                status
            }
            if !sync.syncing, case .failed(let reason) = sync.phase {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let attention = sync.attention {
                Label {
                    Text(Describe.attention(attention))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button(reviewLabel(attention)) {
                    review()
                }
                .disabled(sync.busy)
            }
            Button {
                sync.syncNow()
            } label: {
                HStack {
                    Text("立即同步")
                    Spacer()
                    if sync.syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(sync.busy)
        } header: {
            Text("这台设备")
        } footer: {
            Text("其他设备上显示为“\(sync.deviceName)”。")
        }
    }

    @ViewBuilder
    private var status: some View {
        if sync.syncing {
            Text("正在同步…")
        } else {
            switch sync.phase {
            case .off, .waiting:
                Text("尚未同步")
            case .synced(let date):
                Text("上次同步：\(date.formatted(date: .numeric, time: .shortened))")
            case .failed:
                Text("未能同步")
                    .foregroundStyle(.red)
            }
        }
    }

    /// Where sync goes, and the login to change.
    @ViewBuilder
    private func place(_ location: SyncLocation) -> some View {
        Section {
            switch location {
            case .folder(let path):
                DetailRow(title: "同步文件夹", value: path)
            case .webDav(let url, let username):
                DetailRow(title: "WebDAV 地址", value: url)
                loginRow("WebDAV 账号", value: username, location: location)
            case .s3(let endpoint, _, let bucket, let prefix, _, let accessKey):
                DetailRow(
                    title: "S3 位置",
                    value: prefix.isEmpty
                        ? "\(bucket) · \(endpoint)" : "\(bucket)/\(prefix) · \(endpoint)")
                loginRow("S3 访问密钥", value: accessKey, location: location)
            }
        }
    }

    private func loginRow(
        _ title: LocalizedStringKey, value: String, location: SyncLocation
    ) -> some View {
        HStack {
            DetailRow(title: title, value: value)
            Spacer()
            Button("更换…") {
                sheet = .signIn(location)
            }
            .buttonStyle(.borderless)
            .disabled(sync.jobRunning)
        }
    }

    private var others: some View {
        Section {
            if sync.devices.isEmpty {
                Text("还没有。在另一台设备上开启同步，选同一个文件夹。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sync.devices, id: \.id) { device in
                    DeviceRow(device: device)
                        .swipeActions {
                            Button("移除") {
                                removing = device
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button("移除…", systemImage: "minus.circle", role: .destructive) {
                                removing = device
                            }
                        }
                }
            }
        } header: {
            Text("其他设备")
        } footer: {
            Text("移除丢失的设备后，再更换同步密码。")
        }
    }

    // MARK: Doing

    private func close() {
        sheet = nil
    }

    private func reviewLabel(_ attention: Attention) -> LocalizedStringKey {
        switch attention {
        case .needsPassword: "输入密码…"
        case .vaultReplaced, .removed: "重新加入…"
        case .massDelete: "查看…"
        case .loginRefused: "重新登录…"
        }
    }

    /// Settle what sync waits for.
    private func review() {
        guard let attention = sync.attention, let location = sync.location else {
            return
        }
        switch attention {
        case .needsPassword:
            sheet = .password(
                PasswordStep(purpose: .join(.newPassword), location: location, login: nil))
        case .vaultReplaced:
            sheet = .password(PasswordStep(purpose: .join(.reset), location: location, login: nil))
        case .removed:
            confirmingRejoin = true
        case .massDelete(let count, let of):
            massDelete = MassDelete(count: count, of: of)
        case .loginRefused:
            sheet = .signIn(location)
        }
    }

    private func remove(_ device: SyncDevice) async {
        do {
            try await sync.removeDevice(device)
        } catch {
            trouble = Trouble(title: String(localized: "设备未能移除"), reason: Describe.sync(error))
        }
    }

    private func turnOff(deleteFile: Bool) async {
        do {
            try await sync.turnOff(deleteFile: deleteFile)
        } catch {
            trouble = Trouble(title: String(localized: "未能关闭同步"), reason: Describe.sync(error))
        }
    }
}

/// A WebDAV server or an S3 bucket.
enum RemoteKind: Hashable {
    case webDav
    case s3

    /// The kind `location` is; a folder signs in to nothing, and is
    /// taken for WebDAV.
    init(_ location: SyncLocation) {
        if case .s3 = location {
            self = .s3
        } else {
            self = .webDav
        }
    }
}

/// A way to sync, with what it is.
private struct OptionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
    }
}

/// A title over a value too long to sit beside it, such as an address.
private struct DetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(verbatim: value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

/// Another device in sync: what it is and when it last synced.
private struct DeviceRow: View {
    let device: SyncDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: device.name)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let time = Date(timeIntervalSince1970: Double(device.lastWriteMs) / 1000)
            .formatted(date: .numeric, time: .shortened)
        let platform = Describe.platform(device.platform)
        return String(localized: "\(platform) · ShellRS \(device.appVersion) · 上次同步 \(time)")
    }
}

/// The same stable sheet, whether opened from a compact tab or settings modal.
struct SyncSheetView: View {
    let sync: SyncModel
    let sheet: SyncView.Sheet
    let close: () -> Void

    var body: some View {
        NavigationStack {
            switch sheet {
            case .setUp(let kind):
                SyncLoginView(sync: sync, kind: kind, signingIn: nil, close: close)
            case .signIn(let location):
                SyncLoginView(
                    sync: sync, kind: RemoteKind(location),
                    signingIn: location, close: close)
            case .password(let step):
                SyncPasswordView(sync: sync, step: step, cancellable: true, close: close)
            }
        }
        .interactiveDismissDisabled()
    }
}
