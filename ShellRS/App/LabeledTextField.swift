import SwiftUI

/// A text field with its label beside it, as the Settings app lays them
/// out: a filled-in field still says what it is.
struct LabeledTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: Text?
    /// A password or passphrase, never shown.
    var secure = false

    init(
        _ title: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil,
        secure: Bool = false
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.secure = secure
    }

    var body: some View {
        LabeledContent(title) {
            if secure {
                SecureField(title, text: $text, prompt: prompt)
            } else {
                TextField(title, text: $text, prompt: prompt)
            }
        }
        .multilineTextAlignment(.trailing)
    }
}
