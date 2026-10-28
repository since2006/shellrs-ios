import ShellRSCore

/// What the questions before deleting say goes with what is deleted, in the
/// desktop's words.
extension Describe {
    /// `nil` for a host nothing depends on.
    static func deleting(host dependents: Dependents) -> String? {
        var sentences: [String] = []
        if dependents.forwards > 0 {
            sentences.append(String(localized: "将同时删除经由该主机的 \(Int(dependents.forwards)) 条端口转发。"))
        }
        if dependents.jumpUsers > 0 {
            sentences.append(
                String(localized: "有 \(Int(dependents.jumpUsers)) 台主机把它用作跳板主机，删除后要重新选择跳板主机才能连接。"))
        }
        return joined(sentences)
    }

    /// `nil` for an empty group nothing depends on.
    static func deleting(group dependents: Dependents) -> String? {
        var items: [String] = []
        if dependents.hosts > 0 {
            items.append(String(localized: "\(Int(dependents.hosts)) 台主机"))
        }
        if dependents.subgroups > 0 {
            items.append(String(localized: "\(Int(dependents.subgroups)) 个子分组"))
        }
        var sentences: [String] = []
        if items.count == 2 {
            sentences.append(String(localized: "将同时删除其中的 \(items[0])和 \(items[1])。"))
        } else if let item = items.first {
            sentences.append(String(localized: "将同时删除其中的 \(item)。"))
        }
        if dependents.forwards > 0 {
            sentences.append(String(localized: "这些主机的 \(Int(dependents.forwards)) 条端口转发会一并删除。"))
        }
        if dependents.jumpUsers > 0 {
            sentences.append(
                String(localized: "分组外有 \(Int(dependents.jumpUsers)) 台主机经由这些主机跳转，删除后要重新选择跳板主机才能连接。"))
        }
        return joined(sentences)
    }

    /// `nil` for a credential no host uses.
    static func deleting(_ credential: Credential, usedBy hosts: Int) -> String? {
        guard hosts > 0 else {
            return nil
        }
        return switch credential.kind {
        case .password:
            String(localized: "有 \(hosts) 台主机正在使用此凭据。删除后它们改为「密码」，连接时询问密码，用户名不变。")
        case .key, .agent:
            String(localized: "有 \(hosts) 台主机正在使用此凭据。删除后它们改为「无密码」，用户名不变。")
        }
    }

    /// Sentences one after another: Chinese ones end in 。 and follow
    /// straight on, English ones take a space between.
    private static func joined(_ sentences: [String]) -> String? {
        guard !sentences.isEmpty else {
            return nil
        }
        return sentences.reduce("") { text, sentence in
            text.last.map { $0.isASCII } == true ? "\(text) \(sentence)" : text + sentence
        }
    }
}
