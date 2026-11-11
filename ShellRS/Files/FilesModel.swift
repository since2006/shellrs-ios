import Foundation
import Observation
import ShellRSCore
import UIKit

/// Files on a terminal's host over SFTP, on the terminal's own connection:
/// browsing, changing, and a queue of transfers that run one batch at a
/// time, as the desktop's SFTP tab does.
@MainActor
@Observable
final class FilesModel {
    enum State: Equatable {
        case connecting
        case connected
        /// A transfer's connection dropped; the engine reconnects on its own.
        case reconnecting
        /// Why, if something went wrong.
        case disconnected(String?)
    }

    private(set) var state = State.disconnected(nil)
    /// The user's home folder, where browsing starts.
    private(set) var home = "/"
    /// The folders shown above `/`, deepest last.
    var path: [String] = []
    @ObservationIgnored private var folderStates: [String: FolderState] = [:]

    func folderState(for folder: String) -> FolderState {
        if let state = folderStates[folder] { return state }
        let state = FolderState()
        folderStates[folder] = state
        return state
    }
    private(set) var queue = TransferQueue()
    /// What the running batch asks the user now.
    private(set) var question: TransferQuestion?
    /// A transfer's trouble outside any one file, to show once.
    var notice: String?
    /// A file brought down to look at.
    var preview: URL?
    /// Bumped when a folder's contents changed, so it is read again.
    private(set) var revisions: [String: Int] = [:]
    /// Bumped when a download into 已下载的文件 is done.
    private(set) var downloads = 0

    /// Opens a session on the terminal's connection.
    @ObservationIgnored private let opener: @MainActor () async throws -> SftpSession
    /// Where 下载 puts what it brings down: the host's folder in 已下载的文件,
    /// in which each file goes where it is on the server.
    @ObservationIgnored let downloadsFolder: URL
    @ObservationIgnored private var session: SftpSession?
    @ObservationIgnored private var ended = false
    /// Whether the engine runs a batch: it takes no other till idle.
    @ObservationIgnored private var engineBusy = false
    /// Whether the engine has the stopped head, to resume it; one opened
    /// since does not, and is handed the batch again.
    @ObservationIgnored private var engineHasHead = false
    /// 继续 waits for a session free to take it: asked for while there was
    /// none or the engine was still busy, or a batch was cut short.
    @ObservationIgnored private var pendingResume = false
    /// The head was handed to an engine that did not have it: what it finds
    /// done goes on without asking, as 继续 already said.
    @ObservationIgnored private var resubmitted = false
    /// Why the last reconnect of a transfer failed.
    @ObservationIgnored private var reconnectFailure: String?
    /// The batch being given up: discarded once it has stopped.
    @ObservationIgnored private var abandoning: Int?
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(
        downloadsFolder: URL,
        opener: @escaping @MainActor () async throws -> SftpSession
    ) {
        self.downloadsFolder = downloadsFolder
        self.opener = opener
    }

    func revision(of folder: String) -> Int {
        revisions[folder, default: 0]
    }

    // MARK: The session

    /// Opens the session unless it is open or opening.
    func open() {
        guard !ended, session == nil, state != .connecting else {
            return
        }
        state = .connecting
        Task {
            await connect()
        }
    }

    /// The terminal's connection is up again: a session lost with the old
    /// one opens on it, and a batch cut short goes on.
    func terminalConnected() {
        if case .disconnected = state {
            open()
        }
    }

    /// The terminal's connection closed, and the session on it with it. A
    /// phone's connection does not come back, so the engine's reconnecting
    /// would only wait: the session goes now.
    func terminalClosed() {
        if session != nil {
            lost(String(localized: "终端已断开，重新连接终端后继续"))
        }
    }

    /// Ends the session and the transfers for good: the terminal closed.
    func end() {
        ended = true
        session?.end()
        session = nil
        state = .disconnected(nil)
        question = nil
        for entry in queue.entries {
            clean(entry.job)
        }
        endBackgroundTask()
    }

    private func connect() async {
        do {
            let session = try await opener()
            guard !ended else {
                session.end()
                return
            }
            self.session = session
            engineBusy = false
            engineHasHead = false
            home = session.home()
            if path.isEmpty {
                path = RemotePath.ancestors(of: home)
            }
            state = .connected
            pump(session)
            resumeIfReady()
            startNextIfIdle()
        } catch SshError.NotConnected {
            state = .disconnected(String(localized: "终端未连接，重新连接终端后才能浏览文件"))
        } catch {
            state = .disconnected(String(localized: "无法启动 SFTP：\(Describe.ssh(error))"))
        }
    }

