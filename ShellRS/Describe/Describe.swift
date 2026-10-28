import Foundation
import ShellRSCore

/// The core's failures in the user's language: the core has none of its
/// own words. Worded as the desktop words them (its locales/ssh.yml).
///
/// The switches name every case: when the core adds one, this stops
/// compiling until it has words.
enum Describe {
    /// Every link of `failure`, outermost first, joined as the desktop
    /// joins them.
    static func failure(_ failure: Failure) -> String {
        failure.links.map(link).joined(separator: ": ")
    }

    /// Why the core would not open.
    static func core(_ error: Error) -> String {
        guard let error = error as? CoreError else {
            return error.localizedDescription
        }
        switch error {
        case .DataFolderInUse:
            return String(localized: "数据文件夹正被另一个 ShellRS 使用")
        case .DataFolder(let detail):
            return String(localized: "无法创建数据文件夹：\(detail)")
        case .DatabaseNewer:
            return String(localized: "数据库由更新版本的 ShellRS 写入，请先更新 ShellRS")
        case .DatabaseTooOld:
            return String(localized: "数据库由早期开发版写入，无法打开")
        case .Database(let detail):
            return String(localized: "无法打开数据库：\(detail)")
        case .Internal(let detail):
            return detail
        }
    }

    /// Why the store did nothing.
    static func store(_ error: Error) -> String {
        guard let error = error as? StoreError else {
            return error.localizedDescription
        }
        switch error {
        case .NotFound:
            return String(localized: "找不到这项，可能已被删除")
        case .Host(let problem):
            return host(problem)
        case .Credential(let problem):
            switch problem {
            case .name:
                return String(localized: "请输入凭据名称")
            case .noKey:
                return String(localized: "请选择或粘贴私钥")
            }
        case .Key(let problem):
            return key(problem)
        case .GroupName:
            return String(localized: "请输入分组名称")
        case .GroupNotFound:
            return String(localized: "分组已被删除")
        case .GroupIntoItself:
            return String(localized: "分组不能移到自己或自己的子分组里")
        case .CredentialNotFound:
            return String(localized: "凭据已被删除，请重新选择")
        case .JumpHostNotFound:
            return String(localized: "请移除已删除的跳板主机")
        case .JumpThroughItself:
            return String(localized: "主机不能经由自己连接")
        case .HasDependents:
            return String(localized: "有主机把它用作跳板主机或有端口转发经由它，只能是 SSH 主机")
        case .NotSsh:
            return String(localized: "这台主机不是 SSH 主机，暂时只能在电脑上连接")
        case .KeyNotSaved(let detail):
            return String(localized: "私钥未能保存：\(detail)")
        case .Secret(let problem):
            return secret(problem)
        case .Closed:
            return String(localized: "已关闭")
        case .Internal(let detail):
            return detail
        }
    }

    /// A field of the host form, as the desktop's form words it.
    static func host(_ problem: HostProblem) -> String {
        switch problem {
        case .address:
            String(localized: "请输入地址")
        case .port:
            String(localized: "端口必须是 1 到 65535 之间的数字")
        case .noJumpHosts:
            String(localized: "请添加跳板主机")
        case .deletedJumpHost:
            String(localized: "请移除已删除的跳板主机")
        case .proxyAddress:
            String(localized: "请输入代理地址")
        case .proxyPort:
            String(localized: "代理端口必须是 1 到 65535 之间的数字")
        }
    }

    /// What is wrong with a private key's text.
    static func key(_ problem: KeyProblem) -> String {
        switch problem {
        case .Empty:
            String(localized: "请粘贴私钥")
        case .PublicKey:
            String(localized: "这是公钥，请粘贴私钥")
        case .Unreadable:
            String(localized: "无法识别这段私钥")
        }
    }

    /// What the store could not keep after a change it made.
    static func storeFailure(_ failure: StoreFailure) -> String {
        switch failure {
        case .notSaved(let change, let detail):
            notSaved(change, detail: detail)
        case .keyNotDeleted(let detail):
            String(localized: "私钥文件未能删除：\(detail)")
        case .secret(_, let writing, let problem):
            writing
                ? String(localized: "密码未能存进钥匙串：\(secret(problem))")
                : String(localized: "无法从钥匙串读取密码：\(secret(problem))")
        case .syncedSecret(let problem):
            String(localized: "同步来的密码未能存进钥匙串：\(secret(problem))")
        }
    }

