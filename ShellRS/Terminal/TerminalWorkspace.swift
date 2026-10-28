import ShellRSCore
import SwiftUI

/// The detail of a wide window: the terminal tabs over the one in front,
/// or the start page while none is open.
struct TerminalWorkspace: View {
    @Environment(AppModel.self) private var model

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
                    Button("文件", systemImage: model.showsFiles ? "folder.fill" : "folder") {
                        model.toggleFiles()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    TerminalMenu(session: session)
                }
            }
        }
        // A tab brought forward takes the keys, to type in straight away.
        .onChange(of: model.shownSession?.id, initial: true) {
            model.shownSession?.surface.focusForKeyboard()
        }
    }
}

/// The files beside a terminal, on its connection: they follow the tab in
/// front, each tab's own.
struct FilesPane: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model

    var body: some View {
        // As the files say it once opened on a closed terminal: not opened
        // here, as that would open them for nothing.
        if session.files == nil, session.isClosed {
            ContentUnavailableView {
                Label("SFTP 已断开", systemImage: "bolt.horizontal")
            } description: {
                Text("终端未连接，重新连接终端后才能浏览文件")
            }
        } else {
            FilesView(files: session.openFiles()) {
                model.showsFiles = false
            }
            // Another tab's are other files: opened afresh, not these
            // updated.
            .id(session.id)
        }
    }
}
