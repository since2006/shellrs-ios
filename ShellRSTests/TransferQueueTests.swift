import Foundation
import ShellRSCore
import Testing

@testable import ShellRS

/// The queue's bookkeeping, as the desktop's tests have it.
struct TransferQueueTests {
    private func upload(_ name: String) -> TransferJob {
        .upload(
            sources: [URL(filePath: "/tmp/\(name)")], destination: "/srv",
            staging: URL(filePath: "/tmp/staging"))
    }

    private func report(_ queue: inout TransferQueue, _ phase: TransferPhase, failed: UInt64 = 0) {
        queue.onProgress(progress(phase, failed: failed))
    }

    private func states(_ queue: TransferQueue) -> [TransferEntry.State] {
        queue.entries.map(\.state)
    }

    @Test func batchesRunOneAfterAnother() {
        var queue = TransferQueue()
        let first = queue.push(upload("a"))
        let second = queue.push(upload("b"))
        #expect(queue.startNext()?.id == first)
        // The first holds the engine.
        #expect(queue.startNext() == nil)
        report(&queue, .transferring)
        report(&queue, .completed)
        #expect(states(queue) == [.done, .pending])
        #expect(queue.startNext()?.id == second)
        #expect(queue.unfinishedCount == 1)
    }

    @Test func aStoppedBatchHoldsTheQueueUntilResumedOrTakenOff() {
        var queue = TransferQueue()
        let first = queue.push(upload("a"))
        let second = queue.push(upload("b"))
        queue.startNext()
        report(&queue, .stopped)
        #expect(queue.startNext() == nil)
        #expect(queue.head?.id == first)

        // Taken off, it stays listed, and the next goes.
        #expect(queue.remove(first)?.state == .removed)
        #expect(queue.entries.first?.status == String(localized: "已移出"))
        #expect(queue.startNext()?.id == second)
    }

    @Test func waitingAndEndedBatchesCanBeRemovedButARunningOneCannot() {
        var queue = TransferQueue()
        let running = queue.push(upload("a"))
        let waiting = queue.push(upload("b"))
        queue.startNext()
        report(&queue, .transferring)
        #expect(queue.remove(running) == nil)
        #expect(queue.remove(waiting) != nil)
        #expect(queue.entries.map(\.id) == [running])

        report(&queue, .completed)
        #expect(queue.hasFinished)
        #expect(queue.clearFinished().map(\.id) == [running])
        #expect(queue.entries.isEmpty)
    }

    @Test func eachStateReadsInWords() {
        var queue = TransferQueue()
        queue.push(upload("a"))
        #expect(queue.entries[0].status == String(localized: "等待中"))
        queue.startNext()
        #expect(queue.entries[0].status == String(localized: "正在扫描"))
        report(&queue, .waiting)
        #expect(queue.entries[0].status == String(localized: "等待回答"))
        var going = progress(.transferring)
        going.fraction = 0.294
        queue.onProgress(going)
        #expect(queue.entries[0].status == "29%")
        report(&queue, .completed, failed: 2)
        #expect(queue.entries[0].status == String(localized: "部分失败（\(2) 项）"))

        queue.push(upload("b"))
        queue.startNext()
        report(&queue, .stopped)
        queue.abandonHead(.discarded)
        #expect(queue.entries[1].status == String(localized: "已丢弃续传进度"))
    }

    /// A session that went away under a batch stops it; the next session
    /// has to be handed it again.
    @Test func aBatchTheEngineLostStopsAndStartsOver() {
        var queue = TransferQueue()
        queue.push(upload("a"))
        queue.startNext()
        queue.stopHead()
        #expect(states(queue) == [.stopped])
        queue.restartHead()
        #expect(states(queue) == [.active])
        #expect(queue.entries[0].status == String(localized: "正在扫描"))
    }

    @Test func remotePaths() {
        #expect(RemotePath.join("/", "etc") == "/etc")
        #expect(RemotePath.join("/home/me", "a b") == "/home/me/a b")
        #expect(RemotePath.name("/home/me/") == "me")
        #expect(RemotePath.name("/") == "/")
        #expect(RemotePath.ancestors(of: "/home/me") == ["/home", "/home/me"])
        #expect(RemotePath.ancestors(of: "/") == [])
    }

    @Test func aTypedNameIsCheckedAsTheDesktopDoes() {
        #expect(FileName.problem("", among: []) == String(localized: "名称不能为空"))
        #expect(FileName.problem("..", among: []) == String(localized: "名称不能是「.」或「..」"))
        #expect(FileName.problem("a/b", among: []) == String(localized: "名称不能包含「/」"))
        #expect(FileName.problem("a", among: ["a"]) == String(localized: "已有名为「\("a")」的项目"))
        #expect(FileName.problem("b", among: ["a"]) == nil)
    }
}

/// A batch's progress at `phase`, nothing else known.
func progress(_ phase: TransferPhase, failed: UInt64 = 0) -> TransferProgress {
    TransferProgress(
        direction: .upload, phase: phase, current: "", completedBytes: 0, totalBytes: 0,
        total: 1, succeeded: 0, skipped: 0, failed: failed, deleted: 0, bytesPerSecond: 0,
        fraction: 0, remainingSeconds: nil, elapsedSeconds: 0, note: nil, details: [])
}

/// SFTP failures read as the desktop reads them: a link that says what
/// lies under it in its own sentence ends the chain.
struct DescribeSftpTests {
    @Test func aLayerSaysItsCauseInItsOwnSentence() {
        let failed = Failure(
            links: [.upload(error: .failed), .journal(error: .unreadable), .other(detail: "denied")],
            network: false)
        let text = Describe.failure(failed)
        #expect(text.hasSuffix("denied"), "\(text)")
        #expect(text.components(separatedBy: "denied").count == 2, "\(text)")
        #expect(text.contains(Describe.journal(.unreadable)), "\(text)")
        // A question shows the first link, which says it all.
        #expect(Describe.firstLink(failed) == text)

        // A notice shows only the first link; a detail all of it.
        let unsaved = Failure(
            links: [.journal(error: .unsaved), .other(detail: "disk full")], network: false)
        #expect(Describe.firstLink(unsaved) == Describe.journal(.unsaved))
        #expect(Describe.failure(unsaved) == "\(Describe.journal(.unsaved)): disk full")
    }

    @Test func theServersWordsShowOnlyWhenTheyAddSomething() {
        let generic = Describe.sftpStatus(.failure, message: "Failure")
        #expect(generic == String(localized: "服务器报告操作失败"))
        #expect(Describe.sftpStatus(.failure, message: "disk quota exceeded") == "disk quota exceeded")
        #expect(Describe.sftpStatus(.permissionDenied, message: "") == String(localized: "没有权限"))
    }
}
