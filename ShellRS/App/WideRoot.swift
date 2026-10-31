import SwiftUI

/// A wide window, as the desktop's: the hosts in a sidebar that can
/// be hidden, the terminal tabs beside it.
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
            TerminalWorkspace()
        }
        // The terminal beside the sidebar, never under it.
        .navigationSplitViewStyle(.balanced)
        // The files of the terminal in front, beside the whole split view:
        // inside the detail, their bar would merge into the terminal's.
        // Only with a terminal: the start page has none to show files of.
        .inspector(
            isPresented: Binding(
                get: { model.showsFiles && model.layout.fitsFilesBesideTerminal },
                set: {
                    if model.isWide, model.layout.fitsFilesBesideTerminal {
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
