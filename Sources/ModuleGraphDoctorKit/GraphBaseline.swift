import Foundation

/// Graph baseline committed to the repository.
/// Same idea as docsync checksums: intentional regressions become visible in
/// review as a diff of the baseline update.
package struct GraphBaseline: Codable, Sendable, Equatable {
    /// Closure roots (`package/target` form)
    package let roots: [String]
    /// Per-target cost at the time of recording (seconds)
    package let costPerTarget: Double
    /// Parallelism at the time of recording
    package let parallelism: Int
    /// N: number of local targets in the closure
    package let targetCount: Int
    /// D: longest dependency chain length
    package let criticalPathLength: Int
    /// Simulated makespan (seconds)
    package let simulatedMakespan: Double
    /// Dependency edges within the closure (target -> sorted list of dependencies).
    /// Used to pinpoint the edges contributing to a regression
    package let edges: [String: [String]]
    /// Build-cost snapshot (target -> closure cost in seconds). Present only when weights are configured
    package let buildCosts: [String: Double]?

    /// Creates a baseline from its values
    package init(
        roots: [String],
        costPerTarget: Double,
        parallelism: Int,
        targetCount: Int,
        criticalPathLength: Int,
        simulatedMakespan: Double,
        edges: [String: [String]],
        buildCosts: [String: Double]? = nil,
    ) {
        self.roots = roots
        self.costPerTarget = costPerTarget
        self.parallelism = parallelism
        self.targetCount = targetCount
        self.criticalPathLength = criticalPathLength
        self.simulatedMakespan = simulatedMakespan
        self.edges = edges
        self.buildCosts = buildCosts
    }

    /// Loads from a JSON file
    package static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    /// Writes to a JSON file (sorted keys and pretty-printing keep it
    /// idempotent), creating the parent directory if needed
    package func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}
