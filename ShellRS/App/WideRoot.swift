import SwiftUI

/// A wide window, as an admin console: what the app has in a sidebar that
/// can be hidden, the page chosen beside it, each the narrow window's tab
/// of the same name. Its terminals' page is the list of them, or the one
/// chosen until 收起, or the hosts connected lately while none is open.
struct WideRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(
                get: { model.sidebarVisible ? .all : .detailOnly },
                set: { model.setSidebarVisible($0 != .detailOnly) })
        ) {
            Sidebar()
                .navigationSplitViewColumnWidth(
                    min: AppLayout.sidebarMinimum, ideal: AppLayout.sidebarMinimum,
                    max: AppLayout.sidebarMinimum)
        } detail: {
            switch model.tab {
            case .status:
                StatusTab()
            case .hosts:
                HostListView()
            case .terminals:
                TerminalWorkspace()
            case .credentials:
                NavigationStack {
                    CredentialList()
                }
            case .settings:
                SettingsView()
            }
        }
        // The page beside the sidebar, never under it.
        .navigationSplitViewStyle(.balanced)
        // The files of the terminal shown, beside the whole split view:
        // inside the detail, their bar would merge into the terminal's.
        // Only with a terminal shown: the start page has none to show files of.
        .inspector(
            isPresented: Binding(
                get: {
                    model.showsFiles && model.terminalShown
                        && model.layout.fitsFilesBesideTerminal
                },
                set: {
                    if model.isWide, model.terminalShown, model.layout.fitsFilesBesideTerminal {
                        model.showsFiles = $0
                    }
                })
        ) {
            Group {
                if let session = model.shownSession {
                    FilesPane(session: session)
                }
            }
            .inspectorColumnWidth(
                min: AppLayout.filesMinimum, ideal: AppLayout.filesMinimum,
                max: AppLayout.filesMinimum)
        }
    }
}
