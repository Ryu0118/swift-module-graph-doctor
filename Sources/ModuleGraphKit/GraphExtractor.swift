import Foundation

/// Orchestrator that ties together package scanning, describe execution, and DAG assembly
package struct GraphExtractor: Sendable {
    private let describer: any PackageDescribing

    /// Creates an instance with an injected describe runner (defaults to real process execution)
    package init(describer: any PackageDescribing = SwiftPackageDescriber()) {
        self.describer = describer
    }

    /// Assembles a graph from all packages under the scan roots
    package func extract(from roots: [URL]) async throws -> ModuleGraph {
        let directories = PackageLocator.locatePackages(under: roots)
        return try await extract(packageDirectories: directories)
    }

    /// Assembles a graph from a set of package directories. describe runs in parallel
    package func extract(packageDirectories: [URL]) async throws -> ModuleGraph {
        try await GraphAssembler.assemble(
            packages: describePackages(packageDirectories: packageDirectories).map(\.package),
        )
    }

    /// Describes the package directories and returns each paired with its directory.
    /// Used by analyses that need source file locations, such as import analysis
    package func describePackages(
        packageDirectories: [URL],
    ) async throws -> [(directory: URL, package: DescribedPackage)] {
        try await withThrowingTaskGroup(
            of: (Int, DescribedPackage).self,
        ) { group in
            for (index, directory) in packageDirectories.enumerated() {
                group.addTask {
                    let data = try await describer.describe(packageDirectory: directory)
                    return try (index, DescribedPackage.decode(from: data))
                }
            }
            var results: [(Int, DescribedPackage)] = []
            for try await result in group {
                results.append(result)
            }
            // describe completion order is nondeterministic; re-sort by input order to keep assembly deterministic
            return results.sorted { $0.0 < $1.0 }
                .map { (packageDirectories[$0.0], $0.1) }
        }
    }
}
