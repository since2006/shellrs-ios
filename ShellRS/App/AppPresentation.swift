import Observation
import ShellRSCore
import SwiftUI

/// These sheets are presented above the layout branches. Their identity and local
/// form state survive a change of shell, including passwords that stay in memory.
enum AppSheet: Identifiable {
    case host(HostEditor.Subject)
    case group(GroupEditor.Subject)
    case credential(CredentialEditor.Subject)
    case settings
    case purchase
    case sync(SyncView.Sheet)
    case login(TerminalSession, Prompt)
    case transfers(FilesModel)
    case downloads(FilesModel)
    case file(FilesModel, FileShown)

    var id: String {
        switch self {
        case .host(let subject): "host:\(subject.id)"
        case .group(let subject): "group:\(subject.id)"
        case .credential(let subject): "credential:\(subject.id)"
        case .purchase: "purchase"
        case .settings: "settings"
        case .sync(let sheet): "sync:\(sheet.id)"
        case .login(let session, let prompt): "login:\(session.id):\(prompt.id)"
        case .transfers(let files): "transfers:\(ObjectIdentifier(files))"
        case .downloads(let files): "downloads:\(ObjectIdentifier(files))"
        case .file(let files, let file): "file:\(ObjectIdentifier(files)):\(file.path)"
        }
    }
}

struct AppSheetView: View {
    let sheet: AppSheet
    @Environment(AppModel.self) private var model

    var body: some View {
        switch sheet {
        case .host(let subject): HostEditor(subject: subject)
        case .group(let subject): GroupEditor(subject: subject)
        case .credential(let subject): CredentialEditor(subject: subject)
        case .purchase: PurchaseView()
        case .settings:
            SettingsView { model.showingSettings = false }
        case .sync(let sheet):
            SyncSheetView(sync: model.sync, sheet: sheet) { model.sheet = nil }
        case .login(let session, let prompt):
            PromptSheet(prompt: prompt) { session.answer($0) }
                .id(prompt.id)
        case .transfers(let files): TransfersView(files: files)
        case .downloads(let files):
            NavigationStack {
                DownloadsView(folder: files.downloadsFolder, revision: files.downloads)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { model.sheet = nil }
                        }
                    }
            }
        case .file(let files, let file):
            FileInfoView(files: files, file: file) { model.sheet = nil }
        }
    }
}

@Observable
final class HostListState {
    var query = ""
    var searchShown = false
    var foldedInSearch: Set<UInt64> = []
    var editMode = EditMode.inactive
    var deleting: HostDeletion?
    var failure: String?
}

@Observable
final class CredentialListState {
    var query = ""
    var deleting: Credential?
    var failure: String?
}
