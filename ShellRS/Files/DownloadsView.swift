import QuickLook
import SwiftUI

/// What the user downloaded from a host, on this device: its folder in
/// 已下载的文件, laid out as on the server. Tap a file to look at it, share
/// it or delete it. The Files app shows the same folders.
struct DownloadsView: View {
    let folder: URL
    var title: String?
    /// Read again when it changes: a download finished.
    var revision = 0

    @State private var items: [LocalItem] = []
    @State private var preview: URL?
    @State private var deleting: LocalItem?
    @State private var failure: String?

    var body: some View {
        List {
            ForEach(items) { item in
                Group {
                    if item.isFolder {
                        NavigationLink {
                            DownloadsView(folder: item.url, title: item.name, revision: revision)
                        } label: {
                            LocalRow(item: item)
                        }
                    } else {
                        Button {
                            preview = item.url
                        } label: {
                            LocalRow(item: item)
                        }
                        .tint(.primary)
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        deleting = item
                    }
                }
                .contextMenu {
                    ShareLink(item: item.url)
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) {
                        deleting = item
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("还没有下载的文件", systemImage: "arrow.down.circle")
                } description: {
                    Text("「文件」App 的 ShellRS 文件夹里也能看到下载的文件。")
                }
            }
        }
        .navigationTitle(title ?? String(localized: "已下载的文件"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: revision) {
            load()
        }
        .refreshable {
            load()
        }
        .quickLookPreview($preview, in: items.filter { !$0.isFolder }.map(\.url))
        .confirmation(
            Text(verbatim: deleting.map { String(localized: "删除“\($0.name)”？") } ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { item in
            Button("删除", role: .destructive) {
                delete(item)
            }
        } message: { item in
            if item.isFolder {
                Text("文件夹会连同其中全部内容一起删除，无法恢复。")
            } else {
                Text("删除后无法恢复。")
            }
        }
        .alert(
            "删除失败", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func load() {
        items = LocalItem.list(folder)
    }

    private func delete(_ item: LocalItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            failure = error.localizedDescription
        }
        load()
    }
}

/// A file or folder on this device.
struct LocalItem: Identifiable {
    let url: URL
    let isFolder: Bool
    let size: Int?
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// What `folder` holds, folders first, without the hidden ones or the
    /// partial files of downloads under way.
    static func list(_ folder: URL) -> [LocalItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return
            urls
            .filter { $0.pathExtension != "filepart" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return LocalItem(
                    url: url, isFolder: values?.isDirectory ?? false, size: values?.fileSize,
                    modified: values?.contentModificationDate)
            }
            .sorted { a, b in
                if a.isFolder != b.isFolder {
                    return a.isFolder
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

private struct LocalRow: View {
    let item: LocalItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc")
                .font(.title2)
                .foregroundStyle(item.isFolder ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts: [String] = []
        if !item.isFolder, let size = item.size {
            parts.append(Format.size(UInt64(max(size, 0))))
        }
        if let modified = item.modified {
            parts.append(Format.date(modified))
        }
        return parts.joined(separator: " · ")
    }
}
