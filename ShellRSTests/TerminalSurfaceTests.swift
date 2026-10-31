import Testing
import UIKit

@testable import ShellRS

@MainActor
@Suite(.serialized)
struct TerminalSurfaceTests {
    @Test func anOldHostCannotDetachTheSurfaceFromItsSuccessor() {
        let surface = TerminalSurface(fontSize: 13)
        surface.feed(Data("still-here".utf8))
        let old = TerminalSurfaceHost(surface: surface)
        let next = TerminalSurfaceHost(surface: surface)
        #expect(old.subviews.isEmpty)
        #expect(surface.view.superview === next)
        surface.detach(from: old)
        #expect(surface.view.superview === next)
        #expect(surface.text.contains("still-here"))
        surface.detach(from: next)
        #expect(surface.view.superview == nil)
    }

    @Test func resizingReportsPixelsEvenWhenTheCharacterGridDoesNotChange() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        let surface = TerminalSurface(fontSize: 13)
        let host = TerminalSurfaceHost(surface: surface)
        controller.view.addSubview(host)
        var reported: [TerminalSize] = []
        surface.onResize = { reported.append($0) }

        func layout(width: CGFloat, height: CGFloat) {
            host.frame = CGRect(x: 0, y: 0, width: width, height: height)
            host.layoutIfNeeded()
            surface.view.setNeedsLayout()
            surface.view.layoutIfNeeded()
        }

        layout(width: 500, height: 300)
        let first = try #require(reported.last)
        let count = reported.count
        layout(width: 500, height: 300)
        #expect(reported.count == count)
        layout(width: 501, height: 300)
        let last = try #require(reported.last)
        #expect(last.columns == first.columns)
        #expect(last.rows == first.rows)
        #expect(last.width != first.width)
        #expect(reported.count == count + 1)
        layout(width: 0, height: 0)
        #expect(reported.count == count + 1)
        #expect(reported.allSatisfy { $0.isValid })
    }

    @Test func changingHostsBehindAFormDoesNotStealItsKeyboardFocus() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let surface = TerminalSurface(fontSize: 13)
        let old = TerminalSurfaceHost(surface: surface)
        controller.view.addSubview(old)
        old.frame = CGRect(x: 0, y: 0, width: 500, height: 300)
        surface.focus()
        surface.setFocusAllowed(false)
        #expect(!surface.view.isFirstResponder)

        let field = UITextField(frame: CGRect(x: 0, y: 320, width: 200, height: 44))
        controller.view.addSubview(field)
        field.becomeFirstResponder()
        let next = TerminalSurfaceHost(surface: surface, allowsFocus: false)
        controller.view.addSubview(next)
        next.frame = old.frame
        next.layoutIfNeeded()
        surface.detach(from: old)
        surface.attachedToWindow()
        #expect(field.isFirstResponder)
        #expect(!surface.view.isFirstResponder)
        #expect(surface.view.superview === next)
    }
}
