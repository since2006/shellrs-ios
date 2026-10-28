import ShellRSCore
import SwiftUI
import UIKit

/// The credential form: a username with a password, or with a private key
/// pasted, read from a file or made here.
struct CredentialEditor: View {
    enum Subject: Identifiable {
        /// A new one; with `generate`, a key made here.
        case new(generate: Bool)
        case edit(Credential)

        var id: String {
            switch self {
            case .new(let generate): generate ? "generate" : "new"
            case .edit(let credential): "credential-\(credential.id)"
            }
        }

        var credential: Credential? {
            if case .edit(let credential) = self {
                return credential
            }
            return nil
        }
    }

    /// Where a key credential's private key comes from.
    enum KeySource: Hashable {
        /// The one it has.
        case kept
        case paste
        case generate
    }

    let subject: Subject

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = CredentialKind.password
    @State private var user = ""
    @State private var password = ""
    /// The password as saved, to tell whether it was changed.
    @State private var savedPassword: String?
    @State private var source = KeySource.paste
    @State private var keyText = ""
    @State private var algorithm = KeyAlgorithm.ed25519
    @State private var newKey: NewKey?
    @State private var passphrase = ""
    @State private var savedPassphrase: String?
    /// The kept key's, when it can be told without the passphrase.
    @State private var publicKey: String?
    @State private var importing = false
    @State private var saving = false
    @State private var problem: String?

