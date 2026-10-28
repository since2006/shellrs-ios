import SwiftUI

/// A wide iPad window, as the desktop's: the hosts in a sidebar that can
/// be hidden, the terminal tabs beside it.
struct WideRoot: View {
    @Environment(AppModel.self) private var model
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            TerminalWorkspace()
        }
        // The terminal beside the sidebar, never under it.
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView {
                model.showingSettings = false
            }
        }
    }
}
