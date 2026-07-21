import Foundation
import ModuleGraphKit

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
        /// Resolved closure roots
        package let rootIDs: [TargetID]
    }

    /// Errors shared by the pipeline
    package enum Error: Swift.Error, LocalizedError {
        /// A configured root matches no target in the graph
        case rootNotFound(String)
        /// A bare root name matches targets in multiple packages
        case ambiguousRoot(String, candidates: [String])
        /// Root auto-detection found nothing (empty graph)
        case noRootsDetected
        /// No packages found under the configured scan paths
        case noPackagesFound([String])

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .rootNotFound(root):
                "root '\(root)' does not match any target"
            case let .ambiguousRoot(root, candidates):
                "root '\(root)' is ambiguous; use <package>/<target>: "
                    + candidates.joined(separator: ", ")
            case .noRootsDetected:
                "could not auto-detect any root target; set `root:` in the config"
            case let .noPackagesFound(paths):
                "no packages found under: \(paths.joined(separator: ", "))"
            }
        }
    }

    /// Runs the shared pipeline. Relative paths are resolved against `baseDirectory`
    package static func analyze(
        configuration: Configuration,
        baseDirectory: URL,
        extractor: GraphExtractor,
    ) async throws -> Analysis {
        let directories = locatePackageDirectories(configuration: configuration, baseDirectory: baseDirectory)
        guard !directories.isEmpty else {
            throw Error.noPackagesFound(configuration.path)
        }

        let described = try await extractor.describePackages(packageDirectories: directories)
        let graph = GraphAssembler.assemble(packages: described.map(\.package))
        let rootIDs = try resolveRoots(configuration.root, graph: graph)
        let scope = graph.closure(of: rootIDs)
        let costPerTarget = configuration.costPerTarget ?? 1.0
        let parallelism = configuration.cores ?? ProcessInfo.processInfo.activeProcessorCount

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
            rootIDs: rootIDs,
        )
    }

    /// Loads the configured weights file; absent configuration or file yields nil
    package static func loadWeights(configuration: Configuration, baseDirectory: URL) -> TargetWeights? {
        guard let raw = configuration.weights else { return nil }
        let url = raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
        return try? TargetWeights.load(from: url)
    }

    /// Resolves configured roots against the assembled graph.
    ///
    /// - `<package>/<target>` selects exactly that target
    /// - a bare name selects the unique target with that name (error when ambiguous)
    /// - an empty list auto-detects: every non-test target no other target depends on
    package static func resolveRoots(_ raw: [String], graph: ModuleGraph) throws -> [TargetID] {
        guard !raw.isEmpty else {
            let dependents = graph.reverseEdges()
            let sinks = graph.nonTestNodes
                .filter { (dependents[$0] ?? []).isDisjoint(with: graph.nonTestNodes) }
                .sorted()
            guard !sinks.isEmpty else { throw Error.noRootsDetected }
            return sinks
        }
        return try raw.map { name in
            if name.contains("/") {
                let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
                let id = TargetID(packageName: parts[0], targetName: parts.count > 1 ? parts[1] : "")
                guard graph.nodes.contains(id) else { throw Error.rootNotFound(name) }
                return id
            }
            let candidates = graph.nonTestNodes.filter { $0.targetName == name }.sorted()
            switch candidates.count {
            case 0: throw Error.rootNotFound(name)
            case 1: return candidates[0]
            default: throw Error.ambiguousRoot(name, candidates: candidates.map(\.description))
            }
        }
    }

    private static func locatePackageDirectories(
        configuration: Configuration,
        baseDirectory: URL,
    ) -> [URL] {
        let roots = configuration.path.map { raw in
            raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
        }
        let excluded = Set(configuration.exclude)
        return PackageLocator.locatePackages(under: roots)
            .filter { !excluded.contains($0.lastPathComponent) }
    }
}