    private static func notSaved(_ change: ChangeKind, detail: String) -> String {
        switch change {
        case .newHost:
            String(localized: "新建主机未能保存到本地数据库：\(detail)")
        case .saveHost:
            String(localized: "保存主机未能保存到本地数据库：\(detail)")
        case .deleteHost:
            String(localized: "删除主机未能保存到本地数据库：\(detail)")
        case .duplicateHost:
            String(localized: "复制主机未能保存到本地数据库：\(detail)")
        case .hostOrder, .moveInTree:
            String(localized: "调整主机顺序未能保存到本地数据库：\(detail)")
        case .newGroup:
            String(localized: "新建分组未能保存到本地数据库：\(detail)")
        case .saveGroup:
            String(localized: "保存分组未能保存到本地数据库：\(detail)")
        case .deleteGroup:
            String(localized: "删除分组未能保存到本地数据库：\(detail)")
        case .groupExpanded:
            String(localized: "保存分组展开状态未能保存到本地数据库：\(detail)")
        case .newCredential:
            String(localized: "新建凭据未能保存到本地数据库：\(detail)")
        case .saveCredential:
            String(localized: "保存凭据未能保存到本地数据库：\(detail)")
        case .deleteCredential:
            String(localized: "删除凭据未能保存到本地数据库：\(detail)")
        case .recent:
            String(localized: "最近连接未能保存到本地数据库：\(detail)")
        case .other:
            String(localized: "未能保存到本地数据库：\(detail)")
        }
    }

    private static func secret(_ problem: SecretProblem) -> String {
        switch problem {
        case .unavailable:
            String(localized: "钥匙串现在不可用")
        case .keychain(let detail), .keyFile(let detail):
            detail
        }
    }

    /// Why a call on a connection, terminal or session failed.
    static func ssh(_ error: Error) -> String {
        guard let error = error as? SshError else {
            return error.localizedDescription
        }
        switch error {
        case .NotConnected:
            return String(localized: "未连接")
        case .Closed:
            return String(localized: "已关闭")
        case .Failed(let failure):
            return Self.failure(failure)
        case .Internal(let detail):
            return detail
        }
    }

    static func link(_ link: FailureLink) -> String {
        switch link {
        case .connect(let error):
            connect(error)
        case .knownHosts(let error):
            knownHosts(error)
        case .auth(let error):
            auth(error)
        case .agent(let error):
            agent(error)
        case .proxy(let error):
            proxy(error)
        case .route(let error):
            route(error)
        case .missingCredential(let need):
            missing(need)
        case .passwordWanted:
            String(localized: "服务器要求密码，「无密码」不会询问；请改用「密码」或「使用凭据」")
        case .channel(let error):
            channel(error)
        case .noCommonAlgorithm(let kind, let theirs):
            noCommon(kind, theirs: theirs.joined(separator: String(localized: "、")))
        case .timedOut:
            String(localized: "连接超时")
        case .connectionLost:
            String(localized: "连接已断开")
        case .io(let kind, let detail):
            io(kind, detail: detail)
        case .sftp(let error):
            String(describing: error)
        case .upload(let error):
            String(describing: error)
        case .download(let error):
            String(describing: error)
        case .journal(let error):
            String(describing: error)
        case .edit(let error):
            String(describing: error)
        case .sftpStatus(_, let message):
            message
        case .cancelled:
            String(localized: "已取消")
        case .other(let detail):
            detail
        }
    }

    private static func connect(_ error: ConnectError) -> String {
        switch error {
        case .handshake:
            String(localized: "无法建立 SSH 连接，请检查地址、端口和主机密钥")
        case .unreachable(let host, let port):
            String(localized: "无法连接到 \(host):\(String(port))")
        case .cancelled:
            String(localized: "连接已取消")
        case .noJumpHosts:
            String(localized: "没有可用的跳板主机")
        case .viewClosed:
            String(localized: "连接视图已关闭")
        case .promptCancelled:
            String(localized: "认证请求已取消")
        }
    }

    private static func knownHosts(_ error: KnownHostsError) -> String {
        switch error {
        case .readFailed(let path):
            String(localized: "无法读取主机信任文件：\(path)")
        case .writeFailed(let path):
            String(localized: "无法写入主机信任文件：\(path)")
        case .corrupt(let path):
            String(localized: "主机信任文件已损坏：\(path)")
        case .unreadable(let path):
            String(localized: "主机信任文件已损坏或无法读取：\(path)")
        case .changedWhileSaving:
            String(localized: "保存主机密钥时发现信任文件已发生变化")
        }
    }

