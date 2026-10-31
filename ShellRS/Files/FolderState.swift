import Observation
import ShellRSCore
import SwiftUI
import UniformTypeIdentifiers

/// Per-folder interaction state outlives the pane/screen that happens to show it.
@MainActor
@Observable
final class FolderState {
    enum Listing {
        case loading
        case loaded([DirectoryEntry])
        case failed(String)
    }

    /// A name being typed.
    enum Naming: Equatable {
        case newFolder
        case rename(String)
    }

    /// What went wrong, under what title.
    struct Trouble {
        let title: String
        let message: String
    }

    var listing = Listing.loading
    var selection = Set<String>()
    var editMode = EditMode.inactive
    var naming: Naming?
    var name = ""
    var deleting: [String] = []
    var importing = false
    var trouble: Trouble?
    var dropTargeted = false

    private var entries: [DirectoryEntry] {
        if case .loaded(let entries) = listing { return entries }
        return []
    }

    // MARK: Changing

    var namingTitle: Text {
        switch naming {
        case .rename(let original):
            Text("重命名「\(original)」")
        case .newFolder, nil:
            Text("新建文件夹")
        }
    }

    var deletingTitle: String {
        deleting.count == 1
            ? String(localized: "删除「\(deleting[0])」？")
            : String(localized: "删除 \(deleting.count) 个项目？")
    }

    func commit(_ naming: Naming, files: FilesModel, folder: String) {
        let original: String? =
            switch naming {
            case .rename(let original): original
            case .newFolder: nil
            }
        let failed =
            original == nil ? String(localized: "新建失败") : String(localized: "重命名失败")
        if name == original {
            return
        }
        if let problem = FileName.problem(name, among: entries.map(\.name)) {
            trouble = Trouble(title: failed, message: problem)
            return
        }
        let name = name
        Task {
            do {
                if let original {
                    try await files.rename(original, to: name, in: folder)
                } else {
                    try await files.createFolder(name, in: folder)
                }
            } catch {
                trouble = Trouble(title: failed, message: Describe.ssh(error))
            }
        }
    }

    func delete(_ names: [String], files: FilesModel, folder: String) {
        editMode = .inactive
        selection = []
        Task {
            do {
                try await files.delete(names, in: folder)
            } catch {
                trouble = Trouble(
                    title: String(localized: "删除失败"), message: Describe.ssh(error))
            }
        }
    }
}

struct FolderPrompts: ViewModifier {
    let files: FilesModel
    let folder: String

    func body(content: Content) -> some View {
        @Bindable var state = files.folderState(for: folder)
        content
            .alert(
                state.namingTitle,
                isPresented: Binding(
                    get: { state.naming != nil }, set: { if !$0 { state.naming = nil } }),
                presenting: state.naming
            ) { naming in
                TextField("名称", text: $state.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if naming == .newFolder {
                    Button("创建") {
                        state.commit(naming, files: files, folder: folder)
                    }
                } else {
                    Button("重命名") {
                        state.commit(naming, files: files, folder: folder)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmation(
                Text(verbatim: state.deletingTitle),
                isPresented: Binding(
                    get: { !state.deleting.isEmpty }, set: { if !$0 { state.deleting = [] } })
            ) {
                Button("删除", role: .destructive) {
                    state.delete(state.deleting, files: files, folder: folder)
                }
            } message: {
                Text("远程文件无法恢复，目录会连同其中全部内容一起删除。")
            }
            .fileImporter(
                isPresented: $state.importing, allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await files.upload(urls, to: folder)
                    }
                case .failure(let error):
                    state.trouble = FolderState.Trouble(
                        title: String(localized: "无法上传"), message: error.localizedDescription)
                }
            }
            .alert(
                state.trouble?.title ?? "",
                isPresented: Binding(
                    get: { state.trouble != nil }, set: { if !$0 { state.trouble = nil } }),
                presenting: state.trouble
            ) { _ in
                Button("好") {}
            } message: { trouble in
                Text(trouble.message)
            }
    }
}