    init(subject: Subject) {
        self.subject = subject
        switch subject {
        case .new(let generate):
            if generate {
                _kind = State(initialValue: .key)
                _source = State(initialValue: .generate)
            }
        case .edit(let credential):
            _name = State(initialValue: credential.name)
            _kind = State(initialValue: credential.kind)
            _user = State(initialValue: credential.user)
            if credential.kind == .key {
                _source = State(initialValue: .kept)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextField("名称", text: $name, prompt: Text("例如 生产环境 root"))
                    Picker("类型", selection: $kind) {
                        Text("密码").tag(CredentialKind.password)
                        Text("密钥").tag(CredentialKind.key)
                        if subject.credential?.kind == .agent {
                            Text(verbatim: "SSH Agent").tag(CredentialKind.agent)
                        }
                    }
                    LabeledTextField("用户名", text: $user, prompt: Text(verbatim: "root"))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if kind == .agent {
                        Text("手机上没有 SSH Agent，请改用密钥凭据")
                    }
                }
                switch kind {
                case .password:
                    Section {
                        LabeledTextField("密码", text: $password, secure: true)
                            .textContentType(.password)
                    } footer: {
                        Text("密码和口令保存在系统钥匙串，不会写入 ShellRS 的数据库。")
                    }
                case .key:
                    keySection
                    if source != .paste || pasted?.encrypted == true {
                        Section {
                            LabeledTextField(
                                "私钥口令", text: $passphrase,
                                prompt: Text(
                                    source == .generate
                                        ? String(localized: "留空则不加密")
                                        : String(localized: "留空则每次连接都询问")),
                                secure: true)
                        } footer: {
                            Text("密码和口令保存在系统钥匙串，不会写入 ShellRS 的数据库。")
                        }
                    }
                case .agent:
                    EmptyView()
                }
                if let usage {
                    Section {
                    } footer: {
                        Text(usage)
                    }
                }
            }
            .navigationTitle(
                subject.credential == nil
                    ? String(localized: "新建凭据") : String(localized: "编辑凭据"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(
                            subject.credential == nil
                                ? String(localized: "创建") : String(localized: "保存")) {
                            Task { await save() }
                        }
                    }
                }
            }
            .alert(
                "无法保存", isPresented: Binding(
                    get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(problem ?? "")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    read(url)
                case .failure(let error):
                    problem = error.localizedDescription
                }
            }
            .task {
                await loadSecrets()
            }
            .task(id: Generation(source: source, algorithm: algorithm)) {
                await generate()
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: The key

    private var keySection: some View {
        Section {
            Picker("私钥", selection: $source) {
                if subject.credential?.kind == .key {
                    Text("保持不变").tag(KeySource.kept)
                }
                Text("粘贴").tag(KeySource.paste)
                Text("生成新密钥").tag(KeySource.generate)
            }
            switch source {
            case .kept:
                if let publicKey {
                    PublicKeyView(key: publicKey)
                }
            case .paste:
                TextEditor(text: $keyText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .overlay(alignment: .topLeading) {
                        if keyText.isEmpty {
                            Text("粘贴私钥，以 -----BEGIN 开头")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button("从文件读取…", systemImage: "folder") {
                    importing = true
                }
                pastedNote
            case .generate:
                Picker("算法", selection: $algorithm) {
                    Text(verbatim: "Ed25519").tag(KeyAlgorithm.ed25519)
                    Text(verbatim: "RSA").tag(KeyAlgorithm.rsa)
                }
                if let newKey {
                    PublicKeyView(key: newKey.publicKey(comment: comment))
                } else {
                    HStack {
                        ProgressView()
                        Text("正在生成密钥…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            switch source {
            case .kept:
                Text("这把私钥由 ShellRS 保存，删除凭据时会一起删除。")
            case .paste:
                EmptyView()
            case .generate:
                if algorithm == .rsa {
                    Text("只在服务器不支持 Ed25519 时选它（OpenSSH 6.5 以前）。")
                } else {
                    Text("把公钥加到服务器的 ~/.ssh/authorized_keys，就能用这把密钥登录。")
                }
            }
        }
    }

    /// What the pasted text is, once there is some.
    private var pastedCheck: Result<PrivateKeyInfo, KeyProblem>? {
        guard !keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return Result { try checkPrivateKey(text: keyText) }
            .mapError { $0 as? KeyProblem ?? .Unreadable }
    }

    private var pasted: PrivateKeyInfo? {
        try? pastedCheck?.get()
    }

    @ViewBuilder
    private var pastedNote: some View {
        switch pastedCheck {
        case nil:
            EmptyView()
        case .success(let info) where info.encrypted:
            Label("私钥已加密，需要口令", systemImage: "lock")
                .foregroundStyle(.secondary)
        case .success:
            Label("私钥可用", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failure(let problem):
            Label(Describe.key(problem), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    /// What a generated key's public key ends in: the credential's name, as
    /// the desktop puts it.
    private var comment: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    /// What a new key is made for: another kind is made anew.
    private struct Generation: Hashable {
        let source: KeySource
        let algorithm: KeyAlgorithm
    }

    private func generate() async {
        guard source == .generate else {
            return
        }
        newKey = nil
        do {
            newKey = try await model.hosts.store.generateKey(algorithm: algorithm)
        } catch {
            problem = Describe.store(error)
        }
    }

    /// The text of a key file the user picked, read this once: the file
    /// itself is never changed.
    private func read(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url), data.count <= Self.keyFileLimit,
            let text = String(data: data, encoding: .utf8)
        else {
            problem = String(localized: "无法读取这个文件，请选择私钥文件")
            return
        }
        keyText = text
    }

    /// Larger than any private key.
    private static let keyFileLimit = 64 * 1024

    /// What the form says about the hosts using the credential.
    private var usage: String? {
        guard let credential = subject.credential else {
            return nil
        }
        let hosts = model.hosts.hostsUsing(credential).count
        guard hosts > 0 else {
            return nil
        }
        let used = String(localized: "有 \(hosts) 台主机使用此凭据。")
        if kind == .key && source != .kept {
            return used + String(localized: "换成新私钥后，要把它的公钥加到这些主机上，它们才能再登录。")
        }
        return used
    }

    // MARK: Saving

    private func loadSecrets() async {
        guard let credential = subject.credential else {
            return
        }
        switch credential.kind {
        case .password:
            savedPassword = await model.hosts.savedSecret(
                .credentialPassword(credential: credential.id))
            password = savedPassword ?? ""
        case .key:
            savedPassphrase = await model.hosts.savedSecret(.passphrase(credential: credential.id))
            passphrase = savedPassphrase ?? ""
            publicKey = await model.hosts.store.publicKey(credential: credential.id)
        case .agent:
            break
        }
    }

    private func save() async {
        let key: KeyChange
        switch (kind, source) {
        case (.key, .kept):
            key = .keep(passphrase: Self.change(passphrase, saved: savedPassphrase))
        case (.key, .paste):
            key = .text(text: keyText, passphrase: passphrase.isEmpty ? nil : passphrase)
        case (.key, .generate):
            guard let newKey else {
                problem = String(localized: "密钥还在生成，请稍候")
                return
            }
            key = .generated(key: newKey, passphrase: passphrase.isEmpty ? nil : passphrase)
        default:
            key = .keep(passphrase: .keep)
        }
        let draft = CredentialDraft(
            name: comment, kind: kind, user: user.trimmingCharacters(in: .whitespaces))
        saving = true
        defer { saving = false }
        do {
            try await model.hosts.saveCredential(
                id: subject.credential?.id, draft: draft, key: key,
                password: kind == .password ? Self.change(password, saved: savedPassword) : .keep)
            dismiss()
        } catch {
            problem = Describe.store(error)
        }
    }

    /// What saving does to a secret the form showed as `saved`.
    private static func change(_ typed: String, saved: String?) -> SecretChange {
        guard typed != (saved ?? "") else {
            return .keep
        }
        return typed.isEmpty ? .clear : .set(value: typed)
    }
}

/// A public key, to copy or share and add to a server's authorized_keys.
private struct PublicKeyView: View {
    let key: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: key)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 20) {
                Button(
                    copied ? String(localized: "已复制公钥") : String(localized: "复制公钥"),
                    systemImage: "doc.on.doc"
                ) {
                    UIPasteboard.general.string = key
                    copied = true
                }
                ShareLink(item: key) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
    }
}
