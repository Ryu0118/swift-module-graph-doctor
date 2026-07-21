import FileManagerProtocol
import Foundation
import SwiftModuleGraph

/// Runs the baseline comparison gate: graph extraction, metrics computation, baseline loading, and comparison
package struct CheckRunner: Sendable {
    private let extractor: GraphExtractor
    private let fileManager: any FileManagerProtocol

    /// Creates an instance with injected extractor and file manager (defaults to real implementations)
    package init(
        extractor: GraphExtractor = GraphExtractor(),
        fileManager: any FileManagerProtocol = FileManager.default,
    ) {
        self.extractor = extractor
        self.fileManager = fileManager
    }

    /// Result of a check run
    package struct Result: Sendable {
        /// Comparison findings (severity descending, then message ascending)
        package let findings: [BaselineGate.Finding]
        /// Whether any error is present (used for the exit code)
        package var hasError: Bool {
            findings.contains { $0.severity == .error }
        }
    }

    /// Runtime errors
    package enum Error: Swift.Error, LocalizedError {
        /// The baseline file does not exist
        case baselineNotFound(String)

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .baselineNotFound(path):
                "baseline not found at \(path). Run `check --update-baseline` to create it."
            }
        }
    }

    /// Compares against the baseline
    package func run(configuration: Configuration, baseDirectory: URL) async throws -> Result {
        let baselineURL = baselineURL(configuration: configuration, baseDirectory: baseDirectory)
        guard fileManager.fileExists(atPath: baselineURL.path(percentEncoded: false)) else {
            throw Error.baselineNotFound(baselineURL.path(percentEncoded: false))
        }
        let baseline = try GraphBaseline.load(from: baselineURL)
        let analysis = try await GraphAnalysisSession.analyze(
            configuration: configuration,
            baseDirectory: baseDirectory,
            extractor: extractor,
        )
        let current = await snapshot(from: analysis)

        let thresholds = BaselineGate.Thresholds(
            makespanWarnPercent: configuration.check?.makespanWarnPercent ?? 5,
            makespanErrorPercent: configuration.check?.makespanErrorPercent ?? 10,
            buildCostWarnPercent: configuration.check?.buildCostWarnPercent ?? 10,
            buildCostErrorPercent: configuration.check?.buildCostErrorPercent ?? 25,
        )
        let findings = BaselineGate.evaluate(
            baseline: baseline,
            current: current.metrics,
            currentEdges: current.edges,
            currentFeatureCosts: current.buildCosts,
            thresholds: thresholds,
        )
        return Result(findings: findings.sorted { ($0.severity, $1.message) > ($1.severity, $0.message) })
    }

    /// Rewrites the baseline with the current graph
    package func updateBaseline(configuration: Configuration, baseDirectory: URL) async throws -> URL {
        let analysis = try await GraphAnalysisSession.analyze(
            configuration: configuration,
            baseDirectory: baseDirectory,
            extractor: extractor,
        )
        let current = await snapshot(from: analysis)
        let baseline = GraphBaseline(
            roots: analysis.rootIDs.map(\.description),
            costPerTarget: current.costPerTarget,
            parallelism: current.parallelism,
            targetCount: current.metrics.targetCount,
            criticalPathLength: current.metrics.criticalPathLength,
            simulatedMakespan: current.metrics.simulatedMakespan,
            edges: current.edges,
            buildCosts: current.buildCosts,
        )
        let url = baselineURL(configuration: configuration, baseDirectory: baseDirectory)
        try baseline.save(to: url)
        return url
    }

    private struct Snapshot {
        let metrics: WorkSpanMetrics
        let edges: [String: [String]]
        let costPerTarget: Double
        let parallelism: Int
        let buildCosts: [String: Double]?
    }

    private func snapshot(from analysis: GraphAnalysisSession.Analysis) async -> Snapshot {
        var edges: [String: [String]] = [:]
        for source in analysis.scope {
            let inScope = analysis.graph.dependencies(of: source).filter(analysis.scope.contains)
            edges[source.description] = inScope.map(\.description).sorted()
        }
        return await Snapshot(
            metrics: analysis.metrics,
            edges: edges,
            costPerTarget: analysis.costPerTarget,
            parallelism: analysis.parallelism,
            buildCosts: buildCosts(analysis: analysis),
        )
    }

    /// Build-cost snapshot for every target in scope (nil without weights)
    private func buildCosts(analysis: GraphAnalysisSession.Analysis) async -> [String: Double]? {
        guard let weights = analysis.weights else { return nil }
        let entries = await BuildCostAnalyzer.costs(
            of: analysis.scope.sorted(),
            graph: analysis.graph,
            weights: weights,
        )
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.target, $0.cost) })
    }

    private func baselineURL(configuration: Configuration, baseDirectory: URL) -> URL {
        let raw = configuration.check?.baseline ?? ".module-graph-doctor/graph-baseline.json"
        return raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
    }
}
