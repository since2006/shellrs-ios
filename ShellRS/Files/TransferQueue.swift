import Foundation
import ShellRSCore

/// What a batch copies, as the user asked for it.
enum TransferJob: Equatable {
    /// Local files into a remote folder. `staging` holds the copies the app
    /// made of what the user picked, and goes once the batch is over.
    case upload(sources: [URL], destination: String, staging: URL)
    /// Remote files and folders into a local folder. A `preview` brings one
    /// file down into 已下载的文件 to look at, and shows it once there.
    case download(sources: [String], destination: URL, preview: Bool)

    var direction: TransferDirection {
        switch self {
        case .upload: .upload
        case .download: .download
        }
    }

    /// Bringing a file down to look at: given up rather than stopped, as it
    /// is wanted now or not at all.
    var isPreview: Bool {
        if case .download(_, _, true) = self {
            return true
        }
        return false
    }

    /// The one item by name, or how many there are.
    var title: String {
        let names: [String] =
            switch self {
            case .upload(let sources, _, _): sources.map(\.lastPathComponent)
            case .download(let sources, _, _): sources.map(RemotePath.name)
            }
        if names.count == 1 {
            return names[0]
        }
        return String(localized: "\(names.count) 个项目")
    }

    /// Where the items go.
    var destination: String {
        switch self {
        case .upload(_, let destination, _):
            destination
        case .download:
            String(localized: "已下载的文件")
        }
    }
}

/// Why a batch left the queue before it was done.
enum Removal: Equatable {
    /// 移出队列 after it stopped.
    case takenOff
    /// 丢弃续传进度.
    case discarded
    /// It could not be handed to the engine.
    case notStarted(String)
}

/// A batch in the queue.
struct TransferEntry: Identifiable, Equatable {
    /// Where a batch stands.
    enum State: Equatable {
        /// Waiting its turn.
        case pending
        /// Handed to the engine: scanning, transferring, waiting on a
        /// question or reconnecting.
        case active
        /// Stopped with its progress kept. It holds the head of the queue
        /// until the user resumes it, discards it or takes it off.
        case stopped
        /// Done, some items perhaps skipped or failed.
        case done
        /// Taken off after it stopped, its progress discarded, or never
        /// started.
        case removed

        var isFinished: Bool {
            self == .done || self == .removed
        }
    }

    let id: Int
    let job: TransferJob
    fileprivate(set) var started = false
    fileprivate(set) var removal: Removal?
    /// The engine's last word on this batch.
    fileprivate(set) var progress: TransferProgress?

    var state: State {
        if removal != nil {
            return .removed
        }
        switch progress?.phase {
        case nil where !started: return .pending
        case .stopped: return .stopped
        case .completed: return .done
        default: return .active
        }
    }

    /// Where it stands in words, for everything but a running transfer's
    /// bar, which shows the percentage beside it.
    var status: String {
        switch state {
        case .pending:
            return String(localized: "等待中")
        case .active:
            switch progress?.phase {
            case nil, .scanning:
                return String(localized: "正在扫描")
            case .waiting:
                return String(localized: "等待回答")
            case .reconnecting:
                return progress?.note.map(Describe.firstLink) ?? String(localized: "正在重连")
            default:
                return Self.percent(progress?.fraction ?? 0)
            }
        case .stopped:
            return String(localized: "已停止")
        case .done:
            let failed = progress?.failed ?? 0
            return failed == 0
                ? String(localized: "已完成") : String(localized: "部分失败（\(Int(failed)) 项）")
        case .removed:
            switch removal {
            case .discarded:
                return String(localized: "已丢弃续传进度")
            case .notStarted(let reason):
                return String(localized: "无法开始：\(reason)")
            case .takenOff, nil:
                return String(localized: "已移出")
            }
        }
    }

    /// `0.294` as 「29%」.
    static func percent(_ fraction: Float) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }
}

/// The transfers of an SFTP session, as WinSCP and the desktop keep them:
/// batches waiting their turn, the one being transferred, and the ones
/// that have ended. The engine runs one batch at a time and knows nothing
/// of what waits behind it.
struct TransferQueue: Equatable {
    private(set) var entries: [TransferEntry] = []
    private var nextId = 0

