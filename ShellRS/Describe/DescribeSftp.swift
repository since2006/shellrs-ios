import Foundation
import ShellRSCore

/// The SFTP engine's failures, questions and notes, worded as the desktop
/// words them (its locales/sftp.yml).
extension Describe {
    /// Whether `link` puts what lies under it in a sentence of its own,
    /// such as 「无法上传：…」, which ends the chain there.
    static func saysTheRest(_ link: FailureLink) -> Bool {
        switch link {
        case .sftp(.listFailed), .sftp(.deleteFailed), .upload(.failed), .download(.failed),
            .edit(.interrupted):
            true
        default:
            false
        }
    }

    /// Why an SFTP session has no channel now.
    static func disconnect(_ reason: SftpDisconnect) -> String {
        switch reason {
        case .byUser:
            String(localized: "SFTP 已断开")
        case .dropped:
            String(localized: "SFTP 连接中断，请重新连接")
        case .droppedKept:
            String(localized: "连接中断，传输进度已保留")
        case .loginFailed(let failure):
            Self.failure(failure)
        case .failed(let failure):
            firstLink(failure)
        }
    }

    static func sftp(_ error: SftpError, rest: ArraySlice<FailureLink>) -> String {
        switch error {
        case .startTimeout:
            String(localized: "启动 SFTP 超时")
        case .noV3:
            String(localized: "服务器未提供 SFTP v3")
        case .noPath:
            String(localized: "服务器未返回目录路径")
        case .noLinkTarget:
            String(localized: "无法读取链接目标")
        case .ambiguousName:
            String(localized: "远端名称包含无法可靠表示的字符，已停止操作")
        case .remotePathInvalid:
            String(localized: "远程路径不能为空或包含空字符")
        case .fileNameInvalid(let name):
            String(localized: "无效的文件名：\(name)")
        case .nothingToUpload:
            String(localized: "请选择要上传的文件或目录")
        case .nothingToDownload:
            String(localized: "请选择要下载的文件或目录")
        case .downloadTargetRelative:
            String(localized: "下载目标必须是绝对路径")
        case .fileNameNotUtf8:
            String(localized: "目录包含无法用 UTF-8 表示的文件名")
        case .exists(let name):
            String(localized: "已有名为「\(name)」的项目")
        case .hostKeyChanged:
            String(localized: "服务器主机指纹已改变，已停止续传")
        case .notConnected:
            String(localized: "SFTP 未连接，请重新连接")
        case .noConnection:
            String(localized: "SFTP 未连接")
        case .listFailed:
            String(localized: "无法读取目录：\(chain(rest))")
        case .deleteFailed:
            String(localized: "无法删除：\(chain(rest))")
        case .busy:
            String(localized: "已有传输批次正在处理")
        case .localFolderMissing(let path):
            String(localized: "本地目录 \(path) 不存在")
        case .remoteFolderMissing(let path):
            String(localized: "远程目录 \(path) 不存在")
        case .notAFolder(let path):
            String(localized: "远程路径 \(path) 不是目录")
        case .syncToRoot:
            String(localized: "不能同步到根目录 /")
        case .reconnectIn(let seconds, let attempt):
            String(localized: "将在 \(Int(seconds)) 秒后重连（\(Int(attempt))/3）")
        }
    }

    static func upload(_ error: UploadError, rest: ArraySlice<FailureLink>) -> String {
        switch error {
        case .sourceNameNotUtf8:
            String(localized: "来源文件名不是有效的 UTF-8")
        case .targetBusy:
            String(localized: "另一个传输正在上传同一目标，请稍后继续上传")
        case .parentMissing:
            String(localized: "父目录未创建，无法上传")
        case .failed:
            String(localized: "无法上传：\(chain(rest))")
        case .folderInTheWay:
            String(localized: "目录与文件类型冲突，不会删除远程目录")
        case .exists(let size, let modified):
            String(localized: "远程项目已存在（\(existing(size, modified))）。覆盖会替换这个文件或链接。")
        case .existsChanged(let size, let modified):
            String(
                localized:
                    "目标在上传期间发生变化。远程项目已存在（\(existing(size, modified))）。覆盖会替换这个文件或链接。")
        case .targetGone:
            String(localized: "原目标在上传期间已被删除或移走。是否继续发布此文件？")
        case .sourceNowFolder:
            String(localized: "来源已变为目录，请丢弃旧文件进度后重新上传，或跳过。")
        case .targetNotFolder:
            String(localized: "目标已存在且不是目录，不会跟随或替换链接")
        case .specialFile:
            String(localized: "不支持上传设备、套接字或其他特殊文件")
        case .resumeFound:
            String(localized: "发现未完成的 .filepart 文件。续传会按它的现有大小跳过本地文件前缀，请确认本地文件仍是同一版本。")
        case .linkTargetNotUtf8:
            String(localized: "链接目标不是有效的 UTF-8")
        case .recordWithoutLink:
            String(localized: "续传记录中缺少链接目标")
        case .temporaryLinkChanged:
            String(localized: "临时链接已变化，无法继续上传")
        case .recordWithoutSource:
            String(localized: "续传记录中缺少来源文件信息")
        case .temporaryKindChanged:
            String(localized: "远端临时文件类型已变化")
        case .partialTooLarge:
            String(localized: "远端续传偏移大于本地文件")
        case .pipelineEnded:
            String(localized: "上传写入流水线意外结束")
        case .publishUnconfirmed:
            String(localized: "无法确认文件发布结果，已保留恢复文件；请检查远端目录")
        case .temporaryChanged:
            String(localized: "临时文件大小或类型已变化，未替换目标")
        case .targetCreated:
            String(localized: "替换期间目标被其他操作创建，已保留目标、备份和临时文件")
        case .backupChanged:
            String(localized: "恢复备份已变化，停止替换")
        case .backupChangedAfterPublish:
            String(localized: "备份已变化，未清理；上传的目标文件已发布")
        case .backupAndTarget:
            String(localized: "存在恢复备份和目标文件，请先检查远端目录；未删除任何文件")
        }
    }

