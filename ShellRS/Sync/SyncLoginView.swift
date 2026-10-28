import ShellRSCore
import SwiftUI

/// A WebDAV server's or an S3 bucket's login: to set sync up there, then
/// the sync password; or to sign in anew where sync goes.
struct SyncLoginView: View {
    let sync: SyncModel
    let kind: RemoteKind
    /// Where sync goes, to sign in to anew; `nil` to set sync up.
    let signingIn: SyncLocation?
    let close: () -> Void

    /// How 测试连接 went.
    enum Tested {
        case connected
        case failed(String)
    }

    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var endpoint = ""
    @State private var region = ""
    @State private var bucket = ""
    @State private var prefix = ""
    @State private var pathStyle = false
    @State private var accessKey = ""
    @State private var secretKey = ""
    /// What is wrong with the fields as typed.
    @State private var issue: String?
    @State private var testing = false
    @State private var tested: Tested?
    @State private var working = false
    @State private var failure: String?
    @State private var next: PasswordStep?

    init(sync: SyncModel, kind: RemoteKind, signingIn: SyncLocation?, close: @escaping () -> Void) {
        self.sync = sync
        self.kind = kind
        self.signingIn = signingIn
        self.close = close
        switch signingIn {
        case .webDav(let url, let username):
            _url = State(initialValue: url)
            _username = State(initialValue: username)
        case .s3(let endpoint, let region, let bucket, let prefix, let pathStyle, let accessKey):
            _endpoint = State(initialValue: endpoint)
            _region = State(initialValue: region)
            _bucket = State(initialValue: bucket)
            _prefix = State(initialValue: prefix)
            _pathStyle = State(initialValue: pathStyle)
            _accessKey = State(initialValue: accessKey)
        case nil:
            if kind == .s3 {
                _prefix = State(initialValue: Self.s3Folder)
            }
        case .folder:
            break
        }
    }

    /// The folder in the bucket a new sync goes in, as on the desktop:
    /// left as it is, both find the same one.
    static let s3Folder = "ShellRS"

    var body: some View {
        Form {
            Section {
                switch kind {
                case .webDav:
                    webDavFields
                case .s3:
                    s3Fields
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let issue {
                        Text(issue)
                            .foregroundStyle(.red)
                    }
                    note
                }
            }
            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if testing {
                            ProgressView()
                        }
                    }
                }
                .disabled(testing || working)
                switch tested {
                case .connected:
                    Label {
                        Text("连接成功，可以在这里读写。")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                case .failed(let reason):
                    Label {
                        Text("连接失败：\(reason)")
                    } icon: {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                case nil:
                    EmptyView()
                }
            }
        }
        .disabled(working)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    close()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else if signingIn == nil {
                    Button("下一步") {
                        Task { await commit() }
                    }
                } else {
                    Button("保存") {
                        Task { await commit() }
                    }
                }
            }
        }
        .alert(
            "连接失败", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
        .navigationDestination(item: $next) { step in
            SyncPasswordView(sync: sync, step: step, cancellable: false, close: close)
        }
    }

    // MARK: Fields

    @ViewBuilder
    private var webDavFields: some View {
        LabeledTextField(
            "地址", text: $url, prompt: Text(verbatim: "https://dav.example.com/ShellRS")
        )
        .keyboardType(.URL)
        .textContentType(.URL)
        .plainText()
        .disabled(signingIn != nil)
        LabeledTextField("用户名", text: $username)
            .textContentType(.username)
            .plainText()
        LabeledTextField("密码", text: $password, prompt: Text("必填"), secure: true)
            .textContentType(.password)
    }

    @ViewBuilder
    private var s3Fields: some View {
        Group {
            LabeledTextField(
                "服务地址", text: $endpoint,
                prompt: Text(verbatim: "https://s3.us-east-1.amazonaws.com")
            )
            .keyboardType(.URL)
            .textContentType(.URL)
            LabeledTextField("区域", text: $region, prompt: Text(verbatim: "us-east-1"))
            LabeledTextField("存储桶", text: $bucket)
            LabeledTextField("桶里的文件夹", text: $prefix)
            Toggle("路径式地址（MinIO 等自建的服务要打开）", isOn: $pathStyle)
        }
        .plainText()
        .disabled(signingIn != nil)
        LabeledTextField("Access Key ID", text: $accessKey)
            .plainText()
        LabeledTextField("Secret Access Key", text: $secretKey, prompt: Text("必填"), secure: true)
    }

    private var title: Text {
        switch (kind, signingIn) {
        case (.webDav, nil): Text("连接 WebDAV")
        case (.s3, nil): Text("连接 S3")
        case (.webDav, _): Text("重新登录 WebDAV")
        case (.s3, _): Text("更换 S3 访问密钥")
        }
    }

    private var note: Text {
        switch kind {
        case .webDav:
            Text("地址是服务器上放同步数据的文件夹，不存在会自动建。Nextcloud 要用「设置 › 安全」里生成的应用密码。")
        case .s3:
            Text("区域留空就是 us-east-1，Cloudflare R2 填 auto。阿里云 OSS、腾讯云 COS 等填它们兼容 S3 的服务地址。")
        }
    }

    // MARK: Doing

    /// The fields as typed, checked; `nil` after saying what is wrong.
    private func checked() -> CheckedLogin? {
        do {
            let login =
                switch kind {
                case .webDav:
                    try checkWebdavLogin(url: url, username: username, password: password)
                case .s3:
                    try checkS3Login(
                        login: S3Login(
                            endpoint: endpoint, region: region, bucket: bucket, prefix: prefix,
                            pathStyle: pathStyle, accessKey: accessKey, secretKey: secretKey))
                }
            issue = nil
            return login
        } catch {
            issue = Describe.login(error)
            return nil
        }
    }

    private func test() async {
        tested = nil
        guard let login = checked() else {
            return
        }
        testing = true
        defer { testing = false }
        do {
            try await sync.testConnection(login.location, login: login.login)
            tested = .connected
        } catch {
            tested = .failed(Describe.sync(error))
        }
    }

    private func commit() async {
        guard let login = checked() else {
            return
        }
        working = true
        defer { working = false }
        do {
            if signingIn != nil {
                try await sync.changeLogin(login.location, login: login.login)
                close()
            } else {
                // Setting up: whether sync is there already.
                let present = try await sync.inspect(login.location, login: login.login)
                next = PasswordStep(
                    purpose: present ? .join(.first) : .create, location: login.location,
                    login: login.login)
            }
        } catch {
            failure = Describe.sync(error)
        }
    }
}

extension View {
    /// A field typed as is: no capitals, no corrections.
    func plainText() -> some View {
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
