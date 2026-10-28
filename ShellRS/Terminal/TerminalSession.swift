import Foundation
import Observation
import ShellRSCore

/// A terminal on a saved host: its connection, the shell on it and the
/// screen. It keeps the host as it was when opened, as the desktop's tabs
/// do; reconnecting reads the saved host again.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    enum State: Equatable {
        case connecting
        case connected
        /// Why it ended, if something went wrong.
        case closed(String?)
    }

    let host: Host
    @ObservationIgnored let surface: TerminalSurface
    private(set) var state = State.connecting
    /// What the login asks the user now.
    private(set) var prompt: Prompt?
    /// The last round trip to the server, in milliseconds.
    private(set) var latency: UInt64?
    /// What to do when the user closes the terminal from its own keys.
    @ObservationIgnored var onClose: () -> Void = {}
    /// The host's files over SFTP on this terminal's connection, once
    /// asked for; it outlives reconnecting, its transfers with it.
    private(set) var files: FilesModel?

    @ObservationIgnored private let core: Core
    @ObservationIgnored private var connection: Connection?
    @ObservationIgnored private var terminal: Terminal?
    /// Events from an earlier attempt are dropped.
    @ObservationIgnored private var attempt = 0

    init(host: Host, core: Core, fontSize: Double = AppModel.defaultFontSize) {
        self.host = host
        self.core = core
        surface = TerminalSurface(fontSize: fontSize)
        surface.onInput = { [weak self] bytes in
            self?.input(bytes)
        }
        surface.onResize = { [weak self] size in
            self?.resize(size)
        }
    }

    var isClosed: Bool {
        if case .closed = state {
            return true
        }
        return false
    }

    /// Connects, or connects again after the terminal closed.
    func start() {
        attempt += 1
        let attempt = attempt
        state = .connecting
        prompt = nil
        latency = nil
        let connection: Connection
        do {
            connection = try core.connectHost(id: host.id)
        } catch {
            end(Describe.store(error))
            return
        }
        self.connection = connection
        Task { [weak self] in
            while let event = await connection.nextEvent() {
                guard let self, self.attempt == attempt else {
                    return
                }
                handle(event, on: connection, attempt: attempt)
            }
        }
    }

    /// Ends the terminal and its connection; the screen stays.
    func disconnect() {
        attempt += 1
        terminal?.end()
        connection?.disconnect()
        end(nil)
    }

    /// Whether the connection survived the time the app was away: one the
    /// system closed meanwhile ends the terminal now, through its events.
    /// One that does not answer in time stays open with no latency shown
    /// (it may only be slow, and ending it would end the programs running
    /// there) until the core's keepalive gives up on it.
    @discardableResult
    func checkAlive() async -> Bool {
        guard case .connected = state, let connection else {
            return false
        }
        let attempt = attempt
        do {
            let milliseconds = try await connection.checkAlive()
            if self.attempt == attempt {
                latency = milliseconds
            }
            return true
        } catch {
            if self.attempt == attempt {
                latency = nil
            }
            return false
        }
    }

    /// The files on the host, opening on this terminal's connection; what
    /// comes down goes into the host's folder in 已下载的文件, unless
    /// `downloadsFolder` says where.
    func openFiles(downloadsFolder: URL? = nil) -> FilesModel {
        if let files {
            return files
        }
        let files = FilesModel(
            downloadsFolder: downloadsFolder ?? LocalFolders.downloads(for: host)
        ) { [weak self] in
            guard let connection = self?.connection else {
                throw SshError.NotConnected
            }
            return try await connection.openSftp()
        }
        self.files = files
        return files
    }

    func answer(_ reply: PromptReply) {
        guard let prompt else {
            return
        }
        self.prompt = nil
        connection?.answer(promptId: prompt.id, reply: reply)
    }

    private func handle(_ event: ConnectionEvent, on connection: Connection, attempt: Int) {
        switch event {
        case .prompt(let prompt):
            self.prompt = prompt
        case .connected:
            prompt = nil
            Task {
                await openTerminal(on: connection, attempt: attempt)
            }
        case .latency(let milliseconds):
            latency = milliseconds
        case .closed(let failure):
            end(failure.map(Describe.failure))
        }
    }

    private func openTerminal(on connection: Connection, attempt: Int) async {
        let size = surface.size
        let options = TerminalOptions(
            term: "xterm-256color", columns: size.columns, rows: size.rows,
            width: size.width, height: size.height)
        do {
            let terminal = try await connection.openTerminal(options: options)
            guard self.attempt == attempt else {
                terminal.end()
                return
            }
            self.terminal = terminal
            state = .connected
            files?.terminalConnected()
            // The screen may have changed while the shell started.
            resize(surface.size)
            surface.focus()
            pump(terminal, attempt: attempt)
        } catch {
            guard self.attempt == attempt else {
                return
            }
            connection.disconnect()
            end(Describe.ssh(error))
        }
    }

    private func pump(_ terminal: Terminal, attempt: Int) {
        Task { [weak self] in
            while let event = await terminal.nextEvent() {
                guard let self, self.attempt == attempt else {
                    return
                }
                switch event {
                case .output(let bytes):
                    surface.feed(bytes)
                case .outputDropped(let count):
                    surface.notice(String(localized: "输出太快，跳过了 \(String(count)) 字节"))
                case .exited:
                    connection?.disconnect()
                    end(nil)
                case .failed(let failure):
                    connection?.disconnect()
                    end(Describe.failure(failure))
                }
            }
        }
    }

    /// The terminal has ended: say why in it, as the desktop does.
    private func end(_ reason: String?) {
        if isClosed {
            return
        }
        state = .closed(reason)
        prompt = nil
        terminal = nil
        connection = nil
        files?.terminalClosed()
        if let reason {
            surface.notice(reason)
        }
        surface.notice(String(localized: "已断开连接。按 Enter 重新连接，按 Space 关闭"))
    }

    private func input(_ bytes: Data) {
        switch state {
        case .connected:
            try? terminal?.write(bytes: bytes)
        case .closed:
            // The desktop's keys on a closed terminal.
            if bytes == Data([0x0d]) {
                start()
            } else if bytes == Data([0x20]) {
                onClose()
            }
        case .connecting:
            break
        }
    }

    private func resize(_ size: TerminalSize) {
        try? terminal?.resize(
            columns: size.columns, rows: size.rows, width: size.width, height: size.height)
    }
}
