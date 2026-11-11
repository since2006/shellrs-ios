import ShellRSCore
import SwiftUI

/// 用配置码加入同步: the setup code another device shows, scanned off its
/// screen or pasted, then the sync password on the next page. Nothing of
/// the server or the bucket is typed: the code holds it.
struct SyncCodeScanView: View {
    let sync: SyncModel
    let close: () -> Void

    /// Where the camera stands.
    enum Camera {
        /// The user is being asked.
        case asking
        case ready
        case denied
        case unsupported
    }

    @State private var camera = Camera.asking
    /// What is wrong with what was scanned or pasted.
    @State private var issue: String?
    @State private var next: PasswordStep?

    var body: some View {
        Form {
            Section {
                switch camera {
                case .asking:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .ready:
                    // The camera is on only while this page is the one
                    // shown: the password page turns it off.
                    if next == nil {
                        CodeScanner { text in
                            take(text, scanned: true)
                        }
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                    }
                case .denied:
                    Text("ShellRS 没有相机权限。在系统设置里允许后可以扫码，也可以粘贴配置码。")
                        .foregroundStyle(.secondary)
                    Button("打开设置") {
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settings)
                        }
                    }
                case .unsupported:
                    Text("这台设备不能扫码，可以粘贴配置码。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("扫描二维码")
            } footer: {
                switch camera {
                case .asking, .ready:
                    Text("在已开启同步的设备上打开「云同步」，点「显示配置码…」，把二维码放进取景框。")
                case .denied, .unsupported:
                    Text("在已开启同步的设备上打开「云同步」，点「显示配置码…」，复制配置码后在这里粘贴。")
                }
            }
            Section {
                PasteButton(payloadType: String.self) { texts in
                    Task { @MainActor in
                        _ = take(texts.first ?? "", scanned: false)
                    }
                }
            } header: {
                Text("或者粘贴配置码")
            } footer: {
                if let issue {
                    Text(issue)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("用配置码加入同步")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    close()
                }
            }
        }
        .navigationDestination(item: $next) { step in
            SyncPasswordView(sync: sync, step: step, cancellable: false, close: close)
        }
        .task {
            switch await CodeScanner.access() {
            case .granted: camera = .ready
            case .denied: camera = .denied
            case .unsupported: camera = .unsupported
            }
        }
    }

    /// Goes on to the sync password with `text` when it is a setup code,
    /// and says so. Whatever else the camera reads is passed over without
    /// a word; what was pasted is told what is wrong with it.
    private func take(_ text: String, scanned: Bool) -> Bool {
        guard !scanned || isSyncSetupCode(text: text) else {
            return false
        }
        do {
            try checkSyncSetupCode(code: text)
        } catch {
            issue = Describe.sync(error)
            return false
        }
        issue = nil
        next = PasswordStep(purpose: .code(text), location: nil, login: nil)
        return true
    }
}
