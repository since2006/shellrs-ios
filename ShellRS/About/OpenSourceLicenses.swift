import Foundation

/// The open-source code the app ships and its licenses, as
/// scripts/licenses.py wrote them into Licenses.json.
struct OpenSourceLicenses: Decodable {
    struct Package: Decodable {
        let name: String
        let version: String
        /// An SPDX expression: the license taken, or all a package is under
        /// at once.
        let license: String
        let url: String
        /// Keys into `texts`.
        let texts: [String]

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
