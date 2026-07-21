/// Metrics based on the work-span model (Graham bound: `makespan >= max(T_inf, T_1/p)`)
package struct WorkSpanMetrics: Sendable, Codable, Equatable {
    /// Number of local targets in the closure
    package let targetCount: Int
    /// Longest dependency chain length (in targets)
    package let criticalPathLength: Int
    /// Path of the longest dependency chain (from the root side)
    package let criticalPath: [String]
    /// Total work T_1 = N * c (seconds)
    package let totalWork: Double
    /// Critical path bound T_inf = D * c (seconds)
    package let criticalPathBound: Double
    /// Parallel bound T_1/p (seconds)
    package let parallelBound: Double
    /// Makespan predicted by critical-path-first list scheduling (seconds)
    package let simulatedMakespan: Double
    /// Which lower bound dominates
    package let bindingConstraint: BindingConstraint
    /// Width per depth layer (ascending depth). Used to detect parallelism-killing "necks"
    package let widthProfile: [WidthLevel]

    /// Binding-term verdict. `balanced` (at the knee) when the two terms are within 10% of each other
    package enum BindingConstraint: String, Sendable, Codable {
        /// Critical path (T_inf) dominates — reducing depth helps
        case criticalPath = "critical-path"
        /// Parallel bound (T_1/p) dominates — reducing total work or adding cores helps
        case parallelism
        /// Both terms balanced (at the knee) — improving only one side will not help
        case balanced
    }

    /// A depth layer and its width
    package struct WidthLevel: Sendable, Codable, Equatable {
        /// Depth (1 = bottom layer with no dependencies)
        package let depth: Int
        /// Number of targets in this layer
        package let width: Int
        /// Target names in this layer (sorted)
        package let targets: [String]

        /// Creates a layer from depth, width, and target names
        package init(depth: Int, width: Int, targets: [String]) {
            self.depth = depth
            self.width = width
            self.targets = targets
        }
    }
}

/// Computes work-span metrics from a `ModuleGraph`
package enum WorkSpanAnalyzer {
    /// Computes metrics for `scope` (usually the closure of the root).
    /// `costPerTarget` is the per-target planning cost in seconds; `parallelism` is the core count
    package static func analyze(
        graph: ModuleGraph,
        scope: Set<TargetID>,
        costPerTarget: Double,
        parallelism: Int,
    ) -> WorkSpanMetrics {
        let longest = graph.longestPath(within: scope)
        let totalWork = Double(scope.count) * costPerTarget
        let criticalPathBound = Double(longest.depth) * costPerTarget
        let parallelBound = totalWork / Double(parallelism)
        let makespan = simulateMakespan(
            graph: graph,
            scope: scope,
            costPerTarget: costPerTarget,
            parallelism: parallelism,
        )
        let levels = graph.depthLevels(within: scope)

        return WorkSpanMetrics(
            targetCount: scope.count,
            criticalPathLength: longest.depth,
            criticalPath: longest.path.map(\.description),
            totalWork: totalWork,
            criticalPathBound: criticalPathBound,
            parallelBound: parallelBound,
            simulatedMakespan: makespan,
            bindingConstraint: judgeBinding(
                criticalPathBound: criticalPathBound,
                parallelBound: parallelBound,
            ),
            widthProfile: levels.keys.sorted().map { depth in
                let targets = levels[depth] ?? []
                return WorkSpanMetrics.WidthLevel(
                    depth: depth,
                    width: targets.count,
                    targets: targets.map(\.targetName).sorted(),
                )
            },
        )
    }

    /// Critical-path-first (highest upward height first) list-scheduling simulation.
    /// Among targets whose dependencies have all finished, runs up to p in parallel in descending height order
    package static func simulateMakespan(
        graph: ModuleGraph,
        scope: Set<TargetID>,
        costPerTarget: Double,
        parallelism: Int,
    ) -> Double {
        guard !scope.isEmpty, parallelism > 0 else { return 0 }
        let reversed = graph.reverseEdges()
        let heights = upwardHeights(graph: graph, scope: scope, reversed: reversed)

        var pendingDependencies: [TargetID: Int] = [:]
        for target in scope {
            pendingDependencies[target] = graph.dependencies(of: target).count(where: scope.contains)
        }
        // ready: ordered low-priority-first so the last element is highest priority (height desc, then TargetID asc)
        var ready = scope.filter { pendingDependencies[$0] == 0 }
            .sorted { isLowerPriority($0, than: $1, heights: heights) }
        var running: [(finish: Double, target: TargetID)] = []
        var clock = 0.0

        while !ready.isEmpty || !running.isEmpty {
            while !ready.isEmpty, running.count < parallelism {
                let next = ready.removeLast()
                running.append((clock + costPerTarget, next))
            }
            running.sort { $0.finish > $1.finish }
            guard let finished = running.popLast() else { break }
            clock = finished.finish
            for dependent in reversed[finished.target] ?? [] where scope.contains(dependent) {
                pendingDependencies[dependent, default: 0] -= 1
                if pendingDependencies[dependent] == 0 {
                    insertSorted(&ready, dependent, heights: heights)
                }
            }
        }
        return clock
    }

    /// Upward height of each target (longest chain of targets that depend on it).
    /// Used as the list-scheduling priority (greater height = on the critical path)
    private static func upwardHeights(
        graph: ModuleGraph,
        scope: Set<TargetID>,
        reversed: [TargetID: Set<TargetID>],
    ) -> [TargetID: Int] {
        var memo: [TargetID: Int] = [:]

        func height(of node: TargetID) -> Int {
            if let cached = memo[node] {
                return cached
            }
            var best = 1
            for dependent in reversed[node] ?? [] where scope.contains(dependent) {
                best = max(best, height(of: dependent) + 1)
            }
            memo[node] = best
            return best
        }

        for node in scope {
            _ = height(of: node)
        }
        return memo
    }

    /// Inserts into `ready` (ascending height order, i.e. last element is highest priority) preserving priority order
    private static func insertSorted(
        _ ready: inout [TargetID],
        _ target: TargetID,
        heights: [TargetID: Int],
    ) {
        var low = 0
        var high = ready.count
        while low < high {
            let mid = (low + high) / 2
            if isLowerPriority(ready[mid], than: target, heights: heights) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        ready.insert(target, at: low)
    }

    /// Whether `lhs` has lower priority than `rhs` (the array keeps the highest priority at the end)
    private static func isLowerPriority(
        _ lhs: TargetID,
        than rhs: TargetID,
        heights: [TargetID: Int],
    ) -> Bool {
        let lhsHeight = heights[lhs] ?? 0
        let rhsHeight = heights[rhs] ?? 0
        if lhsHeight != rhsHeight {
            return lhsHeight < rhsHeight
        }
        // At equal heights, treat descending TargetID order as "lower priority" so the ascending side runs first
        return lhs > rhs
    }

    /// Picks the larger of T_inf and T_1/p as the binding term. balanced when within 10%
    private static func judgeBinding(
        criticalPathBound: Double,
        parallelBound: Double,
    ) -> WorkSpanMetrics.BindingConstraint {
        let larger = max(criticalPathBound, parallelBound)
        let smaller = min(criticalPathBound, parallelBound)
        guard larger > 0 else { return .balanced }
        if (larger - smaller) / larger <= 0.1 {
            return .balanced
        }
        return criticalPathBound > parallelBound ? .criticalPath : .parallelism
    }
}
