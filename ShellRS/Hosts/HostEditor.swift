import ShellRSCore
import SwiftUI

/// The host form: a new host, or a saved one's changes.
struct HostEditor: View {
    enum Subject: Identifiable {
        /// In the group given, or at the top.
        case new(group: UInt64?)
        case edit(Host)

        var id: String {
            switch self {
            case .new(let group): "new-\(group.map(String.init) ?? "top")"
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

    enum Kind: Hashable {
        case ssh
        case telnet
    }

    /// How the host logs in. A Telnet host's automatic login is off with
    /// `.noPassword`.
    enum Auth: Hashable {
        case password
        case noPassword
        case credential
    }

    enum RouteKind: Hashable {
        case direct
        case jump
        case proxy
    }

    let subject: Subject

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = Kind.ssh
    @State private var address = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var auth = Auth.password
    @State private var credential: UInt64?
    @State private var password = ""
    /// The password as saved, to tell whether it was changed.
    @State private var savedPassword: String?
    @State private var userPrompt = ""
    @State private var passwordPrompt = ""
    @State private var routeKind = RouteKind.direct
    @State private var jumps: [UInt64?] = []
    @State private var proxyKind = ProxyKind.socks5
    @State private var proxyAddress = ""
    @State private var proxyPort = ""
    @State private var proxyUser = ""
    @State private var proxyPassword = ""
    @State private var savedProxyPassword: String?
    @State private var group: UInt64?
    @State private var notes = ""
    @State private var saving = false
    @State private var problem: String?

    init(subject: Subject) {
        self.subject = subject
        switch subject {
        case .new(let group):
            _group = State(initialValue: group)
        case .edit(let host):
            _name = State(initialValue: host.name)
            _address = State(initialValue: host.address)
            _port = State(initialValue: String(host.port))
            _user = State(initialValue: host.user)
            _group = State(initialValue: host.group)
            _notes = State(initialValue: host.notes)
            if case .telnet(let user, let password) = host.protocol {
                _kind = State(initialValue: .telnet)
                _userPrompt = State(initialValue: user)
                _passwordPrompt = State(initialValue: password)
            }
            switch host.auth {
            case .password:
                _auth = State(initialValue: .password)
            case .noPassword:
                _auth = State(initialValue: .noPassword)
            case .credential(let id):
                _auth = State(initialValue: .credential)
                _credential = State(initialValue: id)
            }
            switch host.route {
            case .direct:
                break
            case .jump(let hosts):
                _routeKind = State(initialValue: .jump)
                _jumps = State(initialValue: hosts)
            case .proxy(let proxy):
                _routeKind = State(initialValue: .proxy)
                _proxyKind = State(initialValue: proxy.kind)
                _proxyAddress = State(initialValue: proxy.host)
                _proxyPort = State(initialValue: String(proxy.port))
                _proxyUser = State(initialValue: proxy.user ?? "")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextField("名称", text: $name, prompt: Text("可选，默认用地址"))
                    Picker("协议", selection: $kind) {
                        Text(verbatim: "SSH").tag(Kind.ssh)
                        Text(verbatim: "Telnet").tag(Kind.telnet)
                    }
                    LabeledTextField("地址", text: $address, prompt: Text("主机名或 IP 地址"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledTextField("端口", text: $port)
                        .keyboardType(.numberPad)
                } footer: {
                    if kind == .telnet {
                        Text("Telnet 主机暂时只能在电脑上连接。")
                    }
                }
                switch kind {
                case .ssh:
                    sshLogin
                case .telnet:
                    telnetLogin
                }
                route
                Section {
                    Picker("分组", selection: $group) {
                        Text("（无分组）").tag(UInt64?.none)
                        ForEach(HostTree.groupOptions(model.hosts.groups)) { option in
                            Text(option.path).tag(Optional(option.id))
                        }
                    }
                }
                Section {
                    TextField("备注", text: $notes, prompt: Text("可选"), axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("备注")
                } footer: {
                    if subject.host != nil {
                        Text("已打开的连接不受影响，下次连接时使用新的设置。")
                    }
                }
            }
            .onChange(of: kind) { old, new in
                // The other protocol's usual port follows the switch.
                if port == String(Self.defaultPort(old)) {
                    port = String(Self.defaultPort(new))
                }
                if new == .telnet, let id = credential, model.hosts.credential(id)?.kind != .password {
                    credential = nil
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
                await loadSecrets()
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Logging in

    private var sshLogin: some View {
        Section {
            if auth != .credential {
                LabeledTextField("用户名", text: $user, prompt: Text(verbatim: "root"))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Picker("认证方式", selection: $auth) {
                Text("密码").tag(Auth.password)
                Text("使用凭据").tag(Auth.credential)
                Text("无密码").tag(Auth.noPassword)
            }
            switch auth {
            case .password:
                LabeledTextField(
                    "密码", text: $password, prompt: Text("留空则每次连接时询问"), secure: true)
                    .textContentType(.password)
            case .credential:
                credentialPicker
            case .noPassword:
                EmptyView()
            }
        } footer: {
            switch auth {
            case .password:
                Text("密码保存在系统钥匙串，不会写入 ShellRS 的数据库。")
            case .noPassword:
                Text("只尝试服务器免认证，不询问密码；要用私钥请改用「使用凭据」。")
            case .credential:
                credentialNote
            }
        }
    }

    /// A Telnet host's automatic login: the user and password, typed here
    /// or a credential's, and the prompts it answers.
    @ViewBuilder
    private var telnetLogin: some View {
        Section {
            Toggle("Telnet 自动登录", isOn: autoLogin)
            if auth != .noPassword {
                Picker("认证方式", selection: $auth) {
                    Text("手动输入").tag(Auth.password)
                    Text("使用凭据").tag(Auth.credential)
                }
                if auth == .password {
                    LabeledTextField("用户名", text: $user, prompt: Text("可选"))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledTextField(
                        "密码", text: $password, prompt: Text("可选，留空则连接后自己输入"),
                        secure: true)
                        .textContentType(.password)
                } else {
                    credentialPicker
                }
            }
        } footer: {
            if auth == .credential {
                credentialNote
            }
        }
        if auth != .noPassword {
            Section {
                LabeledTextField("用户名提示文本", text: $userPrompt, prompt: Text(verbatim: "login:"))
                LabeledTextField(
                    "密码提示文本", text: $passwordPrompt, prompt: Text(verbatim: "Password:"))
            } footer: {
                Text("留空使用常见提示，匹配时忽略大小写。用户名可留空以支持仅密码登录。")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    private var autoLogin: Binding<Bool> {
        Binding(
            get: { auth != .noPassword },
            set: { auth = $0 ? .password : .noPassword })
    }

    /// The credentials the host can log in with: a Telnet host types only a
    /// password.
    private var usableCredentials: [Credential] {
        model.hosts.credentials.filter { kind == .ssh || $0.kind == .password }
    }

    private var credentialPicker: some View {
        Picker("凭据", selection: $credential) {
            if credential == nil {
                Text("请选择凭据").tag(UInt64?.none)
            }
            ForEach(usableCredentials, id: \.id) { credential in
                Text("\(credential.name)（\(credential.summary)）").tag(Optional(credential.id))
            }
        }
    }

    @ViewBuilder
    private var credentialNote: some View {
        if let credential = credential.flatMap(model.hosts.credential) {
            switch credential.kind {
            case .password:
                Text("以 \(credential.user) 登录，使用凭据保存的密码")
            case .key:
                Text("以 \(credential.user) 登录，使用 ShellRS 保存的私钥")
            case .agent:
                Text("手机上没有 SSH Agent，请改用密钥凭据")
            }
        } else if usableCredentials.isEmpty {
            Text(kind == .ssh ? "还没有凭据，可在「凭据」页新建" : "还没有密码凭据，可在「凭据」页新建")
        }
    }

    // MARK: Route

    private var route: some View {
        Section {
            Picker("连接方式", selection: $routeKind) {
                Text("直接连接").tag(RouteKind.direct)
                Text("SSH 跳板").tag(RouteKind.jump)
                Text("代理连接").tag(RouteKind.proxy)
            }
            switch routeKind {
            case .direct:
                EmptyView()
            case .jump:
                ForEach(Array(jumps.enumerated()), id: \.offset) { index, id in
                    jumpRow(index: index, id: id)
                }
                .onMove { jumps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { jumps.remove(atOffsets: $0) }
                Menu("添加跳板主机") {
                    ForEach(jumpCandidates, id: \.id) { host in
                        Button(Self.jumpTitle(host)) {
                            jumps.append(host.id)
                        }
                    }
                }
                .disabled(jumpCandidates.isEmpty)
            case .proxy:
                Picker("代理类型", selection: $proxyKind) {
                    Text("HTTP 代理").tag(ProxyKind.http)
                    Text("SOCKS5 代理").tag(ProxyKind.socks5)
                }
                LabeledTextField("代理地址", text: $proxyAddress, prompt: Text("例如 127.0.0.1"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledTextField("端口", text: $proxyPort)
                    .keyboardType(.numberPad)
                LabeledTextField("用户名", text: $proxyUser, prompt: Text("可选"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledTextField("密码", text: $proxyPassword, prompt: Text("可选"), secure: true)
            }
        } footer: {
            switch routeKind {
            case .direct:
                EmptyView()
            case .jump:
                if jumpCandidates.isEmpty {
                    Text(jumps.isEmpty ? "还没有其他主机可做跳板" : "其他主机都已添加")
                } else {
                    Text("依次经过跳板主机连接到当前主机，可添加多台。")
                }
            case .proxy:
                Text("目标地址由代理服务器解析；代理不需要认证时，用户名和密码留空。")
            }
        }
    }

    private func jumpRow(index: Int, id: UInt64?) -> some View {
        let host = id.flatMap(model.hosts.host)
        return HStack {
            Text(verbatim: "\(index + 1)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let host {
                Text(Self.jumpTitle(host))
                    .lineLimit(1)
            } else {
                Text("已删除的主机")
                    .foregroundStyle(.red)
            }
        }
        .contextMenu {
            if index > 0 {
                Button("上移", systemImage: "arrow.up") {
                    jumps.swapAt(index, index - 1)
                }
            }
            if index < jumps.count - 1 {
                Button("下移", systemImage: "arrow.down") {
                    jumps.swapAt(index, index + 1)
                }
            }
            Button("移除", systemImage: "minus.circle", role: .destructive) {
                jumps.remove(at: index)
            }
        }
    }

    /// The SSH hosts the route can go through next: not this one, nor one
    /// it already goes through.
    private var jumpCandidates: [Host] {
        model.hosts.hosts.filter { host in
            host.isSsh && host.id != subject.host?.id && !jumps.contains(host.id)
        }
    }

    private static func jumpTitle(_ host: Host) -> String {
        String(localized: "\(host.title)（\(host.address)）")
    }

    // MARK: Saving

    private static func defaultPort(_ kind: Kind) -> UInt16 {
        kind == .ssh ? 22 : 23
    }

    private func loadSecrets() async {
        guard let host = subject.host else {
            return
        }
        if case .password = host.auth {
            savedPassword = await model.hosts.savedSecret(.hostPassword(host: host.id))
            password = savedPassword ?? ""
        }
        if case .proxy = host.route {
            savedProxyPassword = await model.hosts.savedSecret(.proxyPassword(host: host.id))
            proxyPassword = savedProxyPassword ?? ""
        }
    }

    private func save() async {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
        if auth == .credential && credential == nil {
            problem = String(localized: "请选择凭据")
            return
        }
        if routeKind == .proxy && trimmed(proxyUser).isEmpty && !proxyPassword.isEmpty {
            problem = String(localized: "填写代理密码时请同时填写用户名")
            return
        }
        saving = true
        defer { saving = false }
        let draft = HostDraft(
            name: trimmed(name),
            protocol: kind == .ssh
                ? .ssh
                : .telnet(userPrompt: trimmed(userPrompt), passwordPrompt: trimmed(passwordPrompt)),
            address: trimmed(address),
            port: UInt16(trimmed(port)) ?? 0,
            user: trimmed(user),
            auth: hostAuth,
            route: hostRoute,
            group: group,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try await model.hosts.save(
                id: subject.host?.id, draft: draft,
                password: Self.change(password, saved: savedPassword, applies: auth == .password),
                proxyPassword: Self.change(
                    proxyPassword, saved: savedProxyPassword,
                    applies: routeKind == .proxy && !trimmed(proxyUser).isEmpty))
            dismiss()
        } catch {
            problem = Describe.store(error)
        }
    }

    private var hostAuth: HostAuth {
        switch auth {
        case .password: .password
        case .noPassword: .noPassword
        case .credential: credential.map { .credential(id: $0) } ?? .password
        }
    }

    private var hostRoute: HostRoute {
        switch routeKind {
        case .direct:
            return .direct
        case .jump:
            return .jump(hosts: jumps)
        case .proxy:
            let user = proxyUser.trimmingCharacters(in: .whitespaces)
            return .proxy(
                proxy: HostProxy(
                    kind: proxyKind,
                    host: proxyAddress.trimmingCharacters(in: .whitespaces),
                    port: UInt16(proxyPort.trimmingCharacters(in: .whitespaces)) ?? 0,
                    user: user.isEmpty ? nil : user))
        }
    }

    /// What saving does to a password the form showed as `saved`: an empty
    /// one is asked for at each connection.
    private static func change(_ typed: String, saved: String?, applies: Bool) -> SecretChange {
        guard applies, typed != (saved ?? "") else {
            return .keep
        }
        return typed.isEmpty ? .clear : .set(value: typed)
    }
}