    @discardableResult
    mutating func push(_ job: TransferJob) -> Int {
        nextId += 1
        entries.append(TransferEntry(id: nextId, job: job))
        return nextId
    }

    /// The batch the engine has: running, or stopped and kept for 继续.
    var head: TransferEntry? {
        headIndex.map { entries[$0] }
    }

    private var headIndex: Int? {
        entries.firstIndex { $0.state == .active || $0.state == .stopped }
    }

    /// The next batch to hand the engine, now marked as started: the first
    /// one waiting, unless another still holds the head.
    @discardableResult
    mutating func startNext() -> TransferEntry? {
        guard headIndex == nil,
            let index = entries.firstIndex(where: { $0.state == .pending })
        else {
            return nil
        }
        entries[index].started = true
        return entries[index]
    }

    /// The engine reports on the batch it has, which is the head. A report
    /// with no head, such as the empty one after 丢弃续传进度, is dropped.
    mutating func onProgress(_ progress: TransferProgress) {
        if let index = headIndex {
            entries[index].progress = progress
        }
    }

    /// The head leaves the queue: it could not be handed over, or its
    /// progress is being discarded.
    mutating func abandonHead(_ why: Removal) {
        if let index = headIndex {
            entries[index].removal = why
        }
    }

    /// A running head the engine went away under stops, as the engine
    /// would have stopped it.
    mutating func stopHead() {
        guard let index = headIndex, entries[index].state == .active else {
            return
        }
        var progress =
            entries[index].progress
            ?? TransferProgress(
                direction: entries[index].job.direction, phase: .stopped, current: "",
                completedBytes: 0, totalBytes: 0, total: 0, succeeded: 0, skipped: 0, failed: 0,
                deleted: 0, bytesPerSecond: 0, fraction: 0, remainingSeconds: nil,
                elapsedSeconds: 0, note: nil, details: [])
        progress.phase = .stopped
        progress.bytesPerSecond = 0
        progress.remainingSeconds = nil
        entries[index].progress = progress
    }

    /// A stopped head handed to an engine that does not have it starts
    /// over: the engine finds what it had done and asks to resume it.
    mutating func restartHead() {
        if let index = headIndex, entries[index].state == .stopped {
            entries[index].progress = nil
        }
    }

    /// Take a batch off the queue. One waiting or ended goes; a stopped
    /// head stays listed as taken off, and the queue moves on past it. A
    /// running batch has to stop first. Returns what went, if anything.
    @discardableResult
    mutating func remove(_ id: Int) -> TransferEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        switch entries[index].state {
        case .active:
            return nil
        case .stopped:
            entries[index].removal = .takenOff
            return entries[index]
        default:
            return entries.remove(at: index)
        }
    }

    var hasFinished: Bool {
        entries.contains { $0.state.isFinished }
    }

    /// 清除已完成: returns what went.
    mutating func clearFinished() -> [TransferEntry] {
        let finished = entries.filter { $0.state.isFinished }
        entries.removeAll { $0.state.isFinished }
        return finished
    }

    /// Batches not yet ended: waiting, running or stopped.
    var unfinishedCount: Int {
        entries.filter { !$0.state.isFinished }.count
    }
}

/// Remote paths, which are always `/`-separated.
enum RemotePath {
    /// `name` in `folder`.
    static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }

    /// The last part of `path`.
    static func name(_ path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    /// The folder `path` is in: 「/home/me」 gives 「/home」, 「/etc」 gives
    /// 「/」.
    static func parent(_ path: String) -> String {
        ancestors(of: path).dropLast().last ?? "/"
    }

    /// `paths` by the folder each is in, in the order they come.
    static func byFolder(_ paths: [String]) -> [(folder: String, paths: [String])] {
        var folders: [(folder: String, paths: [String])] = []
        for path in paths {
            let folder = parent(path)
            if let index = folders.firstIndex(where: { $0.folder == folder }) {
                folders[index].paths.append(path)
            } else {
                folders.append((folder, [path]))
            }
        }
        return folders
    }

    /// The folders from the top down to `path`, without `/` itself:
    /// 「/home/me」 gives 「/home」, 「/home/me」.
    static func ancestors(of path: String) -> [String] {
        var folders: [String] = []
        var current = ""
        for part in path.split(separator: "/") {
            current += "/" + part
            folders.append(current)
        }
        return folders
    }
}
