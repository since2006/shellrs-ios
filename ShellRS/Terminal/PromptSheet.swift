import ShellRSCore
import SwiftUI

/// What a login asks: whether to trust the server's key, or a password,
/// passphrase or the server's own questions.
struct PromptSheet: View {
    let prompt: Prompt
    let answer: (PromptReply) -> Void
    @State private var answers: [String]
    @FocusState private var focused: Int?

    init(prompt: Prompt, answer: @escaping (PromptReply) -> Void) {
        self.prompt = prompt
        self.answer = answer
        let count =
            switch prompt.kind {
            case .password, .passphrase: 1
            case .keyboardInteractive(_, _, let fields, _): fields.count
            case .unknownHost, .hostKeyChanged: 0
            }
        _answers = State(initialValue: Array(repeating: "", count: count))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let jumpHost = prompt.jumpHost {
                    Section {
                        LabeledContent("跳板主机", value: jumpHost)
                    }
                }
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        answer(.cancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, role: isKeyChange ? .destructive : nil) {
                        submit()
                    }
                }
            }
            .onAppear {
                focused = answers.isEmpty ? nil : 0
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch prompt.kind {
        case .unknownHost(let host, let port, let algorithm, let fingerprint):
            Section {
                LabeledContent("地址", value: "\(host):\(port)")
                LabeledContent("算法", value: algorithm)
                fingerprintRow(fingerprint)
            } footer: {
                Text("确认指纹和服务器的一致后再信任。信任后保存在 ShellRS 里，下次不再询问。")
            }
        case .hostKeyChanged(let host, let port, let algorithm, let old, let fingerprint):
            Section {
                LabeledContent("地址", value: "\(host):\(port)")
                LabeledContent("算法", value: algorithm)
            }
            Section("已保存指纹") {
                ForEach(old, id: \.self) { fingerprintRow($0) }
            }
            Section {
                fingerprintRow(fingerprint)
            } header: {
                Text("服务器当前指纹")
            } footer: {
                Text("服务器重装过或换过密钥时，更新后即可连接。否则可能有人在冒充这台服务器，请先核实。")
            }
        case .password(let savedRejected):
            Section {
                secureField(0, label: String(localized: "密码"))
            } footer: {
                Text(
                    savedRejected
                        ? String(localized: "已保存的密码被服务器拒绝，请重新输入") : String(localized: "请输入登录密码"))
            }
        case .passphrase(let keyPath, let savedRejected):
            Section {
                secureField(0, label: String(localized: "口令"))
            } footer: {
                Text(
                    savedRejected
                        ? String(localized: "已保存的口令无法解开 \(keyPath)，请重新输入")
                        : String(localized: "请输入 \(keyPath) 的口令"))
            }
        case .keyboardInteractive(_, let instructions, let fields, let savedPasswordRejected):
            Section {
                ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                    if field.echo {
                        TextField(field.label, text: $answers[index])
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: index)
                            .onSubmit { next(after: index) }
                    } else {
                        secureField(index, label: field.label)
                    }
                }
            } header: {
                if !instructions.isEmpty {
                    Text(instructions)
                }
            } footer: {
                if savedPasswordRejected {
                    Text("已保存的密码被服务器拒绝，请重新输入")
                }
            }
        }
    }

    private func fingerprintRow(_ fingerprint: String) -> some View {
        Text(fingerprint)
            .font(.callout.monospaced())
            .textSelection(.enabled)
    }

    private func secureField(_ index: Int, label: String) -> some View {
        SecureField(label, text: $answers[index])
            .textContentType(.password)
            .focused($focused, equals: index)
            .onSubmit { next(after: index) }
    }

    private var title: String {
        switch prompt.kind {
        case .unknownHost:
            String(localized: "首次连接此主机")
        case .hostKeyChanged:
            String(localized: "服务器主机密钥已变更")
        case .password:
            String(localized: "SSH 登录")
        case .passphrase:
            String(localized: "私钥口令")
        case .keyboardInteractive(let name, _, _, _):
            name.isEmpty ? String(localized: "SSH 登录") : name
        }
    }

    private var confirm: String {
        switch prompt.kind {
        case .unknownHost:
            String(localized: "信任并连接")
        case .hostKeyChanged:
            String(localized: "更新并连接")
        case .password, .passphrase, .keyboardInteractive:
            String(localized: "登录")
        }
    }

    private var isKeyChange: Bool {
        if case .hostKeyChanged = prompt.kind {
            return true
        }
        return false
    }

    private func next(after index: Int) {
        if index + 1 < answers.count {
            focused = index + 1
        } else {
            submit()
        }
    }

    private func submit() {
        switch prompt.kind {
        case .unknownHost, .hostKeyChanged:
            answer(.trustAndSave)
        case .password, .passphrase, .keyboardInteractive:
            answer(.answers(answers: answers))
        }
    }
}
