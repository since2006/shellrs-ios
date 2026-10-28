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
