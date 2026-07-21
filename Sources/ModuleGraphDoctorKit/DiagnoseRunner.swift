import Foundation

/// Report produced by a diagnose run
package struct DiagnoseReport: Sendable, Codable {
    /// Closure roots (`package/target` form)
    package let roots: [String]
    /// Per-target cost used for the analysis (seconds)
    package let costPerTarget: Double
    /// Parallelism used for the analysis
    package let parallelism: Int
    /// Work-span metrics
    package let workSpan: WorkSpanMetrics
    /// Top ranking of interface closure sizes for exported imports
    package let topInterfaceLoads: [InterfaceLoadAnalyzer.LoadEntry]
    /// Top ranking of feature closure costs (present only when weights are configured)
    package let topFeatureCosts: [FeatureCostAnalyzer.CostEntry]?
}

/// Takes a configuration and performs graph extraction, metrics computation, and report generation
package struct DiagnoseRunner: Sendable {
    private let extractor: GraphExtractor

    /// Creates an instance with an injected extractor (defaults to real process execution)
    package init(extractor: GraphExtractor = GraphExtractor()) {
        self.extractor = extractor
    }

    /// Runs diagnose per the configuration. Relative paths resolve against `baseDirectory`
    package func run(configuration: Configuration, baseDirectory: URL) async throws -> DiagnoseReport {
        let analysis = try await GraphAnalysisSession.analyze(
            configuration: configuration,
            baseDirectory: baseDirectory,
            extractor: extractor,
        )
        let described = analysis.described
        let graph = analysis.graph
        let scope = analysis.scope
        let metrics = analysis.metrics

        let interfaceImports = InterfaceLoadAnalyzer.collectInterfaceImports(packages: described)
        var moduleTable: [String: TargetID] = [:]
        for node in graph.nodes {
            moduleTable[node.targetName] = node
        }
        let loads = InterfaceLoadAnalyzer.analyze(
            interfaceImports: interfaceImports.filter { scope.contains($0.key) },
            moduleTable: moduleTable,
        )

        var featureCosts: [FeatureCostAnalyzer.CostEntry]?
        if let weights = analysis.weights {
            let costs = await FeatureCostAnalyzer.costs(
                of: FeatureCostAnalyzer.featureRoots(analysis: analysis),
                graph: graph,
                weights: weights,
            )
            featureCosts = Array(costs.prefix(configuration.analysis.topLoadCount ?? 15))
        }

        return DiagnoseReport(
            roots: configuration.analysis.roots,
            costPerTarget: analysis.costPerTarget,
            parallelism: analysis.parallelism,
            workSpan: metrics,
            topInterfaceLoads: Array(loads.prefix(configuration.analysis.topLoadCount ?? 15)),
            topFeatureCosts: featureCosts,
        )
    }
}
