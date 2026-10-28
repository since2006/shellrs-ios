import QuickLook
import ShellRSCore
import SwiftUI

/// The terminal host's files over SFTP: its folders from `/` down, the
/// user's home open first, and the running transfer along the bottom.
struct FilesView: View {
    let files: FilesModel
    @Environment(\.dismiss) private var dismiss
    @State private var shown: Shown?

    /// What the sheet shows over itself.
    enum Shown: String, Identifiable {
        case transfers
        case downloads

        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var files = files
        let actions = FilesActions(
            close: { dismiss() },
            showTransfers: { shown = .transfers },
            showDownloads: { shown = .downloads })
        NavigationStack(path: $files.path) {
            FolderView(folder: "/", files: files, actions: actions)
                .navigationDestination(for: String.self) { folder in
                    FolderView(folder: folder, files: files, actions: actions)
                }
        }
        .safeAreaInset(edge: .bottom) {
            TransferBar(files: files) {
                shown = .transfers
            }
        }
        .sheet(item: $shown) { shown in
            switch shown {
            case .transfers:
                TransfersView(files: files)
            case .downloads:
                NavigationStack {
                    DownloadsView(revision: files.downloads)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") {
                                    self.shown = nil
                                }
                            }
                        }
                }
            }
        }
        // While a sheet is over it, the sheet asks and shows instead.
        .transferPrompts(files, active: shown == nil)
        .onAppear {
            files.open()
        }
    }
}

extension View {
    /// What a transfer asks of the user, its notices, and the file it
    /// brought down to look at, shown over this view while `active`.
    func transferPrompts(_ files: FilesModel, active: Bool) -> some View {
        modifier(TransferPrompts(files: files, active: active))
    }
}

private struct TransferPrompts: ViewModifier {
    let files: FilesModel
    let active: Bool

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title, isPresented: Binding(get: { active && files.question != nil }, set: { _ in }),
                titleVisibility: .visible, presenting: files.question
            ) { question in
                buttons(question)
            } message: { question in
                Text(verbatim: "\(question.path)\n\n\(Describe.firstLink(question.message))")
            }
            .alert(
                "传输出错", isPresented: Binding(
                    get: { active && files.notice != nil }, set: { if !$0 { files.notice = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(files.notice ?? "")
            }
            .quickLookPreview(
                Binding(get: { active ? files.preview : nil }, set: { files.preview = $0 }))
    }

    private var upload: Bool {
        files.queue.head?.job.direction != .download
    }

    /// Whether more of the batch may ask the same, to answer for them too.
    private var several: Bool {
        (files.queue.head?.progress?.total ?? 0) > 1
    }

    private var title: String {
        switch files.question?.kind {
        case .conflict, nil:
            String(localized: "同名文件已存在")
        case .resume:
            upload ? String(localized: "发现未完成的上传") : String(localized: "发现未完成的下载")
        case .invalidResume:
            String(localized: "无法继续此文件")
        case .error:
            upload ? String(localized: "无法上传此项目") : String(localized: "无法下载此项目")
        }
    }

    @ViewBuilder
    private func buttons(_ question: TransferQuestion) -> some View {
        switch question.kind {
        case .conflict:
            Button("覆盖") { files.answer(.overwrite) }
            if several {
                Button("全部覆盖") { files.answer(.overwrite, toAll: true) }
            }
            Button("跳过") { files.answer(.skip) }
            if several {
                Button("全部跳过") { files.answer(.skip, toAll: true) }
            }
        case .resume:
            Button(upload ? String(localized: "继续上传") : String(localized: "继续下载")) { files.answer(.resume) }
            if several {
                Button("全部继续") { files.answer(.resume, toAll: true) }
            }
            Button(upload ? String(localized: "重新上传") : String(localized: "重新下载")) { files.answer(.restart) }
            Button("跳过") { files.answer(.skip) }
        case .invalidResume:
            Button(upload ? String(localized: "重新上传") : String(localized: "重新下载")) { files.answer(.restart) }
            Button("跳过") { files.answer(.skip) }
        case .error:
            Button("重试") { files.answer(.retry) }
            Button("跳过") { files.answer(.skip) }
        }
        Button(upload ? String(localized: "取消上传") : String(localized: "取消下载"), role: .cancel) {
            files.answer(.cancel)
        }
    }
}

/// The batch at the head of the queue, along the bottom of the files: tap
/// it for the whole queue.
private struct TransferBar: View {
    let files: FilesModel
    let open: () -> Void

    var body: some View {
        if let entry = files.queue.head ?? files.queue.entries.first(where: { $0.state == .pending }) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: entry.job.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: entry.job.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: entry.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if waiting > 0 {
                            Text("还有 \(waiting) 批")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    if entry.state == .active, entry.progress?.phase == .transferring {
                        ProgressView(value: entry.progress?.fraction ?? 0)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// Batches waiting behind the head.
    private var waiting: Int {
        files.queue.entries.filter { $0.state == .pending }.count
            - (files.queue.head == nil ? 1 : 0)
    }
}
