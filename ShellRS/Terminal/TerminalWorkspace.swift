import ShellRSCore
import SwiftUI

/// A wide window's terminals' page, as a narrow window's tab: the
/// terminals open, a tap on one showing it in their place until 收起; the
/// hosts connected lately while none is open, the page it opens on.
struct TerminalWorkspace: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.terminalShown, let session = model.shownSession {
                TerminalPane(session: session)
                    // Down past the home indicator, but not under the
                    // sidebar, which floats over the detail's edge.
                    .background(Color.black.ignoresSafeArea(edges: .bottom))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("收起", systemImage: "chevron.down") {
                                model.hideTerminal()
                            }
                        }
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
                    // Shown, it takes the keys, to type in straight away.
                    .onChange(of: session.id, initial: true) {
                        model.shownSession?.surface.focusForKeyboard()
                    }
            } else if model.sessions.isEmpty {
                StartView()
                    .navigationTitle("终端")
            } else {
                SessionList()
            }
        }
    }
}

/// The files beside a terminal, on its connection: they follow the
/// terminal shown, each its own.
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
            // Another terminal's are other files: opened afresh, not these
            // updated.
            .id(session.id)
        }
    }
}
