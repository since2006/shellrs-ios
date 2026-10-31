import SwiftUI

extension EnvironmentValues {
    /// Whether the window is a wide one, its sidebar beside the
    /// terminals: what is shown over it may want to show otherwise.
    @Entry var wideWindow = false
}

extension View {
    /// Asks before something that cannot be undone, as `confirmationDialog`
    /// does along the bottom of a narrow window; a wide window asks in an
    /// alert instead, where the dialog would be a popover pointing at the
    /// middle of the whole list rather than at the row it asks about.
    /// `actions` brings its own cancel button only if `cancels`; the alert
    /// gets 取消 otherwise, as the dialog does.
    func confirmation<T, A: View, M: View>(
        _ title: Text, isPresented: Binding<Bool>, presenting data: T?, cancels: Bool = false,
        @ViewBuilder actions: @escaping (T) -> A, @ViewBuilder message: @escaping (T) -> M
    ) -> some View {
        modifier(
            Confirmation(
                title: title, isPresented: isPresented, data: data, cancels: cancels,
                actions: actions, message: message))
    }

    func confirmation<A: View, M: View>(
        _ title: Text, isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M
    ) -> some View {
        confirmation(
            title, isPresented: isPresented, presenting: (), actions: { _ in actions() },
            message: { _ in message() })
    }
}

private struct Confirmation<T, A: View, M: View>: ViewModifier {
    let title: Text
    let isPresented: Binding<Bool>
    let data: T?
    let cancels: Bool
    let actions: (T) -> A
    let message: (T) -> M
    @Environment(\.wideWindow) private var wide
    @State private var presentationWide: Bool?

    func body(content: Content) -> some View {
        // Both are always there, one of them shown: choosing between them
        // would make the content another view, its state lost, as the
        // window widens.
        let usesAlert = presentationWide ?? wide
        content
            .alert(title, isPresented: shown(if: usesAlert), presenting: data) { data in
                actions(data)
                if !cancels {
                    Button("取消", role: .cancel) {}
                }
            } message: { data in
                message(data)
            }
            .confirmationDialog(
                title, isPresented: shown(if: !usesAlert), titleVisibility: .visible,
                presenting: data,
                actions: actions, message: message
            )
            .onChange(of: isPresented.wrappedValue, initial: true) { _, presented in
                if presented {
                    if presentationWide == nil { presentationWide = wide }
                } else {
                    presentationWide = nil
                }
            }
    }

    private func shown(if active: Bool) -> Binding<Bool> {
        Binding(
            get: { active && isPresented.wrappedValue },
            set: { isPresented.wrappedValue = $0 })
    }
}
