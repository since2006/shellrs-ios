import Foundation
import Observation
import ShellRSCore

/// The host form's 测试连接, as the desktop's: log in with what the form
/// holds, saved or not, and say whether it got in. Nothing is saved, and
/// the host does not go among the recent ones; a host key the user trusts
/// is kept, as any connection keeps it.
@MainActor
@Observable
final class ConnectionTest {
    enum Outcome: Equatable {
        /// In, and the round trip once in.
        case connected(latency: UInt64?)
        case failed(String)
    }

    private(set) var running = false
    private(set) var outcome: Outcome?
    /// What the login asks the user now: a host key to trust, a password.
    private(set) var prompt: Prompt?

    @ObservationIgnored private var connection: Connection?
    /// Events of an earlier try are dropped.
    @ObservationIgnored private var attempt = 0

    /// Tries `draft`, the form of `editing` or of a new host, with the
    /// password typed for a host logging in with its own; `nil` asks.
    func run(core: Core, editing: UInt64?, draft: HostDraft, password: String?) {
        stop()
        attempt += 1
        let attempt = attempt
        outcome = nil
        let connection: Connection
        do {
            connection = try core.testHost(editing: editing, draft: draft, password: password)
        } catch {
            outcome = .failed(Describe.store(error))
            return
        }
        self.connection = connection
        running = true
        Task { [weak self] in
            while let event = await connection.nextEvent() {
                guard let self, self.attempt == attempt else {
                    connection.disconnect()
                    return
                }
                switch event {
                case .prompt(let prompt):
                    self.prompt = prompt
                case .connected:
                    self.prompt = nil
                    let latency = try? await connection.checkAlive()
                    guard self.attempt == attempt else { return }
                    finish(.connected(latency: latency))
                    connection.disconnect()
                case .latency:
                    break
                case .closed(let failure):
                    if let failure {
                        finish(.failed(Describe.failure(failure)))
                    } else if running {
                        // Closed here, without an outcome.
                        finish(nil)
                    }
                    return
                }
            }
        }
    }

    func answer(_ reply: PromptReply) {
        guard let prompt, let connection else {
            return
        }
        self.prompt = nil
        connection.answer(promptId: prompt.id, reply: reply)
    }

    /// The form cannot be tried as it is.
    func fail(_ reason: String) {
        stop()
        outcome = .failed(reason)
    }

    /// Stops trying; the last outcome stays.
    func stop() {
        attempt += 1
        connection?.disconnect()
        connection = nil
        running = false
        prompt = nil
    }

    /// The form changed: what was tried is not what it holds now.
    func reset() {
        stop()
        outcome = nil
    }

    private func finish(_ outcome: Outcome?) {
        running = false
        prompt = nil
        connection = nil
        self.outcome = outcome
    }
}
