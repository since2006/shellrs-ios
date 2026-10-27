import SwiftTerm
import SwiftUI
import UIKit

/// SwiftTerm's view and what it asks of the app. The only file that sees
/// SwiftTerm: its `Terminal` and `TerminalOptions` are not the core's.
///
/// It outlives SwiftUI's views, so the screen keeps its text when the
/// terminal is hidden and shown again.
@MainActor
final class TerminalSurface: NSObject, TerminalViewDelegate {
    let view: TerminalView
    /// Bytes the user typed or pasted.
    var onInput: (Data) -> Void = { _ in }
    /// The columns, rows and pixels the terminal now has.
    var onResize: (TerminalSize) -> Void = { _ in }
    /// The title the program in the terminal set.
    var onTitle: (String) -> Void = { _ in }

    override init() {
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), font: font)
        super.init()
        view.terminalDelegate = self
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = UIColor(white: 0.9, alpha: 1)
        view.keyboardDismissMode = .interactive
    }

    /// The size the terminal has now.
    var size: TerminalSize {
        let dimensions = view.terminalDimensions
        let scale = view.window?.screen.scale ?? view.traitCollection.displayScale
        return TerminalSize(
            columns: UInt32(max(dimensions.cols, 1)),
            rows: UInt32(max(dimensions.rows, 1)),
            width: UInt32(view.bounds.width * scale),
            height: UInt32(view.bounds.height * scale))
    }

    /// Shows what the server sent.
    func feed(_ bytes: Data) {
        view.feed(byteArray: ArraySlice(bytes))
    }

    /// Writes a line of the app's own into the terminal, dimmed, as the
    /// desktop writes its notices.
    func notice(_ text: String) {
        view.feed(text: "\r\n\u{1b}[2m\(text)\u{1b}[0m\r\n")
    }

    /// The text on the screen and above it.
    var text: String {
        String(decoding: view.getBufferAsData(), as: UTF8.self)
    }

    func focus() {
        _ = view.becomeFirstResponder()
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onResize(size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        onTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    /// Web links open in the browser; nothing else a program prints opens.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// OSC 52: what a program copies goes on the clipboard. Reading it back
    /// stays denied (SwiftTerm's default).
    func clipboardCopy(source: TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = text
        }
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// The terminal's size in characters and pixels.
struct TerminalSize: Equatable {
    var columns: UInt32
    var rows: UInt32
    var width: UInt32
    var height: UInt32
}

/// The surface in SwiftUI.
struct TerminalSurfaceView: UIViewRepresentable {
    let surface: TerminalSurface

    func makeUIView(context: Context) -> TerminalView {
        surface.view
    }

    func updateUIView(_ view: TerminalView, context: Context) {}
}
