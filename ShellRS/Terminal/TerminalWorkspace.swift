import ShellRSCore
import SwiftUI

/// The detail of a wide window: the terminal tabs over the one in front,
/// or the start page while none is open.
struct TerminalWorkspace: View {
    @Environment(AppModel.self) private var model
    @State private var showingFiles = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.sessions.isEmpty {
                TerminalTabs()
                Divider()
            }
            if let session = model.shownSession {
                TerminalPane(session: session)
                    // Down past the home indicator, but not under the
                    // sidebar, which floats over the detail's edge.
                    .background(Color.black.ignoresSafeArea(edges: .bottom))
                    .loginPrompts(of: session)
            } else {
                StartView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session = model.shownSession {
                ToolbarItem(placement: .principal) {
                    TerminalTitle(session: session)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("文件", systemImage: "folder") {
                        showingFiles = true
                    }
                    .disabled(session.files == nil && session.isClosed)
                }
                ToolbarItem(placement: .primaryAction) {
                    TerminalMenu(session: session)
                }
            }
        }
        .sheet(isPresented: $showingFiles) {
            if let session = model.shownSession {
                FilesView(files: session.openFiles())
            }
        }
    }
}