    private static func auth(_ error: AuthError) -> String {
        switch error {
        case .methodsUnknown:
            String(localized: "无法查询服务器支持的认证方式")
        case .agentRejected:
            String(localized: "服务器未接受 SSH Agent 中的密钥")
        case .agentNoPublicKey:
            String(localized: "服务器不接受公钥登录，无法使用 SSH Agent")
        case .rsaHash:
            String(localized: "无法协商 RSA 签名算法")
        case .agentHash:
            String(localized: "无法协商 SSH Agent 签名算法")
        case .keyFailed:
            String(localized: "私钥认证失败")
        case .keyRejected:
            String(localized: "服务器未接受指定的私钥")
        case .noKeyAccepted:
            String(localized: "服务器未接受任何私钥")
        case .keyNotChosen:
            String(localized: "私钥认证需要选择私钥文件")
        case .keyUnreadable(let path):
            String(localized: "无法读取私钥文件：\(path)")
        case .keyTooManyAttempts:
            String(localized: "私钥口令错误次数过多")
        case .passwordFailed:
            String(localized: "密码认证失败")
        case .cancelled:
            String(localized: "认证已取消")
        case .invalidReply:
            String(localized: "认证回复无效")
        case .keyboardStartFailed:
            String(localized: "无法开始交互式认证")
        case .keyboardCancelled:
            String(localized: "交互式认证已取消")
        case .keyboardFailed:
            String(localized: "交互式认证失败")
        case .failed:
            String(localized: "认证失败：服务器未接受可用的认证方式")
        }
    }

    private static func agent(_ error: AgentProblem) -> String {
        switch error {
        case .unreachable(_):
            // A phone has no agent: what the reason says is a computer's.
            String(localized: "手机上没有 SSH Agent，请改用密钥凭据")
        case .empty:
            String(localized: "SSH Agent 中没有密钥")
        case .unsigned:
            String(localized: "SSH Agent 拒绝了签名请求")
        }
    }

    private static func proxy(_ error: ProxyError) -> String {
        switch error {
        case .badCredentials:
            String(localized: "代理服务器拒绝了用户名或密码")
        case .authRequired:
            String(localized: "代理服务器要求认证，请填写代理的用户名和密码")
        case .forbidden(let target):
            String(localized: "代理服务器不允许连接到 \(target)")
        case .replyTooLong:
            String(localized: "代理服务器的回复过长")
        case .closed:
            String(localized: "代理服务器没有回复就关闭了连接")
        case .httpBadGateway(let target):
            String(localized: "代理服务器无法连接到 \(target)：连接失败（HTTP 502）")
        case .httpGatewayTimeout(let target):
            String(localized: "代理服务器无法连接到 \(target)：连接超时（HTTP 504）")
        case .httpRefused(let status):
            String(localized: "代理服务器拒绝了连接：\(status)")
        case .httpUnrecognized:
            String(localized: "代理服务器的回复无法识别，请确认它是 HTTP 代理")
        case .socksUnrecognized:
            String(localized: "代理服务器的回复无法识别，请确认它是 SOCKS5 代理")
        case .socksCredentialsTooLong:
            String(localized: "代理的用户名或密码太长，SOCKS5 最多 255 个字节")
        case .socksNoPasswordAuth:
            String(localized: "代理服务器不接受用户名和密码认证")
        case .socksHostTooLong:
            String(localized: "主机名太长，SOCKS5 最多 255 个字节")
        case .socksRulesForbid(let target):
            String(localized: "代理服务器的规则不允许连接到 \(target)")
        case .socksNetworkUnreachable(let target):
            String(localized: "代理服务器无法连接到 \(target)：网络不可达")
        case .socksHostUnreachable(let target):
            String(localized: "代理服务器无法连接到 \(target)：主机不可达")
        case .socksRefused(let target):
            String(localized: "代理服务器无法连接到 \(target)：连接被拒绝")
        case .socksTimeout(let target):
            String(localized: "代理服务器无法连接到 \(target)：连接超时")
        case .socksInternal(let target):
            String(localized: "代理服务器无法连接到 \(target)：代理服务器内部错误")
        case .socksNoConnect:
            String(localized: "代理服务器不支持 CONNECT 命令")
        case .socksAddressType:
            String(localized: "代理服务器不支持这种地址类型")
        }
    }

