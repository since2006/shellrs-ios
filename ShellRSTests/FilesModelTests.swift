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
}
