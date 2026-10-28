import ShellRSCore
import SwiftUI

/// The transfer queue: each batch as it stands, and what to do with it.
struct TransfersView: View {
    let files: FilesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if files.queue.entries.isEmpty {
                        Text("没有传输")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(files.queue.entries) { entry in
                        TransferRow(entry: entry, files: files)
                    }
                }
                Section {
                    NavigationLink {
                        DownloadsView(revision: files.downloads)
                    } label: {
                        Label("已下载的文件", systemImage: "arrow.down.circle")
                    }
                }
            }
            .navigationTitle("传输队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除已完成") {
                        files.clearFinished()
                    }
                    .disabled(!files.queue.hasFinished)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .transferPrompts(files, active: true)
    }
}

/// A batch: what it copies where, how far it got, and what can be done
/// with it now.
private struct TransferRow: View {
    let entry: TransferEntry
    let files: FilesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: upload ? "arrow.up.circle" : "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(entry.state == .removed ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.job.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(
                        verbatim: upload
                            ? String(localized: "上传到 \(entry.job.destination)")
                            : String(localized: "下载到 \(entry.job.destination)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(verbatim: entry.status)
                    .font(.caption)
                    .foregroundStyle(entry.state == .stopped || failed ? Color.red : Color.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if let progress = entry.progress, entry.state == .active, progress.phase == .transferring {
                ProgressView(value: progress.fraction)
                Text(verbatim: Self.amount(progress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let details = entry.progress?.details, !details.isEmpty, entry.state != .active {
                DisclosureGroup("逐项结果") {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        DetailRow(detail: detail)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            actions
        }
        .contextMenu {
            actions
        }
    }

    private var upload: Bool {
        entry.job.direction == .upload
    }

    private var failed: Bool {
        entry.state == .done && (entry.progress?.failed ?? 0) > 0
    }

    @ViewBuilder
    private var actions: some View {
        switch entry.state {
        case .active:
            Button("停止", systemImage: "stop.circle") {
                files.cancel()
            }
            .tint(.orange)
        case .stopped:
            Button("移出队列", systemImage: "xmark.circle", role: .destructive) {
                files.remove(entry)
            }
            Button("丢弃续传进度", systemImage: "trash") {
                files.discard()
            }
            .tint(.orange)
            Button("继续", systemImage: "play.circle") {
                files.resume()
            }
            .tint(.green)
        case .pending, .done, .removed:
            Button("移出队列", systemImage: "xmark.circle", role: .destructive) {
                files.remove(entry)
            }
        }
    }

    /// 「1.2 MB / 3.4 MB · 2 MB/s · 剩余 12 秒」.
    static func amount(_ progress: TransferProgress) -> String {
        var parts = ["\(Format.size(progress.completedBytes)) / \(Format.size(progress.totalBytes))"]
        if progress.bytesPerSecond > 0 {
            parts.append("\(Format.size(progress.bytesPerSecond))/s")
        }
        if let remaining = progress.remainingSeconds {
            parts.append(String(localized: "剩余 \(Format.duration(remaining))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// How one item of a batch ended.
private struct DetailRow: View {
    let detail: TransferDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: detail.path.isEmpty ? String(localized: "整批") : RemotePath.name(detail.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(outcome)
                    .foregroundStyle(detail.outcome == .failed ? Color.red : Color.secondary)
            }
            if let reason = detail.reason {
                Text(verbatim: Describe.failure(reason))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outcome: String {
        switch detail.outcome {
        case .done: String(localized: "完成")
        case .skipped: String(localized: "已跳过")
        case .failed: String(localized: "失败")
        }
    }
}
