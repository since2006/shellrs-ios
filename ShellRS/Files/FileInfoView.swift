import ShellRSCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A remote file's details, and what can be done with it: looked at or
/// downloaded, both into 已下载的文件. A tap on a file shows this rather
/// than bringing it down, which a large one would do slowly and into the
/// device's space.
struct FileInfoView: View {
    let files: FilesModel
    let file: FileShown
    let close: () -> Void
    /// The batch started here: the file brought down to look at, or into
    /// 已下载的文件.
    @State private var job: Int?
    /// Whether `file.previewing` was acted on: shown again once the
    /// preview closes, it is not looked at again.
    @State private var started = false
    /// Whether a large file's preview waits for the user to say yes.
    @State private var confirmingPreview = false

    /// From this size a preview asks first, as it brings the whole file
    /// down: the desktop's limit for previewing a picture.
    static let largeSize: UInt64 = 20 << 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                Section {
                    actions
                }
                Section {
                    details
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .transferPrompts(files, active: true)
        // An alert on a phone too: the bottom sheet's question would point
        // at the top of the details on iOS 26.
        .alert("文件较大，仍要预览吗？", isPresented: $confirmingPreview) {
            Button("取消", role: .cancel) {}
            Button("预览") {
                preview()
            }
        } message: {
            Text("预览要先下载整个文件（\(Format.size(entry.size))）。")
        }
        .onAppear {
            if file.previewing, !started {
                started = true
                askToPreview()
            }
        }
        // Closed while it still comes down: shown later, it would only be
        // in the way.
        .onDisappear {
            if let running, running.job.isPreview {
                files.abandon(running.id)
            }
        }
    }

    private var entry: DirectoryEntry {
        file.entry
    }

    /// Previews at once, unless that brings a large file down: the copy in
    /// 已下载的文件 when the same is not.
    private func askToPreview() {
        if entry.kind == .file, entry.size >= Self.largeSize, files.downloaded(file.path, as: entry) == nil {
            confirmingPreview = true
        } else {
            preview()
        }
    }

    private func preview() {
        job = files.preview(file.path, as: entry)
    }

    // MARK: The parts

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: entry.symbol)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(verbatim: entry.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var actions: some View {
        if let running {
            TransferCard(entry: running, files: files)
        } else {
            Button("预览", systemImage: "eye") {
                askToPreview()
            }
            .disabled(!entry.isFile)
            Button("下载", systemImage: "arrow.down.circle") {
                job = files.download([file.path])
            }
            .disabled(!entry.isFile)
            if let failure {
                Label {
                    Text(verbatim: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.red)
            }
        }
        Button("复制路径", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = file.path
        }
    }

    @ViewBuilder
    private var details: some View {
        if entry.kind == .file {
            // Under 1000 the size is in bytes already.
            LabeledContent(
                "大小",
                value: entry.size < 1000
                    ? Format.size(entry.size)
                    : String(localized: "\(Format.size(entry.size))（\(entry.size.formatted()) 字节）"))
        }
        if let modified = entry.modified {
            LabeledContent(
                "修改时间",
                value: Date(timeIntervalSince1970: TimeInterval(modified))
                    .formatted(date: .long, time: .standard))
        }
        if let permissions = entry.permissions {
            LabeledContent("权限") {
                Text(verbatim: "\(Format.rights(permissions))  \(String(format: "%03o", permissions & 0o7777))")
                    .monospaced()
            }
        }
        if let owner = entry.owner {
            LabeledContent("所有者", value: owner)
        }
        if let group = entry.group {
            LabeledContent("组", value: group)
        }
        LabeledContent("位置") {
            Text(verbatim: RemotePath.parent(file.path))
                .textSelection(.enabled)
        }
    }

    // MARK: What it says

    /// 「PNG 图像 · 1.2 MB」: the kind the system knows its extension as,
    /// and its size; a link's own size is not the file's.
    private var summary: String {
        var parts: [String] = []
        let suffix = (entry.name as NSString).pathExtension
        if entry.kind == .symlink {
            parts.append(String(localized: "链接"))
        } else if !suffix.isEmpty, let type = UTType(filenameExtension: suffix), !type.isDynamic,
            let kind = type.localizedDescription
        {
            parts.append(kind)
        }
        if entry.kind == .file {
            parts.append(Format.size(entry.size))
        }
        return parts.joined(separator: " · ")
    }

    /// The batch started here while it has not ended.
    private var running: TransferEntry? {
        guard let entry = startedEntry, !entry.state.isFinished else {
            return nil
        }
        return entry
    }

    /// Why the batch started here ended without the file: its first failed
    /// item's reason, or why it could not start.
    private var failure: String? {
        guard let entry = startedEntry else {
            return nil
        }
        switch entry.state {
        case .done where (entry.progress?.failed ?? 0) > 0:
            let reason = entry.progress?.details.first { $0.outcome == .failed }?.reason
            return reason.map(Describe.failure) ?? entry.status
        case .removed:
            return entry.status
        default:
            return nil
        }
    }

    private var startedEntry: TransferEntry? {
        job.flatMap { job in files.queue.entries.first { $0.id == job } }
    }
}

/// The batch started from a file's details: how far it got, and its
/// buttons.
private struct TransferCard: View {
    let entry: TransferEntry
    let files: FilesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(
                    entry.job.isPreview ? String(localized: "预览") : String(localized: "下载"),
                    systemImage: entry.job.isPreview ? "eye" : "arrow.down.circle")
                Spacer(minLength: 0)
                Text(verbatim: entry.status)
                    .font(.callout)
                    .foregroundStyle(entry.state == .stopped ? Color.red : Color.secondary)
                    .monospacedDigit()
                TransferControls(entry: entry, files: files)
            }
            if let progress = entry.progress, entry.state == .active, progress.phase == .transferring {
                ProgressView(value: progress.fraction)
                Text(verbatim: progress.amount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if entry.state == .pending, files.queue.head != nil {
                Text("等前面的传输完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
