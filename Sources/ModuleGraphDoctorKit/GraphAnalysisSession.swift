import Foundation

/// Shared pipeline used by both `diagnose` and `check`:
/// locate packages -> describe -> assemble graph -> compute closure and
/// work-span metrics (makespan >= max(T_inf, T_1/p)).
package enum GraphAnalysisSession {
    /// Result of the shared analysis pipeline
    package struct Analysis: Sendable {
        /// The assembled module graph
        package let graph: ModuleGraph
        /// Closure of the configured roots
        package let scope: Set<TargetID>
        /// Work-span metrics over the closure
        package let metrics: WorkSpanMetrics
        /// Described packages paired with their directories (for source-level analyses)
        package let described: [(directory: URL, package: DescribedPackage)]
        /// Effective per-target cost c (seconds)
        package let costPerTarget: Double
        /// Effective parallelism p
        package let parallelism: Int
        /// Measured target weights (nil when not configured or the file is absent)
        package let weights: TargetWeights?
    }

    /// Errors shared by the pipeline
    package enum Error: Swift.Error, LocalizedError {
        /// Configured roots are empty or not in `<package>/<target>` form
        case invalidRoots([String])
        /// No packages found under the configured scan roots
        case noPackagesFound([String])

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .invalidRoots(roots):
                "analysis.roots must be '<package>/<target>' format: \(roots.joined(separator: ", "))"
            case let .noPackagesFound(roots):
                "no packages found under: \(roots.joined(separator: ", "))"
            }
        }
    }

    /// Runs the shared pipeline. Relative paths are resolved against `baseDirectory`
    package static func analyze(
        configuration: Configuration,
        baseDirectory: URL,
        extractor: GraphExtractor,
    ) async throws -> Analysis {
        let rootIDs = configuration.analysis.roots.compactMap(Configuration.parseTargetID)
        guard !rootIDs.isEmpty, rootIDs.count == configuration.analysis.roots.count else {
            throw Error.invalidRoots(configuration.analysis.roots)
        }
        let directories = locatePackageDirectories(configuration: configuration, baseDirectory: baseDirectory)
        guard !directories.isEmpty else {
            throw Error.noPackagesFound(configuration.packages.roots)
        }

        let described = try await extractor.describePackages(packageDirectories: directories)
        let graph = GraphAssembler.assemble(packages: described.map(\.package))
        let scope = graph.closure(of: rootIDs)
        let costPerTarget = configuration.analysis.costPerTarget ?? 1.0
        let parallelism = configuration.analysis.parallelism ?? ProcessInfo.processInfo.activeProcessorCount

        return Analysis(
            graph: graph,
            scope: scope,
            metrics: WorkSpanAnalyzer.analyze(
                graph: graph,
                scope: scope,
                costPerTarget: costPerTarget,
                parallelism: parallelism,
            ),
            described: described,
            costPerTarget: costPerTarget,
            parallelism: parallelism,
            weights: loadWeights(configuration: configuration, baseDirectory: baseDirectory),
        )
    }

    /// Loads the configured weights file; absent configuration or file yields nil
    package static func loadWeights(configuration: Configuration, baseDirectory: URL) -> TargetWeights? {
        guard let raw = configuration.weights else { return nil }
        let url = raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
        return try? TargetWeights.load(from: url)
    }

    private static func locatePackageDirectories(
        configuration: Configuration,
        baseDirectory: URL,
    ) -> [URL] {
        let roots = configuration.packages.roots.map { raw in
            raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
        }
        let excluded = Set(configuration.packages.exclude ?? [])
        return PackageLocator.locatePackages(under: roots)
            .filter { !excluded.contains($0.lastPathComponent) }
    }
}
