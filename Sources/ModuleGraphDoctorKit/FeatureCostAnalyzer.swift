import Foundation

/// Computes `FeatureCost(F) = sum of w(M) for M in reach(F)`: the total measured
/// build cost a target pulls into its closure. A heavy external dependency leaking
/// into a feature closure shows up as a large jump in this number
package enum FeatureCostAnalyzer {
    /// A target and the total weight of its dependency closure
    package struct CostEntry: Sendable, Codable, Equatable {
        /// Target in `package/target` form
        package let target: String
        /// Closure cost in seconds (local targets + external products, by name)
        package let cost: Double

        /// Creates an entry
        package init(target: String, cost: Double) {
            self.target = target
            self.cost = cost
        }
    }

    /// Feature-labeled targets in the closure; falls back to the configured
    /// analysis roots when no labeler produces a `feature` label
    package static func featureRoots(analysis: GraphAnalysisSession.Analysis) -> [TargetID] {
        analysis.scope.filter { $0.targetName.hasSuffix("Feature") }.sorted()
    }

    /// Computes closure costs for the given roots. Weights are keyed by plain
    /// target/product name (build logs do not know package names).
    /// Each root's closure walk is independent, so they run in parallel on the
    /// cooperative thread pool via a task group
    package static func costs(
        of roots: [TargetID],
        graph: ModuleGraph,
        weights: TargetWeights,
    ) async -> [CostEntry] {
        await withTaskGroup(of: CostEntry.self) { group in
            for root in roots {
                group.addTask {
                    cost(of: root, graph: graph, weights: weights)
                }
            }
            var entries: [CostEntry] = []
            for await entry in group {
                entries.append(entry)
            }
            return entries.sorted { ($0.cost, $1.target) > ($1.cost, $0.target) }
        }
    }

    private static func cost(of root: TargetID, graph: ModuleGraph, weights: TargetWeights) -> CostEntry {
        let closure = graph.closure(of: root)
        var total = 0.0
        var countedExternals: Set<String> = []
        for node in closure {
            total += weights.weight(of: node.targetName)
            for external in graph.externalDependencies[node] ?? []
                where !countedExternals.contains(external)
            {
                countedExternals.insert(external)
                total += weights.weight(of: external)
            }
        }
        return CostEntry(target: root.description, cost: total)
    }
}
