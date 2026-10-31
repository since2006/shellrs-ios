import ShellRSCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the files sheet's folders do beyond themselves.
struct FilesActions {
    let close: () -> Void
    let showTransfers: () -> Void
    let showDownloads: () -> Void
    let showFile: (FileShown) -> Void
}

/// A remote file to show the details of, as its folder listed it; with
/// `previewing`, brought down to look at straight away.
struct FileShown {
    let path: String
    let entry: DirectoryEntry
    var previewing = false
}

/// A remote folder: tap a folder to go in, a file for its details and to
/// look at it; swipe or long-press for the rest, or select several to
/// download or delete.
struct FolderView: View {
    let folder: String
    let files: FilesModel
    let actions: FilesActions

    private var state: FolderState { files.folderState(for: folder) }

    @AppStorage("files.showHidden") private var showHidden = false
    var body: some View {
        @Bindable var state = files.folderState(for: folder)
        // Selecting only while 选择 is on: an iPad's list selects with a
        // binding at all, and a tap would then select a folder rather than
        // go in.
        List(selection: state.editMode.isEditing ? $state.selection : nil) {
            // A folder not reachable now shows why, not what it had.
            ForEach(connected || files.state == .reconnecting ? shown : [], id: \.name) { entry in
                row(entry)
            }
        }
        .overlay {
            overlay
        }
        // Files dragged in from another app go up into this folder.
        .dropDestination(for: DroppedFile.self) { dropped, _ in
            guard connected, !dropped.isEmpty else {
                return false
            }
            files.upload(dropped: dropped.map(\.url), to: folder)
            return true
        } isTargeted: { targeted in
            state.dropTargeted = targeted && connected
        }
        .overlay {
            if state.dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(
                        Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .refreshable {
            await load()
        }
        .task(id: Reading(revision: files.revision(of: folder), connected: connected)) {
            await load()
        }
        .navigationTitle(folder == "/" ? "/" : RemotePath.name(folder))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            titleMenu
        }
        .toolbar {
            toolbar
        }
        .environment(\.editMode, $state.editMode)
    }

    // MARK: The list

    private var connected: Bool {
        files.state == .connected
    }

    private var entries: [DirectoryEntry] {
        guard case .loaded(let entries) = state.listing else {
            return []
        }
        return entries.filter { $0.name != "." && $0.name != ".." }
    }

    /// Folders first, then files, by name as Finder sorts them.
    private var shown: [DirectoryEntry] {
        entries
            .filter { showHidden || !$0.name.hasPrefix(".") }
            .sorted { a, b in
                if a.isFolder != b.isFolder {
                    return a.isFolder
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    private func row(_ entry: DirectoryEntry) -> some View {
        let path = RemotePath.join(folder, entry.name)
        return Group {
            if entry.isFolder {
                NavigationLink(value: path) {
                    EntryRow(entry: entry)
                }
            } else {
                // Not brought down on a tap: a large one would come down by
                // mistake.
                Button {
                    actions.showFile(FileShown(path: path, entry: entry))
                } label: {
                    EntryRow(entry: entry)
                }
                .tint(.primary)
            }
        }
        .swipeActions {
            Button("删除", role: .destructive) {
                state.deleting = [entry.name]
            }
            Button("下载") {
                files.download([path])
            }
            .tint(.blue)
        }
        .contextMenu {
            if entry.isFile {
                Button("预览", systemImage: "eye") {
                    actions.showFile(FileShown(path: path, entry: entry, previewing: true))
                }
            }
            Button("下载", systemImage: "arrow.down.circle") {
                files.download([path])
            }
            Button("重命名…", systemImage: "pencil") {
                state.name = entry.name
                state.naming = .rename(entry.name)
            }
            Button("复制路径", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = path
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                state.deleting = [entry.name]
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch files.state {
        case .connecting:
            ProgressView("正在连接 SFTP…")
        case .disconnected(let reason):
            ContentUnavailableView {
                Label("SFTP 已断开", systemImage: "bolt.horizontal")
            } description: {
                if let reason {
                    Text(reason)
                }
            } actions: {
                Button("重新连接") {
                    files.open()
                }
                .buttonStyle(.borderedProminent)
            }
        case .connected, .reconnecting:
            switch state.listing {
            case .loading:
                ProgressView("正在读取目录…")
            case .failed(let reason):
                ContentUnavailableView {
                    Label("无法读取目录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            case .loaded where entries.isEmpty:
                ContentUnavailableView("空目录", systemImage: "folder")
            case .loaded where shown.isEmpty:
                ContentUnavailableView("只有隐藏文件", systemImage: "eye.slash")
            case .loaded:
                EmptyView()
            }
        }
    }

    /// When the folder is read again.
    private struct Reading: Equatable {
        let revision: Int
        let connected: Bool
    }

    private func load() async {
        guard connected else {
            return
        }
        do {
            let entries = try await files.list(folder)
            guard !Task.isCancelled else { return }
            state.listing = .loaded(entries)
        } catch {
            guard !Task.isCancelled else { return }
            state.listing = .failed(Describe.ssh(error))
        }
        state.selection.formIntersection(self.entries.map(\.name))
    }

    // MARK: The bars

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if state.editMode.isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    endSelecting()
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("下载", systemImage: "arrow.down.circle") {
                    files.download(state.selection.map { RemotePath.join(folder, $0) })
                    endSelecting()
                }
                .disabled(state.selection.isEmpty)
                Spacer()
                Text(
                    state.selection.isEmpty
                        ? "" : String(localized: "已选择 \(state.selection.count) 项")
                )
                .font(.footnote)
                Spacer()
                Button("删除", systemImage: "trash", role: .destructive) {
                    state.deleting = Array(state.selection)
                }
                .disabled(state.selection.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("选择", systemImage: "checkmark.circle") {
                        state.editMode = .active
                    }
                    .disabled(shown.isEmpty)
                    Button("新建文件夹…", systemImage: "folder.badge.plus") {
                        state.name = String(localized: "新建文件夹")
                        state.naming = .newFolder
                    }
                    Button("上传文件…", systemImage: "arrow.up.doc") {
                        state.importing = true
                    }
                    Divider()
                    Toggle("显示隐藏文件", systemImage: "eye", isOn: $showHidden)
                    Divider()
                    Button("传输队列", systemImage: "arrow.up.arrow.down") {
                        actions.showTransfers()
                    }
                    Button("已下载的文件", systemImage: "arrow.down.circle") {
                        actions.showDownloads()
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .disabled(!connected)
                Button("完成") {
                    actions.close()
                }
            }
        }
    }

    /// The title's menu: up the path, home, or the path copied.
    @ViewBuilder
    private var titleMenu: some View {
        Button("复制路径", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = folder
        }
        Button("主目录", systemImage: "house") {
            files.path = RemotePath.ancestors(of: files.home)
        }
        let above = ["/"] + RemotePath.ancestors(of: folder).dropLast()
        if folder != "/" {
            Section {
                ForEach(above.reversed(), id: \.self) { parent in
                    Button(parent == "/" ? "/" : RemotePath.name(parent), systemImage: "folder") {
                        files.path = RemotePath.ancestors(of: parent)
                    }
                }
            }
        }
    }

    private func endSelecting() {
        state.editMode = .inactive
        state.selection = []
    }

}

/// A file or folder dragged in from another app, kept as it lands: the
/// app it came from takes it back once the drop is over.
struct DroppedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            DroppedFile(url: try LocalFolders.keep(received.file))
        }
    }
}

/// A file or folder in the list.
private struct EntryRow: View {
    let entry: DirectoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.title2)
                .foregroundStyle(
                    entry.isFolder ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
                )
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts: [String] = []
        if entry.kind == .symlink {
            parts.append(String(localized: "链接"))
        }
        if entry.isFile {
            parts.append(Format.size(entry.size))
        }
        if let modified = entry.modified {
            parts.append(Format.date(Date(timeIntervalSince1970: TimeInterval(modified))))
        }
        return parts.joined(separator: " · ")
    }
}

extension DirectoryEntry {
    /// A folder, or a link to one: going in lists what it points at.
    var isFolder: Bool {
        kind == .directory || (kind == .symlink && targetKind == .directory)
    }

    /// A file, or a link to one: what can be looked at.
    var isFile: Bool {
        kind == .file || (kind == .symlink && targetKind == .file)
    }

    var symbol: String {
        if isFolder {
            return kind == .symlink ? "folder" : "folder.fill"
        }
        guard isFile else {
            return kind == .symlink ? "link" : "doc.badge.ellipsis"
        }
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else {
            return "doc"
        }
        if type.conforms(to: .image) {
            return "photo"
        }
        if type.conforms(to: .audiovisualContent) {
            return type.conforms(to: .audio) ? "music.note" : "film"
        }
        if type.conforms(to: .archive) {
            return "doc.zipper"
        }
        if type.conforms(to: .pdf) {
            return "doc.richtext"
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            return "doc.text"
        }
        return "doc"
    }
}

/// What is wrong with a name typed for a remote file, as the desktop says
/// it.
enum FileName {
    static func problem(_ name: String, among existing: [String]) -> String? {
        if name.isEmpty {
            return String(localized: "名称不能为空")
        }
        if name == "." || name == ".." {
            return String(localized: "名称不能是「.」或「..」")
        }
        if name.contains("/") {
            return String(localized: "名称不能包含「/」")
        }
        if existing.contains(name) {
            return String(localized: "已有名为「\(name)」的项目")
        }
        return nil
    }
}
