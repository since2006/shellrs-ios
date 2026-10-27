import SwiftUI

@main
struct ShellRSApp: App {
    @State private var launch = Launch.open()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let model):
                RootView()
                    .environment(model)
            case .failed(let reason):
                LaunchFailedView(reason: reason)
            }
        }
    }
}

/// The core, or why it would not open.
enum Launch {
    case ready(AppModel)
    case failed(String)

    @MainActor
    static func open() -> Launch {
        do {
            return .ready(try AppModel.open())
        } catch {
            return .failed(Describe.core(error))
        }
    }
}

/// The data folder would not open: nothing else can work.
struct LaunchFailedView: View {
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("ShellRS 无法启动", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        }
    }
}
