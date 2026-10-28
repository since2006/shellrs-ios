import SwiftUI

/// The open-source code the app ships and its licenses, as
/// scripts/licenses.py wrote them into Licenses.json.
struct OpenSourceLicenses: Decodable {
    struct Package: Decodable, Identifiable {
        let name: String
        let version: String
        /// An SPDX expression: the license taken, or all a package is under
        /// at once.
        let license: String
        let url: String
        /// Keys into `texts`.
        let texts: [String]

        var id: String { "\(name) \(version)" }

        /// Its name and version, as a title.
        var title: String {
            version.isEmpty ? name : "\(name) \(version)"
        }
    }

    let packages: [Package]
    let texts: [String: String]

    /// The list in the app's bundle; empty if it is missing, which a test
    /// guards against.
    static func bundled() -> OpenSourceLicenses {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let licenses = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return OpenSourceLicenses(packages: [], texts: [:])
        }
        return licenses
    }
}

/// 开源许可: each package, searchable, with its license's text a tap away.
struct LicensesView: View {
    @State private var licenses = OpenSourceLicenses.bundled()
    @State private var search = ""

    var body: some View {
        List {
            Section {
                ForEach(shown) { package in
                    NavigationLink {
                        LicenseView(
                            package: package, texts: package.texts.compactMap { licenses.texts[$0] })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: package.name)
                                Text(verbatim: package.version)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(verbatim: package.license)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } footer: {
                if search.isEmpty {
                    Text("ShellRS 用到的开源软件，点开看许可证全文。")
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shown: [OpenSourceLicenses.Package] {
        let words = search.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else {
            return licenses.packages
        }
        return licenses.packages.filter {
            $0.name.localizedCaseInsensitiveContains(words)
                || $0.license.localizedCaseInsensitiveContains(words)
        }
    }
}

/// A package's license, in full.
private struct LicenseView: View {
    let package: OpenSourceLicenses.Package
    let texts: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: package.license)
                        .font(.headline)
                    if let url = URL(string: package.url) {
                        Link(destination: url) {
                            Text(verbatim: package.url)
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                    Text(verbatim: text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(Text(verbatim: package.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
