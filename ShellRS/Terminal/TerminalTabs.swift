import ShellRSCore
import SwiftUI

/// The tabs of a wide window, a terminal each: its host's mark colored
/// while it is online and gray otherwise, as the desktop's tabs show it.
struct TerminalTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(model.sessions.enumerated()), id: \.element.id) {
                        index, session in
                        TerminalTab(
                            session: session, isFront: session === model.shownSession,
                            isFirst: index == 0, isLast: index == model.sessions.count - 1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.shownSession?.id) { _, id in
                if let id {
                    withAnimation {
                        scroller.scrollTo(id)
                    }
                }
            }
        }
        .background(.bar)
    }
}

/// A tab: tap to bring it forward, hold or right-click for the rest.
private struct TerminalTab: View {
    let session: TerminalSession
    let isFront: Bool
    let isFirst: Bool
    let isLast: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.show(session)
            } label: {
                HStack(spacing: 8) {
                    HostMark(host: session.host, dimmed: session.state != .connected, size: 20)
                    Text(session.host.title)
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)
                    if session.prompt != nil {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text("等待输入"))
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isFront ? .isSelected : [])
            Button("关闭", systemImage: "xmark") {
                model.close(session)
            }
            .labelStyle(.iconOnly)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .padding(.trailing, 2)
        }
        .background(
            isFront ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .hoverEffect()
        .contextMenu {
            TerminalActions(session: session)
            Divider()
            Button("关闭左侧") {
                model.close(.left, of: session)
            }
            .disabled(isFirst)
            Button("关闭右侧") {
                model.close(.right, of: session)
            }
            .disabled(isLast)
            Button("关闭其他") {
                model.close(.others, of: session)
            }
            .disabled(isFirst && isLast)
            Button("关闭全部") {
                model.close(.all, of: session)
            }
        }
    }
}
