import SwiftUI

/// The window's model, for its menus: hold ⌘ on an iPad's keyboard to see
/// them. A window sets it with `focusedSceneValue`.
private struct AppModelKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

/// The desktop's main shortcuts, under its names. SwiftTerm leaves ⌘ keys
/// to the system, so they work in a terminal too; ⌘C and ⌘V are the
/// system's Edit menu, which reaches the terminal's copy and paste.
struct AppCommands: Commands {
    @FocusedValue(\.appModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建主机…") {
                model?.request(.newHost)
            }
            .keyboardShortcut("n")
            .disabled(model?.canPresent != true)
            Button("新建分组…") {
                model?.request(.newGroup)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model?.canPresent != true)
        }
        CommandGroup(replacing: .appSettings) {
            Button("打开设置") {
                model?.openSettings()
            }
            .keyboardShortcut(",")
            .disabled(model?.canPresent != true)
        }
        CommandGroup(replacing: .sidebar) {
            Button("显示或隐藏侧栏") {
                model?.toggleSidebar()
            }
            .keyboardShortcut("b")
            .disabled(model?.isWide != true)
            Button("显示或隐藏右侧栏") {
                model?.toggleFiles()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(model.map { !$0.isWide || $0.shownSession == nil } != false)
            Button("聚焦搜索") {
                model?.request(.search)
            }
            .keyboardShortcut("k")
            .disabled(model?.canPresent != true)
        }
        CommandMenu("终端") {
            Button("关闭标签") {
                model?.closeShown()
            }
            .keyboardShortcut("w")
            .disabled(model?.shownSession == nil)
            Divider()
            Button("下一个标签") {
                model?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(model?.sessions.isEmpty != false)
            Button("上一个标签") {
                model?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(model?.sessions.isEmpty != false)
            if let model, !model.sessions.isEmpty {
                Divider()
                TabCommands(model: model)
            }
            Divider()
            Button("放大字号") {
                model?.biggerText()
            }
            .keyboardShortcut("=")
            .disabled(model.map { $0.fontSize >= AppModel.fontSizes.upperBound } != false)
            Button("缩小字号") {
                model?.smallerText()
            }
            .keyboardShortcut("-")
            .disabled(model.map { $0.fontSize <= AppModel.fontSizes.lowerBound } != false)
            Button("默认字号") {
                model?.defaultText()
            }
            .keyboardShortcut("0")
            .disabled(model.map { $0.fontSize == AppModel.defaultFontSize } != false)
        }
    }
}

/// The open terminals by name: ⌘1 to ⌘8, and ⌘9 to the last, as in a
/// browser.
private struct TabCommands: View {
    let model: AppModel

    var body: some View {
        let sessions = model.sessions
        ForEach(Array(sessions.prefix(8).enumerated()), id: \.element.id) { index, session in
            Button(session.host.title) {
                model.select(tab: index + 1)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
        if sessions.count > 8, let last = sessions.last {
            Button(last.host.title) {
                model.select(tab: 9)
            }
            .keyboardShortcut("9")
        }
    }
}
