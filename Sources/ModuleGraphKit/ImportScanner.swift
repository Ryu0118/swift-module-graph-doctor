import Foundation

/// Extracts import statements and their access levels from Swift source.
///
/// Recognizes SE-0409 access-level imports (`internal import Foo`, etc.) and
/// distinguishes imports exposed in a module's public interface
/// (`public import` / unqualified `import` / `@_exported import`) from those
/// that are not. Unqualified imports are treated as exposed to match Swift's
/// default behavior until `InternalImportsByDefault` is enabled.
package enum ImportScanner {
    /// An extracted import statement
    package struct ScannedImport: Sendable, Equatable {
        /// Name of the imported module
        package let module: String
        /// Whether it is exposed in the module's public interface
        package let isInterfaceVisible: Bool

        /// Creates an instance from a module name and visibility flag
        package init(module: String, isInterfaceVisible: Bool) {
            self.module = module
            self.isInterfaceVisible = isInterfaceVisible
        }
    }

    /// Extracts import statements from a single source file
    package static func scan(source: String) -> [ScannedImport] {
        // Regex is not Sendable, so build it locally instead of holding it statically
        let pattern = #/
            ^\s*
            (?:@[A-Za-z_]\w*\s+)*
            (?:(public|package|internal|fileprivate|private)\s+)?
            import\s+
            (?:(?:typealias|struct|class|enum|protocol|func|var|let)\s+)?
            ([A-Za-z_]\w*)
        /#
        var results: [ScannedImport] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let match = line.matches(of: pattern).first else { continue }
            let accessLevel = match.output.1.map(String.init)
            let module = String(match.output.2)
            // @_exported is already matched as an attribute (treated as unqualified = exposed).
            // Only no access level and `public` are exposed in the public interface
            let visible = accessLevel == nil || accessLevel == "public"
            results.append(ScannedImport(module: module, isInterfaceVisible: visible))
        }
        return results
    }
}
