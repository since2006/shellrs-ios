import ShellRSCore
import SwiftUI
import UIKit

/// The window: a sidebar and terminal tabs when it is a wide one, the
/// iPhone's tabs otherwise. The terminals and what is shown are the
/// model's, so they stay as the window narrows or widens.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Group {
                    if model.isWide {
                        WideRoot()
                    } else {
                        CompactRoot()
                    }
                }
                .allowsHitTesting(
                    !model.filesCoverTerminal
                        && (model.isWide || !model.compactTerminalPresented)
                )
                .accessibilityHidden(
                    model.filesCoverTerminal
                        || (!model.isWide && model.compactTerminalPresented))

                // A full-window layer, in the same scene as the workspace. Unlike a
                // modal cover, its teardown cannot race a second terminal presenter.
                if !model.isWide, model.compactTerminalPresented,
                    let session = model.shownSession
                {
                    TerminalScreen(session: session)
                        .id(session.id)
                        .allowsHitTesting(!model.filesCoverTerminal)
                        .accessibilityHidden(model.filesCoverTerminal)
                        .zIndex(1)
                }
                if model.filesCoverTerminal,
                    let session = model.shownSession
                {
                    FilesPane(session: session)
                        .background(.background)
                        .zIndex(2)
                }
            }
            .onChange(
                of: AppLayout(width: geometry.size.width, regular: sizeClass == .regular),
                initial: true
            ) { _, layout in
                model.updateLayout(layout)
            }
        }
        .environment(\.wideWindow, model.isWide)
        .sheet(
            item: Binding(
                get: { model.presentedSheet },
                set: { if $0 == nil { model.dismissSheet() } })
        ) { sheet in
            AppSheetView(sheet: sheet)
                .environment(model)
        }
        .modifier(ActiveTransferPrompts())
        .modifier(HostListPrompts())
        .task { await model.purchases.start() }
        // The ads wait for StoreKit: whoever bought them away never starts the SDK.
        .onChange(of: model.purchases.adRemoval, initial: true) { _, removal in
            Task { await model.ads.purchaseChanged(removal) }
        }
        .focusedSceneValue(\.appModel, model)
        .preferredColorScheme(model.appearance.colorScheme)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                model.cameForward()
            case .background:
                model.wentToBackground()
            default:
                break
            }
        }
    }
}

/// The app's tabs, with the terminal shown over them.
private struct CompactRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            StatusTab()
                .tabItem { Label("状态", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(AppTab.status)
            HostListView()
                .tabItem { Label("主机", systemImage: "server.rack") }
                .tag(AppTab.hosts)
            SessionsView()
                .tabItem { Label("终端", systemImage: "terminal") }
                .badge(model.sessions.count)
                .tag(AppTab.terminals)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
                .badge(model.sync.attention == nil ? 0 : 1)
                .tag(AppTab.settings)
        }
        .alert(
            "同步",
            isPresented: Binding(
                get: {
                    model.sync.notice != nil && !model.sync.pageShown
                        && !model.compactTerminalPresented && model.presentedSheet == nil
                },
                set: { if !$0 { model.sync.notice = nil } }),
            presenting: model.sync.notice
        ) { _ in
            Button("处理…") {
                model.reviewSync()
            }
            Button("稍后", role: .cancel) {}
        } message: { attention in
            Text(Describe.attention(attention))
        }
    }
}

/// File questions and previews also belong to the stable window, not its file pane.
private struct ActiveTransferPrompts: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        // Do not replace the content subtree when a file model opens or closes.
        content.modifier(
            WindowTransferPrompts(
                files: model.shownSession?.files,
                active: model.showsFiles && model.presentedSheet == nil
                    && (model.isWide || model.compactTerminalPresented)))
    }
}