    private func pump(_ session: SftpSession) {
        Task { [weak self] in
            while let event = await session.nextEvent() {
                guard let self, self.session === session else {
                    return
                }
                handle(event)
            }
            guard let self, self.session === session else {
                return
            }
            lost(String(localized: "SFTP 已断开"))
        }
    }

    private func handle(_ event: SftpEvent) {
        switch event {
        case .connected:
            state = .connected
            reconnectFailure = nil
        case .disconnected(let reason):
            switch reason {
            case .droppedKept:
                state = .reconnecting
            case .failed(let failure):
                // The engine tries again, or stops the batch, which ends it.
                reconnectFailure = Describe.firstLink(failure)
            case .byUser, .dropped, .loginFailed:
                lost(Describe.disconnect(reason))
            }
        case .progress(let progress):
            let head = queue.head
            queue.onProgress(progress)
            if queue.head?.state != .active {
                question = nil
            }
            if let head, let now = queue.entries.first(where: { $0.id == head.id }) {
                finished(now)
            }
            if state == .reconnecting, progress.phase == .stopped {
                lost(reconnectFailure ?? Describe.disconnect(.droppedKept))
            }
        case .question(let question) where resubmitted && question.kind == .resume:
            try? session?.answer(
                questionId: question.id, answer: TransferAnswer(choice: .resume, applyToAll: true))
        case .question(let question):
            self.question = question
        case .notice(let failure):
            notice = Describe.firstLink(failure)
        case .idle:
            engineBusy = false
            resubmitted = false
            if abandonIfStopped() {
                return
            }
            resumeIfReady()
            startNextIfIdle()
        }
    }

    /// The session is gone: the next browse or transfer opens another, and
    /// a batch it cut short goes on there.
    private func lost(_ reason: String?) {
        if queue.head?.state == .active || state == .reconnecting {
            pendingResume = true
        }
        session?.end()
        session = nil
        engineBusy = false
        engineHasHead = false
        question = nil
        queue.stopHead()
        state = .disconnected(reason)
        endBackgroundTask()
        abandonIfStopped()
    }

    // MARK: Browsing and changing

    func list(_ folder: String) async throws -> [DirectoryEntry] {
        try await connected().list(path: folder).entries
    }

    func createFolder(_ name: String, in folder: String) async throws {
        try await connected().createDirectory(path: RemotePath.join(folder, name))
        touch(folder)
    }

    func rename(_ name: String, to newName: String, in folder: String) async throws {
        try await connected().rename(
            from: RemotePath.join(folder, name), to: RemotePath.join(folder, newName))
        touch(folder)
    }

    func delete(_ names: [String], in folder: String) async throws {
        defer { touch(folder) }
        try await connected().delete(paths: names.map { RemotePath.join(folder, $0) })
    }

    /// Reads `folder` again wherever it shows.
    func touch(_ folder: String) {
        revisions[folder, default: 0] += 1
    }

    private func connected() throws -> SftpSession {
        guard let session, state == .connected else {
            throw SshError.NotConnected
        }
        return session
    }

    // MARK: Transfers

    /// Brings `paths` down into 已下载的文件, each where it is on the
    /// server, so two of a name in different folders are two files there.
    /// A batch for each folder they are in: the one a selection is in.
    /// Returns the last batch.
    @discardableResult
    func download(_ paths: [String]) -> Int? {
        var batch: Int?
        for (folder, sources) in RemotePath.byFolder(paths) {
            guard let destination = localFolder(folder) else {
                return batch
            }
            batch = enqueue(.download(sources: sources, destination: destination, preview: false))
        }
        return batch
    }

    /// Shows the file at `path`, which the folder listed as `entry`: a
    /// download into 已下载的文件 that shows the file once there, or the copy
    /// there at once if it is the same. One there that is not is asked
    /// about as a download asks. Returns the batch that brings it down.
    @discardableResult
    func preview(_ path: String, as entry: DirectoryEntry) -> Int? {
        if let copy = downloaded(path, as: entry) {
            preview = copy
            return nil
        }
        guard let destination = localFolder(RemotePath.parent(path)) else {
            return nil
        }
        return enqueue(.download(sources: [path], destination: destination, preview: true))
    }

    /// The copy of the file at `path` in 已下载的文件, if it is the same as
    /// `entry` says the server's is: a download gives it the server's time.
    func downloaded(_ path: String, as entry: DirectoryEntry) -> URL? {
        let copy = local(path)
        return LocalFolders.same(copy, as: entry) ? copy : nil
    }

    /// Where `path` on the server goes in 已下载的文件.
    func local(_ path: String, directoryHint: URL.DirectoryHint = .inferFromPath) -> URL {
        let relative = path.drop { $0 == "/" }
        return relative.isEmpty
            ? downloadsFolder
            : downloadsFolder.appending(path: String(relative), directoryHint: directoryHint)
    }

