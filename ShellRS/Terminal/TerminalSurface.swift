import GameController
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
    private var lastReportedSize: TerminalSize?
    private var restoreInput = false
    private var focusAllowed = true
    /// Bytes the user typed or pasted.
    var onInput: (Data) -> Void = { _ in }
    /// The columns, rows and pixels the terminal now has.
    var onResize: (TerminalSize) -> Void = { _ in }
    /// The title the program in the terminal set.
    var onTitle: (String) -> Void = { _ in }

    /// The text size in points. The terminal then has other columns and
    /// rows: SwiftTerm reports them through `sizeChanged`, as it reports a
    /// new window size.
    var fontSize: Double {
        didSet {
            if fontSize != oldValue {
                view.font = Self.font(fontSize)
            }
        }
    }

    init(fontSize: Double) {
        self.fontSize = fontSize
        let view = ResizingTerminalView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480), font: Self.font(fontSize))
        self.view = view
        super.init()
        view.geometryChanged = { [weak self] in self?.reportSize() }
        view.terminalDelegate = self
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = UIColor(white: 0.9, alpha: 1)
        view.keyboardDismissMode = .interactive
    }

    /// The size the terminal has now.
    var size: TerminalSize {
        let dimensions = view.terminalDimensions
        let scale = view.traitCollection.displayScale
        return TerminalSize(
            columns: UInt32(max(dimensions.cols, 1)),
            rows: UInt32(max(dimensions.rows, 1)),
            width: Self.pixels(view.bounds.width * scale),
            height: Self.pixels(view.bounds.height * scale))
    }

    private static func pixels(_ value: CGFloat) -> UInt32 {
        guard value.isFinite, value > 0 else { return 0 }
        return UInt32(min(value.rounded(.down), CGFloat(UInt32.max)))
    }

    private func reportSize() {
        guard view.window != nil else { return }
        let size = size
        guard size.isValid, size != lastReportedSize else { return }
        lastReportedSize = size
        onResize(size)
    }

    /// A surface has exactly one UIKit owner, even if SwiftUI creates the new
    /// shell before dismantling the old one. An old host cannot detach its successor.
    func attach(to host: UIView) {
        guard view.superview !== host else { return }
        restoreInput = restoreInput || view.isFirstResponder
        view.removeFromSuperview()
        host.addSubview(view)
        // A newly created SwiftUI host initially has zero bounds. Keep the
        // emulator's old grid until its successor has a real viewport.
        if !host.bounds.isEmpty { view.frame = host.bounds }
        view.autoresizingMask = []
    }

    func detach(from host: UIView) {
        guard view.superview === host else { return }
        restoreInput = restoreInput || view.isFirstResponder
        view.removeFromSuperview()
    }

    func attachedToWindow() {
        guard focusAllowed, view.window != nil else { return }
        if restoreInput {
            restoreInput = false
            focus()
        } else {
            focusForKeyboard()
        }
    }

    func setFocusAllowed(_ allowed: Bool) {
        guard focusAllowed != allowed else { return }
        focusAllowed = allowed
        if allowed {
            attachedToWindow()
        } else if view.isFirstResponder {
            restoreInput = true
            view.resignFirstResponder()
        }
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
        guard focusAllowed, view.window != nil else { return }
        _ = view.becomeFirstResponder()
    }

    /// Explicitly hiding or leaving a terminal ends its input intent. A later
    /// resize may restore active input, but must not resurrect a dismissed keyboard.
    func dismissInput() {
        restoreInput = false
        view.resignFirstResponder()
    }

    /// Takes the keys if a keyboard is attached, once the view is in the
    /// window: shown, the terminal is typed into straight away. Without a
    /// keyboard it stays as it is, rather than bring up the on-screen one.
    func focusForKeyboard() {
        guard GCKeyboard.coalesced != nil else {
            return
        }
        DispatchQueue.main.async {
            guard self.view.window != nil else { return }
            self.focus()
        }
    }

    private static func font(_ size: Double) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        reportSize()
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
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased())
        else {
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

    var isValid: Bool { columns > 0 && rows > 0 && width > 0 && height > 0 }
}

/// SwiftTerm reports character-grid changes. Pixel-only changes and a new display
/// scale must also reach the remote PTY, after UIKit has completed its layout.
private final class ResizingTerminalView: TerminalView {
    var geometryChanged: () -> Void = {}

    override func layoutSubviews() {
        super.layoutSubviews()
        geometryChanged()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }
}

final class TerminalSurfaceHost: UIView {
    let surface: TerminalSurface
    var allowsFocus: Bool

    init(surface: TerminalSurface, allowsFocus: Bool = true) {
        self.surface = surface
        self.allowsFocus = allowsFocus
        super.init(frame: .zero)
        surface.attach(to: self)
        surface.setFocusAllowed(allowsFocus)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, surface.view.superview === self {
            surface.setFocusAllowed(allowsFocus)
            surface.attachedToWindow()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if surface.view.superview === self, !bounds.isEmpty {
            surface.view.frame = bounds
        }
    }
}

/// The surface in SwiftUI.
struct TerminalSurfaceView: UIViewRepresentable {
    let surface: TerminalSurface
    @Environment(AppModel.self) private var model

    func makeUIView(context: Context) -> TerminalSurfaceHost {
        TerminalSurfaceHost(surface: surface, allowsFocus: model.terminalInputAllowed)
    }

    func updateUIView(_ view: TerminalSurfaceHost, context: Context) {
        view.allowsFocus = model.terminalInputAllowed
        if surface.view.superview === view { surface.setFocusAllowed(view.allowsFocus) }
    }

    static func dismantleUIView(_ view: TerminalSurfaceHost, coordinator: ()) {
        view.surface.detach(from: view)
    }
}
