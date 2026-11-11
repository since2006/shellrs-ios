import Foundation
import ShellRSCore

/// Sync in words, as the desktop words it (its locales/sync.yml and the
/// sync part of settings.yml), for a device rather than a computer.
extension Describe {
    /// Why a round or a job failed: a whole sentence, shown alone or after
    /// 「未能同步」.
    static func sync(_ error: Error) -> String {
        guard let error = error as? SyncFailure else {
            return error.localizedDescription
        }
        switch error {
        case .Unavailable:
            return String(localized: "这台设备上没有可用的系统钥匙串，同步的密钥无处保存。")
        case .NotSetUp:
            return String(localized: "同步已关闭。")
        case .InProgress:
            return String(localized: "正在同步，等这一轮结束再试。")
        case .Busy:
            return String(localized: "同步期间数据一直在变，下次再同步。")
        case .NoKeyring:
            return String(localized: "钥匙串里没有同步的密钥，需要再输入一次同步密码。")
        case .NoLogin:
            return String(localized: "钥匙串里没有同步位置的密码或密钥。")
        case .Keychain(let problem):
            return secret(problem)
        case .NotSaved(let detail):
            return String(localized: "同步来的改动未能保存，这一轮没有应用：\(detail)")
        case .StateNotSaved(let detail):
            return String(localized: "同步状态未能保存：\(detail)")
        case .Storage(let problem):
            return storage(problem)
        case .VaultMissing:
            return String(localized: "同步文件夹里没有同步数据。")
        case .VaultExists:
            return String(localized: "另一台设备刚在这个文件夹里开启了同步。重新开启同步，改为加入它。")
        case .VaultTooNew:
            return String(localized: "这个文件夹里的同步来自更新版本的 ShellRS，升级后才能使用。")
        case .BadVault(let detail):
            return String(localized: "同步文件夹里的 vault.json 已损坏：\(detail)")
        case .WrongPassword:
            return String(localized: "同步密码不对。")
        case .NeedsPassword:
            return String(localized: "同步密码已在别的设备上更改。")
        case .VaultReplaced:
            return String(localized: "同步已在别的设备上重置。")
        case .StateUnreadable(let detail):
            return String(localized: "这台设备的同步状态读不出来：\(detail)。关闭同步再开启即可恢复。")
        case .MassDelete(let count, let of):
            return String(localized: "这次同步会删除 \(Int(of)) 条记录中的 \(Int(count)) 条。")
        case .ReadOnly:
            return String(localized: "另一台设备的 ShellRS 更新，这台设备升级后才能继续同步。")
        case .Random:
            return String(localized: "系统的随机数源出错了。")
        case .Password(let problem):
            return password(problem)
        case .OtherPlace:
            return String(localized: "只能重新登录同步正在用的位置。")
        case .NoSuchDevice:
            return String(localized: "同步里没有这台设备。")
        case .LocationNotSaved(let detail):
            return String(localized: "同步已设好，但没能记下同步的位置，下次打开 ShellRS 时同步是关闭的：\(detail)")
        case .BadSetupCode:
            return String(localized: "这不是有效的配置码，可能没有复制完整。")
        case .SetupCodeTooNew:
            return String(localized: "这个配置码来自更新版本的 ShellRS，升级后才能使用。")
        case .SetupCodeWrongPassword:
            return String(localized: "同步密码不对，或者这个配置码是更换同步密码之前生成的。")
        case .Closed:
            return String(localized: "已关闭")
        case .Internal(let detail):
            return detail
        }
    }

    /// What the server or the bucket said.
    static func storage(_ problem: StorageProblem) -> String {
        switch problem {
        case .notFound:
            String(localized: "同步文件夹里找不到需要的文件。")
        case .preconditionFailed:
            String(localized: "同步文件夹里的文件刚被别的设备改过，稍后再试。")
        case .tooLarge:
            String(localized: "同步文件夹里有文件大得不正常。")
        case .timeout:
            String(localized: "同步文件夹没有响应。")
        case .unauthorized:
            String(localized: "同步的位置拒绝了访问：检查用户名和密码，或文件夹的权限。")
        case .unavailable(let detail):
            String(localized: "同步文件夹暂时用不了：\(detail)")
        case .io(let detail):
            String(localized: "读写同步文件夹失败：\(detail)")
        }
    }

    /// What is wrong with a sync password as typed.
    static func password(_ problem: PasswordProblem) -> String {
        switch problem {
        case .missing:
            String(localized: "输入同步密码。")
        case .tooShort:
            String(localized: "同步密码至少要 \(Int(minSyncPasswordLength())) 个字符。")
        case .mismatch:
            String(localized: "两次输入的同步密码不一样。")
        }
    }

    /// What is wrong with a server's or a bucket's login as typed.
    static func login(_ error: Error) -> String {
        guard let problem = error as? LoginProblem else {
            return sync(error)
        }
        switch problem {
        case .UrlInvalid:
            return String(localized: "地址要以 https:// 或 http:// 开头，比如 https://dav.example.com/ShellRS。")
        case .UsernameMissing:
            return String(localized: "输入用户名。")
        case .PasswordMissing:
            return String(localized: "输入密码。")
        case .EndpointInvalid:
            return String(localized: "服务地址要以 https:// 或 http:// 开头，比如 Cloudflare R2 的 https://<ACCOUNT_ID>.r2.cloudflarestorage.com。")
        case .BucketInvalid:
            return String(localized: "输入存储桶的名称。")
        case .AccessKeyMissing:
            return String(localized: "输入 Access Key ID。")
        case .SecretKeyMissing:
            return String(localized: "输入 Secret Access Key。")
        }
    }

    /// What only the user can settle, as the page and the notice say it.
    static func attention(_ attention: Attention) -> String {
        switch attention {
        case .needsPassword:
            String(localized: "同步密码已在别的设备上更改，输入新密码后继续同步。")
        case .vaultReplaced:
            String(localized: "同步已在别的设备上重置，重新加入后继续同步。")
        case .removed:
            String(localized: "这台设备已在别的设备上被移出同步，同步已暂停。")
        case .massDelete(let count, _):
            String(localized: "这次同步会删除 \(Int(count)) 条记录，等你确认。")
        case .loginRefused:
            String(localized: "同步的位置拒绝了这台设备的登录信息，重新登录后继续同步。")
        }
    }

    /// The system a device runs, as people call it.
    static func platform(_ platform: String) -> String {
        switch platform {
        case "macos": "macOS"
        case "windows": "Windows"
        case "linux": "Linux"
        case "ios": "iOS"
        case "android": "Android"
        default: platform
        }
    }
}