    /// The folder `folder` on the server goes to, made if need be.
    private func localFolder(_ folder: String) -> URL? {
        let url = local(folder, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    /// Uploads what the user picked into `folder`: copies of it, made
    /// first, as the files picked may be out of reach by the batch's turn.
    func upload(_ urls: [URL], to folder: String) async {
        let staging = LocalFolders.uploads.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            let sources = try await Task.detached {
                try LocalFolders.copy(urls, into: staging)
            }.value
            enqueue(.upload(sources: sources, destination: folder, staging: staging))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            notice = String(localized: "无法读取选择的文件：\(error.localizedDescription)")
        }
    }

    /// Uploads into `folder` what was dropped on it, kept by
    /// `LocalFolders.keep`: one batch, as the files picked are.
    func upload(dropped: [URL], to folder: String) {
        let staging = LocalFolders.uploads.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            let sources = try LocalFolders.gather(dropped, into: staging)
            enqueue(.upload(sources: sources, destination: folder, staging: staging))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            for file in dropped {
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
            notice = String(localized: "无法读取拖入的文件：\(error.localizedDescription)")
        }
    }

    /// Stops the running batch, keeping what is done.
    func cancel() {
        try? session?.cancel()
    }

    /// Goes on with the stopped head, once there is a session free for it.
    func resume() {
        guard queue.head?.state == .stopped else {
            return
        }
        pendingResume = true
        if session == nil {
            open()
        } else {
            resumeIfReady()
        }
    }

    private func resumeIfReady() {
        guard pendingResume, let session, state == .connected, !engineBusy,
            let head = queue.head, head.state == .stopped
        else {
            return
        }
        pendingResume = false
        engineBusy = true
        do {
            if engineHasHead {
                try session.resume()
            } else {
                queue.restartHead()
                resubmitted = true
                try submit(head.job, to: session)
                engineHasHead = true
            }
        } catch {
            engineBusy = false
            notice = Describe.ssh(error)
        }
        updateBackgroundTask()
    }

    /// Gives up the stopped head, removing what it left half done when the
    /// engine still has it.
    func discard() {
        guard let head = queue.head, head.state == .stopped, !engineBusy else {
            return
        }
        pendingResume = false
        queue.abandonHead(.discarded)
        clean(head.job)
        if let session, engineHasHead, state == .connected {
            engineBusy = true
            engineHasHead = false
            try? session.discard()
        } else {
            startNextIfIdle()
        }
    }

    /// Gives up the batch `id`, leaving nothing of it: one waiting leaves
    /// the queue; one running stops, and goes with what it left half done
    /// once it has.
    func abandon(_ id: Int) {
        guard let entry = queue.entries.first(where: { $0.id == id }) else {
            return
        }
        switch entry.state {
        case .pending:
            remove(entry)
        case .active:
            abandoning = id
            cancel()
        case .stopped:
            abandoning = id
            abandonIfStopped()
        case .done, .removed:
            break
        }
    }

    /// Discards the batch being given up once it has stopped and the
    /// engine is free, and takes it off the list. Whether it did.
    @discardableResult
    private func abandonIfStopped() -> Bool {
        guard let abandoning, let head = queue.head, head.id == abandoning,
            head.state == .stopped, !engineBusy
        else {
            return false
        }
        self.abandoning = nil
        discard()
        queue.remove(abandoning)
        return true
    }

    func remove(_ entry: TransferEntry) {
        let head = queue.head?.id == entry.id
        guard let removed = queue.remove(entry.id) else {
            return
        }
        clean(removed.job)
        // The engine keeps a stopped head taken off till the next batch
        // replaces it: there is nothing to resume now.
        if head {
            pendingResume = false
            engineHasHead = false
        }
        startNextIfIdle()
    }

    func clearFinished() {
        for entry in queue.clearFinished() {
            clean(entry.job)
        }
    }

    func answer(_ choice: TransferChoice, toAll: Bool = false) {
        guard let question else {
            return
        }
        self.question = nil
        try? session?.answer(
            questionId: question.id, answer: TransferAnswer(choice: choice, applyToAll: toAll))
    }

    @discardableResult
    private func enqueue(_ job: TransferJob) -> Int {
        let id = queue.push(job)
        if session == nil {
            open()
        }
        startNextIfIdle()
        return id
    }

    /// Hands the engine the next batch if it is free for one.
    private func startNextIfIdle() {
        while let session, state == .connected, !engineBusy, let entry = queue.startNext() {
            do {
                try submit(entry.job, to: session)
                engineBusy = true
                engineHasHead = true
            } catch {
                queue.abandonHead(.notStarted(Describe.ssh(error)))
                clean(entry.job)
            }
        }
        updateBackgroundTask()
    }

    private func submit(_ job: TransferJob, to session: SftpSession) throws {
        switch job {
        case .upload(let sources, let destination, _):
            try session.upload(sources: sources.map(\.path), destination: destination)
        case .download(let sources, let destination, _):
            try session.download(sources: sources, destination: destination.path)
        }
    }

    /// What a batch that ended leaves to do.
    private func finished(_ entry: TransferEntry) {
        guard entry.state == .done else {
            return
        }
        switch entry.job {
        case .upload(_, let destination, let staging):
            try? FileManager.default.removeItem(at: staging)
            touch(destination)
        case .download(let sources, let destination, let shows):
            downloads += 1
            // What came down, or the copy there the user chose to keep.
            if shows, let progress = entry.progress, progress.succeeded + progress.skipped > 0,
                let source = sources.first
            {
                let copy = destination.appending(path: RemotePath.name(source))
                if FileManager.default.fileExists(atPath: copy.path) {
                    preview = copy
                }
            }
        }
    }

    /// What a batch leaving the queue no longer needs: the copies made for
    /// an upload.
    private func clean(_ job: TransferJob) {
        if case .upload(_, _, let staging) = job {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    // MARK: Running in the background

    /// A transfer under way asks iOS for the time it gives an app that
    /// leaves the screen, so a quick look elsewhere does not stop it.
    private func updateBackgroundTask() {
        if engineBusy {
            guard backgroundTask == .invalid else {
                return
            }
            backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "SFTP transfer"
            ) { [weak self] in
                MainActor.assumeIsolated {
                    self?.endBackgroundTask()
                }
            }
        } else {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// The app's own folders for files.
enum LocalFolders {
    /// What the user downloads, which the Files app shows too: a folder
    /// for each host.
    static var downloads: URL {
        URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// The folder in 已下载的文件 for what comes down from `host`.
    static func downloads(for host: Host) -> URL {
        downloads.appending(path: folderName(host.title), directoryHint: .isDirectory)
    }

    /// `title` as a folder's name: what a name cannot hold, or the Files
    /// app shows otherwise, made 「-」, and no leading dot to hide it.
    static func folderName(_ title: String) -> String {
        let name = String(
            title.map { $0 == "/" || $0 == ":" ? "-" : $0 }
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .drop { $0 == "." }
        return name.isEmpty ? "Host" : String(name)
    }

    /// Copies of what the user picked to upload.
    static var uploads: URL {
        URL.temporaryDirectory.appending(path: "Uploads", directoryHint: .isDirectory)
    }

    /// Clears what an earlier run left: its queue went with it.
    static func clearLeftovers() {
        try? FileManager.default.removeItem(at: uploads)
    }

    /// Copies `urls`, which may be outside the app, each into a folder of
    /// its own under `staging`, so two of the same name both go.
    static func copy(_ urls: [URL], into staging: URL) throws -> [URL] {
        let manager = FileManager.default
        return try urls.enumerated().map { index, url in
            let folder = staging.appending(path: String(index), directoryHint: .isDirectory)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: url.lastPathComponent)
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try manager.copyItem(at: url, to: copy)
            return copy
        }
    }

    /// Keeps a copy of `file`, dropped from another app, which takes it
    /// back once the drop is over: in a folder of its own among the
    /// uploads, for `gather` to put in a batch.
    static func keep(_ file: URL) throws -> URL {
        let manager = FileManager.default
        let folder = uploads.appending(
            path: "Dropped/\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: file.lastPathComponent)
        try manager.copyItem(at: file, to: copy)
        return copy
    }

    /// Whether `copy` is a file the same as `entry` on the server: its size,
    /// and its time to the second, which a download gives it. A server that
    /// gives no time leaves it unknown, so not the same.
    static func same(_ copy: URL, as entry: DirectoryEntry) -> Bool {
        guard let modified = entry.modified,
            let attributes = try? FileManager.default.attributesOfItem(atPath: copy.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? UInt64,
            let date = attributes[.modificationDate] as? Date
        else {
            return false
        }
        return size == entry.size
            && Int64(date.timeIntervalSince1970.rounded(.down)) == Int64(modified)
    }

    /// Moves what `keep` kept into `staging`, each into a folder of its own
    /// as `copy` puts them, and drops the folders they were kept in.
    static func gather(_ kept: [URL], into staging: URL) throws -> [URL] {
        let manager = FileManager.default
        return try kept.enumerated().map { index, file in
            let folder = staging.appending(path: String(index), directoryHint: .isDirectory)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let moved = folder.appending(path: file.lastPathComponent)
            try manager.moveItem(at: file, to: moved)
            try? manager.removeItem(at: file.deletingLastPathComponent())
            return moved
        }
    }
}
