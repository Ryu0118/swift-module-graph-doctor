import FileManagerProtocol
import Foundation
import Yams

/// Violations baseline: a sorted list of stable violation keys stored as YAML.
///
/// Known violations are committed to `violations-baseline.yml` (boy-scout style):
/// only violations whose stable keys are absent from the baseline are reported as
/// errors, so a legacy codebase can adopt the rules incrementally.
package enum ViolationsBaseline {
    /// Loads baselined keys (empty set when the file does not exist)
    package static func load(
        from url: URL,
        fileManager: any FileManagerProtocol = FileManager.default,
    ) throws -> Set<String> {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try Set(YAMLDecoder().decode([String].self, from: yaml))
    }

    /// Writes keys sorted so the file is diff-stable and idempotent
    package static func save(_ keys: Set<String>, to url: URL) throws {
        let yaml = try YAMLEncoder().encode(keys.sorted())
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
