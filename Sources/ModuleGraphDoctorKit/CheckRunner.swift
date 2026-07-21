import Foundation

/// Runs the baseline comparison gate: graph extraction, metrics computation, baseline loading, and comparison
package struct CheckRunner: Sendable {
    private let extractor: GraphExtractor

    /// Creates an instance with an injected extractor (defaults to real process execution)
    package init(extractor: GraphExtractor = GraphExtractor()) {
        self.extractor = extractor
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
        guard FileManager.default.fileExists(atPath: baselineURL.path(percentEncoded: false)) else {
            throw Error.baselineNotFound(baselineURL.path(percentEncoded: false))
        }
        let baseline = try GraphBaseline.load(from: baselineURL)
        let current = try await snapshot(configuration: configuration, baseDirectory: baseDirectory)

        let thresholds = BaselineGate.Thresholds(
            makespanWarnSeconds: configuration.check?.makespanWarnSeconds ?? 0.5,
            makespanErrorSeconds: configuration.check?.makespanErrorSeconds ?? 1.0,
        )
        let findings = BaselineGate.evaluate(
            baseline: baseline,
            current: current.metrics,
            currentEdges: current.edges,
            thresholds: thresholds,
        ).sorted { ($0.severity, $1.message) > ($1.severity, $0.message) }
        return Result(findings: findings)
    }

    /// Rewrites the baseline with the current graph
    package func updateBaseline(configuration: Configuration, baseDirectory: URL) async throws -> URL {
        let current = try await snapshot(configuration: configuration, baseDirectory: baseDirectory)
        let baseline = GraphBaseline(
            roots: configuration.analysis.roots,
            costPerTarget: current.costPerTarget,
            parallelism: current.parallelism,
            targetCount: current.metrics.targetCount,
            criticalPathLength: current.metrics.criticalPathLength,
            simulatedMakespan: current.metrics.simulatedMakespan,
            edges: current.edges,
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
    }

    private func snapshot(configuration: Configuration, baseDirectory: URL) async throws -> Snapshot {
        let analysis = try await GraphAnalysisSession.analyze(
            configuration: configuration,
            baseDirectory: baseDirectory,
            extractor: extractor,
        )
        var edges: [String: [String]] = [:]
        for source in analysis.scope {
            let inScope = analysis.graph.dependencies(of: source).filter(analysis.scope.contains)
            edges[source.description] = inScope.map(\.description).sorted()
        }
        return Snapshot(
            metrics: analysis.metrics,
            edges: edges,
            costPerTarget: analysis.costPerTarget,
            parallelism: analysis.parallelism,
        )
    }

    private func baselineURL(configuration: Configuration, baseDirectory: URL) -> URL {
        let raw = configuration.check?.baseline ?? "graph-baseline.json"
        return raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
    }
}
