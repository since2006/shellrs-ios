import ShellRSCore
import SwiftUI

/// A terminal over the whole screen, with what the login asks over it and
/// a bar to reconnect once it has closed.
struct TerminalScreen: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model
    @State private var showingFiles = false

    var body: some View {
        NavigationStack {
            TerminalSurfaceView(surface: session.surface)
                .safeAreaInset(edge: .bottom) {
                    if session.isClosed {
                        ClosedBar(session: session)
                            .padding()
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .overlay {
                    if session.state == .connecting, session.prompt == nil {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
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
                    ToolbarItem(placement: .primaryAction) {
                        Button("文件", systemImage: "folder") {
                            showingFiles = true
                        }
                        .disabled(session.files == nil && session.isClosed)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu("更多", systemImage: "ellipsis.circle") {
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
                }
        }
        // The terminal is dark whatever the system's appearance.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingFiles) {
            FilesView(files: session.openFiles())
        }
        .sheet(
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

/// Why the terminal closed, and what to do now.
private struct ClosedBar: View {
    let session: TerminalSession
    @Environment(AppModel.self) private var model
    @State private var showingFiles = false

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
