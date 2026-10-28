import Foundation
import Testing

@testable import ShellRS

/// 开源许可 lists what the app ships, each with its license's text.
struct LicensesTests {
    @Test func theBundledListHasWhatTheAppShips() throws {
        let licenses = OpenSourceLicenses.bundled()
        let names = Set(licenses.packages.map(\.name))
        for shipped in ["SwiftTerm", "russh", "tokio", "uniffi", "Simple Icons"] {
            #expect(names.contains(shipped), "\(shipped) is not listed")
        }
        // shell-rs's own crates are the app, not what it uses.
        #expect(!names.contains("shellrs-mobile"))
        for package in licenses.packages {
            #expect(!package.license.isEmpty, "\(package.title) has no license")
            #expect(!package.texts.isEmpty, "\(package.title) has no license text")
            for key in package.texts {
                #expect(licenses.texts[key]?.isEmpty == false, "\(package.title): text \(key)")
            }
        }
    }
}
