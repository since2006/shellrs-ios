import Observation
import SwiftUI
import Testing
import UIKit

@testable import ShellRS

@MainActor
@Suite(.serialized)
struct PresentationContinuityTests {
    @Test func anEditorAndItsTypedTextSurviveReplacingTheLayoutBranch() async throws {
        let test = try TestCore()
        let model = AppModel(core: test.core, deviceName: "Duo")
        let size = WindowSize()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: Harness(model: model, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        model.sheet = .host(.new(group: nil))
        try await waitUntil("the editor appears") {
            controller.presentedViewController != nil
        }
        let editor = try #require(controller.presentedViewController)
        try await waitUntil("the editor's fields appear") {
            !fields(in: editor.view).isEmpty
        }
        let field = try #require(fields(in: editor.view).first)
        field.becomeFirstResponder()
        field.text = "unfinished-host-name"
        field.sendActions(for: .editingChanged)

        size.width = 900
        try await waitUntil("the wide shell replaces the compact one") { model.isWide }
        #expect(controller.presentedViewController === editor)
        #expect(fields(in: editor.view).contains { $0 === field })
        #expect(field.text == "unfinished-host-name")
        size.width = 350
        try await waitUntil("the compact shell returns") { !model.isWide }
        #expect(controller.presentedViewController === editor)
        #expect(field.text == "unfinished-host-name")
        model.dismissSheet()
    }

    private func fields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
    }

    @Observable final class WindowSize {
        var width = 350.0
    }

    private struct Harness: View {
        let model: AppModel
        let size: WindowSize

        var body: some View {
            RootView()
                .environment(model)
                .environment(\.horizontalSizeClass, size.width > 600 ? .regular : .compact)
                .frame(width: size.width, height: 600)
        }
    }
}
