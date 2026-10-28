import SwiftUI

/// A wide iPad window, as the desktop's: the hosts in a sidebar that can
/// be hidden, the terminal tabs beside it.
struct WideRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(
            columnVisibility: Binding(
                get: { model.sidebarShown ? .all : .detailOnly },
                set: { model.sidebarShown = $0 != .detailOnly })
        ) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
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
                get: { model.showsFiles },
                set: { model.showsFiles = $0 })
        ) {
            Group {
                if let session = model.shownSession {
                    FilesPane(session: session)
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 400, max: 640)
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView {
                model.showingSettings = false
            }
        }
    }
}
