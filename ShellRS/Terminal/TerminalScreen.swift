import ShellRSCore
import SwiftUI

/// A terminal over the whole of a narrow window, with its bar.
struct TerminalScreen: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model
    @State private var showingFiles = false

    var body: some View {
        NavigationStack {
            TerminalPane(session: session)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(session.host.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("收起", systemImage: "chevron.down") {
                            model.shownSession = nil
                        }
                    }
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
        // The terminal is dark whatever the system's appearance; what is
        // shown over it is not.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingFiles) {
            FilesView(files: session.openFiles())
        }
        .loginPrompts(of: session)
        .onAppear {
            session.surface.focusForKeyboard()
        }
    }
}

/// A terminal, with a bar to reconnect once it has closed: what a narrow
/// window's screen and a wide window's tab both show. Each puts black
/// behind it as far as suits it.
struct TerminalPane: View {
    let session: TerminalSession

    var body: some View {
        TerminalSurfaceView(surface: session.surface)
            // The view is the session's own: another session needs a new
            // representable, not this one updated.
            .id(session.id)
            .safeAreaInset(edge: .bottom) {
                if session.isClosed {
                    ClosedBar(session: session)
                        .padding()
                }
            }
            .overlay {
                if session.state == .connecting, session.prompt == nil {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
    }
}

extension View {
    /// What the login of `session` asks the user, in a sheet.
    func loginPrompts(of session: TerminalSession) -> some View {
        sheet(
            isPresented: Binding(
                get: { session.prompt != nil },
                set: { if !$0 { session.answer(.cancel) } })
        ) {
            if let prompt = session.prompt {
                PromptSheet(prompt: prompt) { reply in
                    session.answer(reply)
                }
                .id(prompt.id)
            }
        }
    }
}

/// The host's name over the latency, in the bar.
struct TerminalTitle: View {
    let session: TerminalSession

    var body: some View {
        VStack(spacing: 0) {
            Text(session.host.title)
                .font(.headline)
            if let latency = session.latency, session.state == .connected {
                Text("\(String(latency)) ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The bar's 更多.
struct TerminalMenu: View {
    let session: TerminalSession

    var body: some View {
        Menu("更多", systemImage: "ellipsis.circle") {
            TerminalActions(session: session)
        }
    }
}

/// Reconnect or disconnect, and close: the bar's menu and a tab's.
struct TerminalActions: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model

    var body: some View {
        if session.isClosed {
            Button("重新连接", systemImage: "arrow.clockwise") {
                session.start()
            }
        } else {
            Button("断开连接", systemImage: "bolt.slash") {
                session.disconnect()
            }
        }
        Button("关闭", systemImage: "xmark", role: .destructive) {
            model.close(session)
        }
    }
}

/// Why the terminal closed, and what to do now.
private struct ClosedBar: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .closed(let reason?) = session.state {
                Text(reason)
                    .font(.callout)
                    .lineLimit(4)
            } else {
                Text("已断开连接")
                    .font(.callout)
            }
            HStack {
                Button("重新连接") {
                    session.start()
                }
                .buttonStyle(.borderedProminent)
                Button("关闭") {
                    model.close(session)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