    static func download(_ error: DownloadError, rest: ArraySlice<FailureLink>) -> String {
        switch error {
        case .nameInvalid(let name):
            String(localized: "名称「\(name)」在本机无效")
        case .sourceMissing:
            String(localized: "远程项目不存在")
        case .targetBusy:
            String(localized: "另一个传输正在下载到同一位置，请稍后继续下载")
        case .parentMissing:
            String(localized: "父目录未创建，无法下载")
        case .failed:
            String(localized: "无法下载：\(chain(rest))")
        case .targetInvalid:
            String(localized: "无效的下载目标")
        case .folderInTheWay:
            String(localized: "本地已有同名目录，不会删除它")
        case .exists(let size, let modified):
            String(localized: "本地已有同名项目（\(existing(size, modified))）。覆盖会替换它。")
        case .existsChanged(let size, let modified):
            String(
                localized:
                    "目标在下载期间发生变化。本地已有同名项目（\(existing(size, modified))）。覆盖会替换它。")
        case .fileInTheWay:
            String(localized: "本地已有同名文件，不会替换为目录")
        case .specialFile:
            String(localized: "不支持下载设备、套接字或其他特殊文件")
        case .partialNotFile(let path):
            String(localized: "临时文件 \(path) 不是普通文件")
        case .partialTooLarge:
            String(localized: "本地 .filepart 文件比远程文件大，无法续传。")
        case .sourceChanged:
            String(localized: "远程文件在上次下载后已变化，无法续传。")
        case .resumeFound:
            String(localized: "发现未完成的 .filepart 文件。续传会按它的现有大小跳过远程文件前缀，请确认远程文件仍是同一版本。")
        case .pipelineEnded:
            String(localized: "下载读取流水线意外结束")
        case .sourceShrank:
            String(localized: "远程文件在下载期间变短，已停止")
        case .linksUnsupported:
            String(localized: "此系统不支持创建符号链接")
        }
    }

    static func journal(_ error: JournalError) -> String {
        switch error {
        case .sourceNotFile:
            String(localized: "本地来源已不再是普通文件")
        case .mismatch:
            String(localized: "续传记录与当前来源或服务器不匹配")
        case .temporaryInvalid:
            String(localized: "无效的续传临时路径")
        case .replacesFolder:
            String(localized: "续传记录不能替换目录")
        case .uploadDamaged:
            String(localized: "续传记录损坏，原文件和临时文件均已保留")
        case .downloadDamaged:
            String(localized: "续传记录损坏，临时文件已保留")
        case .unreadable:
            String(localized: "无法读取续传记录")
        case .unsaved:
            String(localized: "无法保存续传进度")
        }
    }

    static func edit(_ error: EditError, rest: ArraySlice<FailureLink>) -> String {
        switch error {
        case .missing:
            String(localized: "文件不存在")
        case .shrank:
            String(localized: "文件在读取时变短了，请重新打开")
        case .goneAfterSave:
            String(localized: "保存后找不到文件")
        case .interrupted:
            // Said by what cut the write short.
            chain(rest)
        }
    }

    /// What the server answered a request with. A plain failure is the
    /// server's own words, when it has any beyond the status's name.
    static func sftpStatus(_ status: SftpStatus, message: String) -> String {
        switch status {
        case .eof:
            String(localized: "已读到文件末尾")
        case .noSuchFile:
            String(localized: "文件或目录不存在")
        case .permissionDenied:
            String(localized: "没有权限")
        case .failure:
            message.isEmpty || message == "Failure"
                ? String(localized: "服务器报告操作失败") : message
        case .badMessage:
            String(localized: "服务器无法识别这个请求")
        case .noConnection:
            String(localized: "SFTP 未连接")
        case .connectionLost:
            String(localized: "SFTP 连接已断开")
        case .opUnsupported:
            String(localized: "服务器不支持这个操作")
        }
    }

    /// What is in the way: its size, and when it was changed if known.
    private static func existing(_ size: UInt64, _ modified: UInt64?) -> String {
        let size = Format.size(size)
        guard let modified else {
            return size
        }
        let date = Format.date(Date(timeIntervalSince1970: TimeInterval(modified)))
        return String(localized: "\(size)，修改时间 \(date)")
    }
}

/// Sizes and times as the file lists show them.
enum Format {
    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    /// `seconds` as 「1 分 5 秒」.
    static func duration(_ seconds: UInt64) -> String {
        Duration.seconds(Int64(clamping: seconds)).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}
