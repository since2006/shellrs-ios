import ShellRSCore
import SwiftUI

/// A terminal over the whole of a narrow window, with its bar.
struct TerminalScreen: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model

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
                            model.hideTerminal()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        TerminalTitle(session: session)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("文件", systemImage: "folder") {
                            model.showsFiles = true
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
        UnobscuredArea {
            TerminalSurfaceView(surface: session.surface)
                // A new session owns a different UIKit surface.
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
