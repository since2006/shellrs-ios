import ShellRSCore
import SwiftUI

/// The host form: a new host, or a saved one's changes.
struct HostEditor: View {
    enum Subject: Identifiable {
        case new
        case edit(Host)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let host): "host-\(host.id)"
            }
        }

        var host: Host? {
            if case .edit(let host) = self {
                return host
            }
            return nil
        }
    }

    enum Auth: Hashable {
        case password
        case noPassword
        case credential(UInt64)
    }

    let subject: Subject

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var auth = Auth.password
    @State private var password = ""
    /// The password as saved, to tell whether it was changed.
    @State private var savedPassword: String?
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name, prompt: Text("可选，默认用地址"))
                    TextField("地址", text: $address, prompt: Text("主机名或 IP 地址"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }
                Section {
                    TextField("用户名", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("认证方式", selection: $auth) {
                        Text("密码").tag(Auth.password)
                        if case .credential(let id) = subject.host?.auth {
                            Text("使用凭据").tag(Auth.credential(id))
                        }
                        Text("无密码").tag(Auth.noPassword)
                    }
                    if auth == .password {
                        SecureField("密码", text: $password, prompt: Text("留空则每次连接时询问"))
                            .textContentType(.password)
                    }
                } footer: {
                    switch auth {
                    case .password:
                        Text("密码保存在系统钥匙串，不会写入 ShellRS 的数据库。")
                    case .noPassword:
                        Text("只尝试服务器免认证，不询问密码；要用私钥请改用「使用凭据」。")
                    case .credential:
                        Text("用保存的凭据登录。")
                    }
                }
                if subject.host != nil {
                    Section {
                    } footer: {
                        Text("已打开的连接不受影响，下次连接时使用新的设置。")
                    }
                }
            }
            .navigationTitle(subject.host == nil ? "新建主机" : "编辑主机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(subject.host == nil ? "创建" : "保存") {
                        Task { await save() }
                    }
                    .disabled(saving)
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
            .task {
                await load()
            }
        }
        .interactiveDismissDisabled()
    }

    private func load() async {
        guard let host = subject.host else {
            return
        }
        name = host.name
        address = host.address
        port = String(host.port)
        user = host.user
        switch host.auth {
        case .password:
            auth = .password
        case .noPassword:
            auth = .noPassword
        case .credential(let id):
            auth = .credential(id)
        }
        if case .password = host.auth {
            savedPassword = await model.hosts.savedPassword(of: host)
            password = savedPassword ?? ""
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let host = subject.host
        let draft = HostDraft(
            name: name.trimmingCharacters(in: .whitespaces),
            protocol: host?.protocol ?? .ssh,
            address: address.trimmingCharacters(in: .whitespaces),
            port: UInt16(port.trimmingCharacters(in: .whitespaces)) ?? 0,
            user: user.trimmingCharacters(in: .whitespaces),
            auth: hostAuth,
            // What this form does not show yet stays as it is.
            route: host?.route ?? .direct,
            group: host?.group,
            notes: host?.notes ?? ""
        )
        do {
            try await model.hosts.save(id: host?.id, draft: draft, password: passwordChange)
            dismiss()
        } catch {
            problem = Describe.store(error)
        }
    }

    private var hostAuth: HostAuth {
        switch auth {
        case .password: .password
        case .noPassword: .noPassword
        case .credential(let id): .credential(id: id)
        }
    }

    /// An empty password is asked for at each connection.
    private var passwordChange: SecretChange {
        guard auth == .password else {
            return .keep
        }
        if password == (savedPassword ?? "") {
            return .keep
        }
        return password.isEmpty ? .clear : .set(value: password)
    }
}
