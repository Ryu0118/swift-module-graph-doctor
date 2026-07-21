import Foundation
import SwiftModuleGraph

/// Computes the transitive closure size (Load) on the interface graph formed by exported imports.
///
/// When module B is compiled, imports exposed in the public interfaces of the
/// modules B imports (`public import` / unqualified `import`) trigger cascading
/// swiftmodule loads. `Load(M)` = the number of modules transitively reachable
/// from M along interface-visible import edges (local targets + external
/// modules, excluding M itself). Converting to `internal import` cuts this
/// closure; this metric makes that effect observable as a number.
package enum InterfaceLoadAnalyzer {
    /// Load value for one target
    package struct LoadEntry: Sendable, Codable, Equatable {
        /// The target (`package/target` form)
        package let target: String
        /// Interface closure size (excluding the target itself)
        package let load: Int

        /// Creates an entry from a target and its Load value
        package init(target: String, load: Int) {
            self.target = target
            self.load = load
        }
    }

    /// Computes the Load of each target from per-target sets of interface-visible imported module names.
    ///
    /// - Parameters:
    ///   - interfaceImports: target -> set of interface-visible imported module names
    ///   - moduleTable: module name -> local target (assumes target name = module name)
    /// - Returns: entries sorted by Load in descending order
    package static func analyze(
        interfaceImports: [TargetID: Set<String>],
        moduleTable: [String: TargetID],
    ) -> [LoadEntry] {
        var memo: [TargetID: Set<String>] = [:]
        var visiting: Set<TargetID> = []

        func loadSet(of target: TargetID) -> Set<String> {
            if let cached = memo[target] {
                return cached
            }
            // Return empty on an import cycle (module cycles are normally impossible in Swift)
            guard !visiting.contains(target) else { return [] }
            visiting.insert(target)
            defer { visiting.remove(target) }

            var loaded: Set<String> = []
            for module in interfaceImports[target] ?? [] {
                loaded.insert(module)
                if let local = moduleTable[module] {
                    loaded.formUnion(loadSet(of: local))
                }
            }
            loaded.remove(target.targetName)
            memo[target] = loaded
            return loaded
        }

        return interfaceImports.keys
            .map { LoadEntry(target: $0.description, load: loadSet(of: $0).count) }
            .sorted { ($0.load, $1.target) > ($1.load, $0.target) }
    }

    /// Collects per-target sets of interface-visible imported module names from describe results and the file system.
    /// Targets whose sources cannot be read are silently skipped (tolerant of missing generated code, etc.)
    package static func collectInterfaceImports(
        packages: [(directory: URL, package: DescribedPackage)],
        excludedTargets: Set<TargetID> = [],
    ) -> [TargetID: Set<String>] {
        var results: [TargetID: Set<String>] = [:]
        for (directory, package) in packages {
            for target in package.targets where target.type != "test" {
                let id = TargetID(packageName: package.name, targetName: target.name)
                guard !excludedTargets.contains(id), let targetPath = target.path else { continue }
                results[id] = interfaceImports(
                    of: target,
                    targetDirectory: directory.appendingPathComponent(targetPath),
                )
            }
        }
        return results
    }

    /// Scans one target's sources and returns the set of interface-visible imported module names
    private static func interfaceImports(
        of target: DescribedPackage.Target,
        targetDirectory: URL,
    ) -> Set<String> {
        var imports: Set<String> = []
        for source in target.sources ?? [] where source.hasSuffix(".swift") {
            let fileURL = targetDirectory.appendingPathComponent(source)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for scanned in ImportScanner.scan(source: content) where scanned.isInterfaceVisible {
                imports.insert(scanned.module)
            }
        }
        return imports
    }
}
