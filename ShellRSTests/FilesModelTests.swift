import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

@MainActor
struct FilesModelTests {
    /// With the terminal not connected, the files say so, and what was
    /// asked for waits in the queue for the next session.
    @Test func withoutAConnectionItSaysWhyAndKeepsTheQueue() async throws {
        let downloads = FileManager.default.temporaryDirectory
            .appending(path: "shellrs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: downloads) }
        let files = FilesModel(downloadsFolder: downloads) {
            throw SshError.NotConnected
        }
        files.download(["/etc/hosts"])
        try await waitUntil("opening fails") {
            if case .disconnected(_?) = files.state { true } else { false }
        }
        #expect(files.state == .disconnected(String(localized: "终端未连接，重新连接终端后才能浏览文件")))
        #expect(files.queue.entries.map(\.state) == [.pending])
        await #expect(throws: SshError.NotConnected) {
            try await files.list("/")
        }
    }

    /// The copy in 已下载的文件 is the same as the server's file when it is
    /// where that file is on the server, of its size and time: previewed at
    /// once, while a different one is brought down there; one of the name
    /// in another folder is another file. A preview given up leaves what is
    /// there alone.
    @Test func aCopyHereTheSameIsShownAtOnce() async throws {
        let manager = FileManager.default
        let downloads = manager.temporaryDirectory
            .appending(path: "shellrs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let srv = downloads.appending(path: "srv", directoryHint: .isDirectory)
        try manager.createDirectory(at: srv, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: downloads) }
        let copy = srv.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: copy)
        try manager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: copy.path)
        let files = FilesModel(downloadsFolder: downloads) {
            throw SshError.NotConnected
        }
        func entry(size: UInt64 = 5, modified: UInt32? = 1_700_000_000) -> DirectoryEntry {
            DirectoryEntry(
                name: "notes.txt", kind: .file, size: size, modified: modified, permissions: 0o644,
                owner: nil, group: nil, targetKind: nil)
        }

        #expect(files.downloaded("/srv/notes.txt", as: entry())?.path == copy.path)
        #expect(files.preview("/srv/notes.txt", as: entry()) == nil)
        #expect(files.preview?.path == copy.path)
        #expect(files.queue.entries.isEmpty)
        files.preview = nil

        // Elsewhere on the server, changed there, or no time to tell by: not
        // the same.
        #expect(files.downloaded("/srv/b/notes.txt", as: entry()) == nil)
        #expect(files.downloaded("/notes.txt", as: entry()) == nil)
        #expect(files.downloaded("/srv/notes.txt", as: entry(size: 6)) == nil)
        #expect(files.downloaded("/srv/notes.txt", as: entry(modified: 1_700_000_001)) == nil)
        #expect(files.downloaded("/srv/notes.txt", as: entry(modified: nil)) == nil)

        let job = try #require(files.preview("/srv/notes.txt", as: entry(size: 6)))
        #expect(files.preview == nil)
        let queued = try #require(files.queue.entries.first)
        #expect(queued.job == .download(sources: ["/srv/notes.txt"], destination: srv, preview: true))
        #expect(queued.job.destination == String(localized: "已下载的文件"))
        files.abandon(job)
        #expect(files.queue.entries.isEmpty)
        #expect(try Data(contentsOf: copy) == Data("hello".utf8))
    }

    /// What comes down goes where it is on the server, in the host's
    /// folder: two of a name in different folders do not meet.
    @Test func downloadsGoWhereTheyAreOnTheServer() throws {
        let manager = FileManager.default
        let downloads = manager.temporaryDirectory
            .appending(path: "shellrs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: downloads) }
        let files = FilesModel(downloadsFolder: downloads) {
            throw SshError.NotConnected
        }
        files.download(["/srv/a/README.md", "/srv/a/logs"])
        files.download(["/srv/b/README.md"])
        files.download(["/etc/hosts", "/srv/b/notes.txt"])
        let a = downloads.appending(path: "srv/a", directoryHint: .isDirectory)
        let b = downloads.appending(path: "srv/b", directoryHint: .isDirectory)
        let etc = downloads.appending(path: "etc", directoryHint: .isDirectory)
        #expect(
            files.queue.entries.map(\.job) == [
                .download(sources: ["/srv/a/README.md", "/srv/a/logs"], destination: a, preview: false),
                .download(sources: ["/srv/b/README.md"], destination: b, preview: false),
                .download(sources: ["/etc/hosts"], destination: etc, preview: false),
                .download(sources: ["/srv/b/notes.txt"], destination: b, preview: false),
            ])
        #expect([a, b, etc].allSatisfy { manager.fileExists(atPath: $0.path) })
        #expect(files.local("/srv/a/README.md").path == a.appending(path: "README.md").path)
        #expect(files.local("/").path == downloads.path)

        #expect(LocalFolders.folderName("web-1") == "web-1")
        #expect(LocalFolders.folderName("prod/web: 1") == "prod-web- 1")
        #expect(LocalFolders.folderName(" .hidden ") == "hidden")
        #expect(LocalFolders.folderName("..") == "Host")
    }

    /// Permissions read as `ls -l` shows them, as the desktop's column.
    @Test func rightsReadAsLsShowsThem() {
        #expect(Format.rights(0o100_755) == "rwxr-xr-x")
        #expect(Format.rights(0o600) == "rw-------")
        #expect(Format.rights(0o41_777) == "rwxrwxrwt")
        #expect(Format.rights(0o1_776) == "rwxrwxrwT")
        #expect(Format.rights(0o4_755) == "rwsr-xr-x")
        #expect(Format.rights(0o2_745) == "rwxr-Sr-x")
    }

    /// What is dropped from another app is copied as it lands, then goes up
    /// as one batch, which takes its copies with it.
    @Test func filesDroppedGoUpAsOneBatch() async throws {
        let manager = FileManager.default
        let source = manager.temporaryDirectory
            .appending(path: "shellrs-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: source.appending(path: "b"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: source) }
        let a = source.appending(path: "notes.txt")
        let b = source.appending(path: "b/notes.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let kept = [try LocalFolders.keep(a), try LocalFolders.keep(b)]
        #expect(manager.fileExists(atPath: a.path))
        #expect(kept.allSatisfy { $0.path.hasPrefix(LocalFolders.uploads.path) })

        let files = FilesModel(downloadsFolder: source) {
            throw SshError.NotConnected
        }
        files.upload(dropped: kept, to: "/srv")
        #expect(files.queue.entries.count == 1)
        let entry = try #require(files.queue.entries.first)
        guard case .upload(let sources, let destination, let staging) = entry.job else {
            Issue.record("not an upload: \(entry.job)")
            return
        }
        #expect(destination == "/srv")
        // Two of the same name both go, each in a folder of its own.
        #expect(sources.map(\.lastPathComponent) == ["notes.txt", "notes.txt"])
        #expect(try sources.map { try String(contentsOf: $0, encoding: .utf8) } == ["a", "b"])
        #expect(sources.allSatisfy { $0.path.hasPrefix(staging.path) })
        #expect(kept.allSatisfy { !manager.fileExists(atPath: $0.deletingLastPathComponent().path) })

        files.end()
        #expect(!manager.fileExists(atPath: staging.path))
    }
}