    /// Where on the way the connection failed; what went wrong there is the
    /// next link.
    private static func route(_ failure: RouteFailure) -> String {
        switch failure {
        case .jumpDeleted(let number):
            return String(localized: "第 \(String(number)) 台跳板主机已被删除，请编辑这台主机的连接方式")
        case .jump(let name):
            return String(localized: "跳板主机「\(name)」")
        case .jumpForward(let name, let host, let port, let problem):
            let target = "\(host):\(port)"
            switch problem {
            case .connectFailed:
                return String(localized: "跳板主机「\(name)」无法连接到 \(target)：连接失败")
            case .prohibited:
                return String(localized: "跳板主机「\(name)」无法连接到 \(target)：服务器不允许端口转发")
            case .timedOut:
                return String(localized: "跳板主机「\(name)」无法连接到 \(target)：连接超时")
            case .channelFailed:
                return String(localized: "跳板主机「\(name)」无法连接到 \(target)：无法打开转发通道")
            }
        case .proxyUnreachable(let host, let port):
            return String(localized: "无法连接代理服务器 \(host):\(String(port))")
        case .proxy:
            return String(localized: "代理服务器")
        }
    }

    private static func missing(_ need: MissingCredential) -> String {
        switch need {
        case .password(let rejected):
            rejected ? String(localized: "用户名或密码错误") : String(localized: "未填写密码")
        case .passphrase(let rejected):
            rejected ? String(localized: "私钥口令错误") : String(localized: "私钥已加密，未填写口令")
        case .keyboardInteractive:
            String(localized: "服务器要求键盘交互式认证，这里无法完成")
        }
    }

    private static func channel(_ error: ChannelError) -> String {
        switch error {
        case .sessionFailed:
            String(localized: "无法创建 SSH 会话通道")
        case .ptyRefused:
            String(localized: "服务器拒绝创建终端")
        case .shellRefused:
            String(localized: "服务器拒绝启动 Shell")
        case .writeFailed:
            String(localized: "向远程终端写入失败")
        case .resizeFailed:
            String(localized: "调整远程终端尺寸失败")
        case .execChannelFailed:
            String(localized: "无法打开 SSH 通道")
        case .execSendFailed:
            String(localized: "无法发送命令")
        case .execRefused:
            String(localized: "服务器拒绝执行命令")
        case .execTimeout:
            String(localized: "命令超时")
        case .sftpRefused:
            String(localized: "服务器没有开启 SFTP")
        case .sftpTimeout:
            String(localized: "打开 SFTP 超时")
        case .shellOnly:
            String(localized: "这个终端经由堡垒机打开，只能使用终端本身，不能另外执行命令")
        case .shellOnlySftp:
            String(localized: "这个终端经由堡垒机打开，只能使用终端本身，不能另外打开文件")
        }
    }

    private static func noCommon(_ kind: AlgorithmKind, theirs: String) -> String {
        switch kind {
        case .keyExchange:
            String(localized: "无法建立 SSH 连接：和服务器没有共同的密钥交换算法，服务器支持的是 \(theirs)")
        case .hostKey:
            String(localized: "无法建立 SSH 连接：和服务器没有共同的主机密钥算法，服务器支持的是 \(theirs)")
        case .cipher:
            String(localized: "无法建立 SSH 连接：和服务器没有共同的加密算法，服务器支持的是 \(theirs)")
        case .mac:
            String(localized: "无法建立 SSH 连接：和服务器没有共同的消息校验（MAC）算法，服务器支持的是 \(theirs)")
        case .compression:
            String(localized: "无法建立 SSH 连接：和服务器没有共同的压缩算法，服务器支持的是 \(theirs)")
        }
    }

    /// The system's error: its common kinds in words, the rest as the
    /// system says.
    private static func io(_ kind: IoKind, detail: String) -> String {
        switch kind {
        case .connectionRefused:
            String(localized: "连接被拒绝，该端口上没有服务在监听")
        case .connectionReset:
            String(localized: "连接被对方重置")
        case .connectionAborted:
            String(localized: "连接被中止")
        case .notConnected:
            String(localized: "未连接")
        case .timedOut:
            String(localized: "连接超时")
        case .hostUnreachable:
            String(localized: "主机不可达")
        case .networkUnreachable:
            String(localized: "网络不可达")
        case .notFound:
            String(localized: "找不到")
        case .permissionDenied:
            String(localized: "没有权限")
        case .alreadyExists:
            String(localized: "已存在")
        case .storageFull:
            String(localized: "存储空间已满")
        case .closed:
            String(localized: "对方关闭了连接")
        case .other:
            detail
        }
    }
}
