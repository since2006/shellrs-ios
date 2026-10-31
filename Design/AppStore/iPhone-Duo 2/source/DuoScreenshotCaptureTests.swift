import Foundation
import ShellRSCore
import SwiftUI
import Testing
import UIKit

@testable import ShellRS

/// Temporary capture fixture. Example content is not production telemetry.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHELLRS_CAPTURE_DUO"] == "1"))
struct DuoScreenshotCaptureTests {
    @Test func capture() async throws {
        let language = ProcessInfo.processInfo.environment["SHELLRS_CAPTURE_LANGUAGE"] ?? "zh-Hans"
        let chinese = language == "zh-Hans"
        let test = try TestCore(name: "Screenshot fixture")
        let defaultsName = "DuoScreenshotFixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let model = AppModel(core: test.core, deviceName: "iPhone Duo", defaults: defaults)
        model.fontSize = 16
        let hosts = model.hosts
        let production = try hosts.saveGroup(id: nil, draft: GroupDraft(name: chinese ? "生产环境" : "Production", parent: nil))
        let staging = try hosts.saveGroup(id: nil, draft: GroupDraft(name: chinese ? "开发与测试" : "Development", parent: nil))
        let data = try hosts.saveGroup(id: nil, draft: GroupDraft(name: chinese ? "数据服务" : "Data services", parent: nil))
        let proxy = HostProxy(kind: .socks5, host: "127.0.0.1", port: 22223, user: nil)
        let samples: [(String, String, UInt64)] = [
            (chinese ? "API · 生产" : "API · Prod", "api.example", production),
            (chinese ? "Web · 生产" : "Web · Prod", "web.example", production),
            (chinese ? "Web · 预发布" : "Web · Stage", "stage.example", staging),
            (chinese ? "开发服务器" : "Dev Server", "dev.example", staging),
            ("PostgreSQL", "db.example", data),
            ("Redis", "cache.example", data),
        ]
        var ids: [UInt64] = []
        for (name,address,group) in samples {
            let id = try await hosts.save(id: nil,
                draft: draft(name: name, address: address, user: "deploy", route: .proxy(proxy: proxy), group: group),
                password: .set(value: "screenshot-only"))
            ids.append(id)
        }
        for group in hosts.groups { hosts.setExpanded(group, false) }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        var root = UIHostingController(rootView: RootView().environment(model)
            .environment(\.locale, Locale(identifier: chinese ? "zh_CN" : "en_US"))
            .preferredColorScheme(.light))
        window.rootViewController = root
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        defer {
            for session in model.sessions { session.disconnect() }
            window.isHidden = true
        }
        for index in [5,4,3,1,2,0] {
            try model.connect(try #require(hosts.host(ids[index])))
            let session = try #require(model.shownSession)
            for _ in 0..<300 {
                if let prompt = session.prompt {
                    if case .unknownHost = prompt.kind { session.answer(.trustAndSave) }
                    else if case .password = prompt.kind { session.answer(.answers(answers: ["screenshot-only"])) }
                    else { throw CaptureError.connection }
                }
                if session.state == .connected { break }
                if session.isClosed { throw CaptureError.connection }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(session.state == .connected)
            session.surface.dismissInput()
            if index != 2 && index != 0 { model.close(session) }
        }
        let selected = try #require(model.shownSession)
        hosts.reload()
        let bridge = URL.documentsDirectory.appending(path: "duo-capture", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true)
        for page in ["01-terminal", "02-hosts", "03-files", "04-sync"] {
            model.showingSettings = false
            model.sheet = nil
            model.shownSession = selected
            model.showsFiles = false
            model.sidebarShown = page != "03-files"
            try await Task.sleep(for: .milliseconds(700))
            if page == "02-hosts" { model.shownSession = nil }
            if page == "03-files" {
                model.showsFiles = true
                let files = selected.openFiles()
                files.open()
                try await waitUntil("fixture SFTP opens") { files.state == .connected }
                files.path = ["/srv", "/srv/apps", "/srv/apps/api"]
                // Mount the completed workspace afresh, avoiding a split-view
                // animation snapshot left by the previous StartView screen.
                root = UIHostingController(rootView: RootView().environment(model)
                    .environment(\.locale, Locale(identifier: chinese ? "zh_CN" : "en_US"))
                    .preferredColorScheme(.light))
                window.rootViewController = root
                _ = try await files.list("/srv/apps/api")
                try await waitUntil("the terminal and inspector have settled") {
                    selected.surface.view.bounds.width >= 400
                }
            }
            if page == "04-sync" {
                model.settingsPath = [.sync]
                model.showingSettings = true
            }
            try await Task.sleep(for: .seconds(1))
            // Pre-filled example deployment output, rendered by the actual emulator.
            let narrow = page == "03-files"
            let output = narrow ? """
            \u{1b}[2J\u{1b}[H\u{1b}[36mdeploy@api-prod\u{1b}[0m:~/apps/api$ ls -lh
            total 23M
            drwxr-xr-x  current/
            drwxr-xr-x  releases/
            drwxr-xr-x  shared/
            -rw-r--r--  compose.yaml
            -rwxr-xr-x  deploy.sh
            -rw-r--r--  release.tar.gz

            \u{1b}[36mdeploy@api-prod\u{1b}[0m:~/apps/api$ ./deploy.sh status
            \u{1b}[32m● api-service   running\u{1b}[0m
            \u{1b}[32m● worker        running\u{1b}[0m
            \u{1b}[32m● scheduler     running\u{1b}[0m

            Release     2026.10.22
            Health      \u{1b}[32mpassing\u{1b}[0m
            Uptime      14 days

            \u{1b}[36mdeploy@api-prod\u{1b}[0m:~/apps/api$\u{20}
            """ : """
            \u{1b}[2J\u{1b}[H\u{1b}[36mdeploy@api-prod\u{1b}[0m:~$ ./health-check

            \u{1b}[1;32mALL SYSTEMS OPERATIONAL\u{1b}[0m
            ───────────────────────────────────────────────
            SERVICE          STATUS       INSTANCES
            ───────────────────────────────────────────────
            api-gateway      \u{1b}[32mhealthy\u{1b}[0m      3 / 3
            web-frontend     \u{1b}[32mhealthy\u{1b}[0m      2 / 2
            postgres         \u{1b}[32mhealthy\u{1b}[0m      1 / 1
            redis            \u{1b}[32mhealthy\u{1b}[0m      1 / 1
            ───────────────────────────────────────────────

            Release          v2.8.0
            Environment      production
            Last deployment  2026-10-22 09:30 UTC

            \u{1b}[32m✓\u{1b}[0m Database migrations applied
            \u{1b}[32m✓\u{1b}[0m Health checks passed
            \u{1b}[32m✓\u{1b}[0m Rolling deployment completed

            \u{1b}[36mdeploy@api-prod\u{1b}[0m:~$\u{20}
            """
            selected.surface.feed(Data(output.replacingOccurrences(of: "\n", with: "\r\n").utf8))
            for session in model.sessions { session.surface.dismissInput() }
            window.endEditing(true)
            try await Task.sleep(for: .milliseconds(400))
            let token = "\(language)/\(page)"
            try token.write(to: bridge.appending(path: "ready.txt"), atomically: true, encoding: .utf8)
            print("CAPTURE READY \(token)")
            for _ in 0..<9000 {
                if (try? String(contentsOf: bridge.appending(path: "next.txt"), encoding: .utf8)) == token { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try? FileManager.default.removeItem(at: bridge.appending(path: "ready.txt"))
        }
    }
    enum CaptureError: Error { case connection }
}
