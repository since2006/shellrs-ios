import ShellRSCore
import SwiftUI

/// What a sync password is asked for.
struct PasswordStep: Hashable, Identifiable {
    enum Purpose: Hashable {
        /// Set sync up with a new one.
        case create
        case join(JoinReason)
        /// Join the sync this setup code is of: the place and the login
        /// are in the code, which the password opens.
        case code(String)
        /// 更换同步密码.
        case change
    }

    let purpose: Purpose
    /// Where sync is set up or joined; `nil` to change the password, and
    /// for a setup code, which says where.
    let location: SyncLocation?
    /// The server's or the bucket's login, typed the step before; `nil`
    /// for the one the keychain keeps.
    let login: String?

    var id: Self { self }
}

/// Why the sync password is asked for, to join.
enum JoinReason: Hashable {
    /// This device joins the sync it found.
    case first
    /// The password was changed on another device.
    case newPassword
    /// Sync was reset on another device.
    case reset
}

/// The sync password: a new one typed twice to set sync up or change it,
/// or the one there is to join.
struct SyncPasswordView: View {
    let sync: SyncModel
    let step: PasswordStep
    /// It opens alone, not after the login: it has its own 取消.
    let cancellable: Bool
    let close: () -> Void

    @State private var password = ""
    @State private var repeated = ""
    @State private var shown = false
    @State private var issue: String?
    @State private var working = false
    @State private var failure: String?

    /// It takes a new password, typed twice.
    private var isNew: Bool {
        switch step.purpose {
        case .create, .change: true
        case .join, .code: false
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    if isNew {
                        PasswordField(title: "新的同步密码", text: $password, shown: shown, new: true)
                    } else {
                        PasswordField(title: "同步密码", text: $password, shown: shown, new: false)
                    }
                    Button {
                        shown.toggle()
                    } label: {
                        Image(systemName: shown ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(shown ? Text("隐藏密码") : Text("显示密码"))
                }
                if isNew {
                    PasswordField(title: "再输入一次", text: $repeated, shown: shown, new: true)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let issue {
                        Text(issue)
                            .foregroundStyle(.red)
                    }
                    if working {
                        workingText
                    }
                    description
                }
            }
            if isNew {
                Section {
                    Button("生成随机密码") {
                        let generated = randomSyncPassword()
                        password = generated
                        repeated = generated
                        shown = true
                    }
                } footer: {
                    Label("忘了同步密码就无法找回，记在安全的地方。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .disabled(working)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(working)
        .toolbar {
            if cancellable {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        close()
                    }
                    .disabled(working)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else {
                    Button {
                        Task { await commit() }
                    } label: {
                        commitLabel
                    }
                }
            }
        }
        .alert(
            failureTitle, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Words

    private var title: Text {
        switch step.purpose {
        case .create: Text("创建同步")
        case .join(.first), .code: Text("加入同步")
        case .join(.newPassword): Text("输入新的同步密码")
        case .join(.reset): Text("重新加入同步")
        case .change: Text("更换同步密码")
        }
    }

    private var description: Text {
        switch step.purpose {
        case .create:
            Text("这个文件夹里还没有同步。设一个同步密码，别的设备加入时要输入它。")
        case .join(.first):
            Text("这个文件夹里已有同步。输入创建时设的同步密码，这台设备上的数据会和其他设备的合并。")
        case .join(.newPassword):
            Text("同步密码已在别的设备上更改，输入新密码后继续同步。")
        case .join(.reset):
            Text("同步已在别的设备上重置。输入现在的同步密码重新加入，这台设备上的数据会和其他设备的合并。")
        case .code:
            Text("输入这个同步的同步密码，这台设备上的数据会和其他设备的合并。")
        case .change:
            Text("同时换一把新的数据密钥：已移除的设备即使知道旧密码，也读不了之后的数据。别的设备下次同步时要输入新密码。")
        }
    }

    private var commitLabel: Text {
        switch step.purpose {
        case .create: Text("创建同步")
        case .join(.newPassword): Text("继续同步")
        case .join, .code: Text("加入同步")
        case .change: Text("更换")
        }
    }

    private var workingText: Text {
        switch step.purpose {
        case .create: Text("正在创建同步…")
        case .join, .code: Text("正在加入同步…")
        case .change: Text("正在更换…")
        }
    }

    private var failureTitle: String {
        switch step.purpose {
        case .create: String(localized: "未能创建同步")
        case .join, .code: String(localized: "未能加入同步")
        case .change: String(localized: "未能更换同步密码")
        }
    }

    // MARK: Doing

    private func commit() async {
        let problem =
            isNew
            ? checkNewSyncPassword(password: password, repeat: repeated)
            : checkSyncPassword(password: password)
        if let problem {
            issue = Describe.password(problem)
            return
        }
        issue = nil
        working = true
        defer { working = false }
        do {
            switch step.purpose {
            case .create:
                guard let location = step.location else { return }
                try await sync.create(location, login: step.login, password: password)
            case .join(let reason):
                guard let location = step.location else { return }
                try await sync.join(
                    location, login: step.login, password: password, fresh: reason != .newPassword)
            case .code(let code):
                try await sync.join(code: code, password: password)
            case .change:
                try await sync.changePassword(password)
            }
            close()
        } catch {
            failure = Describe.sync(error)
        }
    }
}

/// A password field that shows what is typed when asked to.
private struct PasswordField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let shown: Bool
    /// A new one, for the system to offer to keep.
    let new: Bool

    var body: some View {
        Group {
            if shown {
                TextField(title, text: $text)
                    .plainText()
                    .fontDesign(.monospaced)
            } else {
                SecureField(title, text: $text)
            }
        }
        .textContentType(new ? .newPassword : .password)
    }
}
