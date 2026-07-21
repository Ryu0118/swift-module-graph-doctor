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

    /// Creates metrics from precomputed values (also used to build fixtures in downstream tests)
    package init(
        targetCount: Int,
        criticalPathLength: Int,
        criticalPath: [String],
        totalWork: Double,
        criticalPathBound: Double,
        parallelBound: Double,
        simulatedMakespan: Double,
        bindingConstraint: BindingConstraint,
        widthProfile: [WidthLevel],
    ) {
        self.targetCount = targetCount
        self.criticalPathLength = criticalPathLength
        self.criticalPath = criticalPath
        self.totalWork = totalWork
        self.criticalPathBound = criticalPathBound
        self.parallelBound = parallelBound
        self.simulatedMakespan = simulatedMakespan
        self.bindingConstraint = bindingConstraint
        self.widthProfile = widthProfile
    }

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
