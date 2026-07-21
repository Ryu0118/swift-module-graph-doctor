import ModuleGraphKit

/// Compares the baseline against current values (pure logic).
///
/// The core of the gate is the simulated-makespan regression threshold. Adding
/// a neck (a narrow serial layer) or lengthening the critical path always shows
/// up as an increase in the simulated makespan, so the width profile itself is
/// not gated; everything is unified into the makespan check.
package enum BaselineGate {
    /// Severity of a finding
    package enum Severity: String, Sendable, Codable, Comparable {
        /// Informational only
        case info
        /// Warning (does not affect the exit code)
        case warning
        /// Error (non-zero exit code)
        case error

        private var rank: Int {
            switch self {
            case .info: 0
            case .warning: 1
            case .error: 2
            }
        }

        /// Severity ordering
        package static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    /// An individual finding
    package struct Finding: Sendable, Equatable {
        /// Severity
        package let severity: Severity
        /// Human-readable message
        package let message: String

        /// Creates a finding from a severity and message
        package init(severity: Severity, message: String) {
            self.severity = severity
            self.message = message
        }
    }

    /// Regression thresholds, expressed as percentages relative to the baseline.
    ///
    /// Relative thresholds are scale-invariant: re-measuring `weights.yml` or
    /// `costPerTarget` on a faster or slower machine rescales every number by
    /// the same factor, so percentage-based gates stay calibrated while
    /// absolute-seconds gates would all fire (or all go blind). Tiny baselines
    /// would make percentages noisy, so a small absolute noise floor applies
    /// on top: a regression must clear both the percentage and the floor
    package struct Thresholds: Sendable, Equatable {
        /// Makespan regression (percent of the baseline) at or above which check warns
        package let makespanWarnPercent: Double
        /// Makespan regression (percent of the baseline) at or above which check errors
        package let makespanErrorPercent: Double
        /// Build-cost regression (percent of the baseline) at or above which check warns
        package let buildCostWarnPercent: Double
        /// Build-cost regression (percent of the baseline) at or above which check errors
        package let buildCostErrorPercent: Double

        /// Noise floor for makespan deltas (in the same unit as the makespan)
        static let makespanFloor = 0.2
        /// Noise floor for build-cost deltas (in the same unit as the weights)
        static let buildCostFloor = 2.0

        /// Creates thresholds (defaults: makespan warn 5% / error 10%,
        /// build cost warn 10% / error 25%)
        package init(
            makespanWarnPercent: Double = 5,
            makespanErrorPercent: Double = 10,
            buildCostWarnPercent: Double = 10,
            buildCostErrorPercent: Double = 25,
        ) {
            self.makespanWarnPercent = makespanWarnPercent
            self.makespanErrorPercent = makespanErrorPercent
            self.buildCostWarnPercent = buildCostWarnPercent
            self.buildCostErrorPercent = buildCostErrorPercent
        }
    }

    /// Compares the baseline against the current metrics and edge set
    package static func evaluate(
        baseline: GraphBaseline,
        current: WorkSpanMetrics,
        currentEdges: [String: [String]],
        currentFeatureCosts: [String: Double]? = nil,
        thresholds: Thresholds = Thresholds(),
    ) -> [Finding] {
        var findings: [Finding] = []
        findings.append(contentsOf: evaluateMakespan(baseline: baseline, current: current, thresholds: thresholds))
        findings.append(contentsOf: evaluateBuildCosts(
            baseline: baseline.buildCosts,
            current: currentFeatureCosts,
            thresholds: thresholds,
        ))

        if current.criticalPathLength > baseline.criticalPathLength {
            findings.append(Finding(
                severity: .warning,
                message: "critical path length increased: "
                    + "\(baseline.criticalPathLength) -> \(current.criticalPathLength)",
            ))
        }
        if current.targetCount != baseline.targetCount {
            findings.append(Finding(
                severity: .info,
                message: "target count changed: \(baseline.targetCount) -> \(current.targetCount)",
            ))
        }
        findings.append(contentsOf: edgeDiff(baseline: baseline.edges, current: currentEdges))
        return findings
    }

    private static func evaluateMakespan(
        baseline: GraphBaseline,
        current: WorkSpanMetrics,
        thresholds: Thresholds,
    ) -> [Finding] {
        guard let finding = regression(
            name: "simulated makespan",
            baseline: baseline.simulatedMakespan,
            current: current.simulatedMakespan,
            gate: Gate(
                warnPercent: thresholds.makespanWarnPercent,
                errorPercent: thresholds.makespanErrorPercent,
                floor: Thresholds.makespanFloor,
            ),
        ) else { return [] }
        return [finding]
    }

    /// Warn/error percentages plus the absolute noise floor for one metric
    private struct Gate {
        let warnPercent: Double
        let errorPercent: Double
        let floor: Double
    }

    /// Percentage-based regression judgement with an absolute noise floor
    private static func regression(
        name: String,
        baseline: Double,
        current: Double,
        gate: Gate,
    ) -> Finding? {
        let delta = current - baseline
        guard baseline > 0, delta >= gate.floor else { return nil }
        let percent = delta / baseline * 100
        guard percent >= gate.warnPercent else { return nil }
        let message = "\(name) regressed by "
            + String(format: "%+.1f%% (%.1f -> %.1f)", percent, baseline, current)
        return Finding(
            severity: percent >= gate.errorPercent ? .error : .warning,
            message: message,
        )
    }

    /// Compares per-target closure costs; only regressions at or above the thresholds are reported
    private static func evaluateBuildCosts(
        baseline: [String: Double]?,
        current: [String: Double]?,
        thresholds: Thresholds,
    ) -> [Finding] {
        guard let baseline, let current else { return [] }
        var findings: [Finding] = []
        for (target, cost) in current.sorted(by: { $0.key < $1.key }) {
            guard let previous = baseline[target] else { continue }
            if let finding = regression(
                name: "build cost of \(target)",
                baseline: previous,
                current: cost,
                gate: Gate(
                    warnPercent: thresholds.buildCostWarnPercent,
                    errorPercent: thresholds.buildCostErrorPercent,
                    floor: Thresholds.buildCostFloor,
                ),
            ) {
                findings.append(finding)
            }
        }
        return findings
    }

    /// Lists new edges (candidate contributors to regressions) and removed edges as info
    private static func edgeDiff(
        baseline: [String: [String]],
        current: [String: [String]],
    ) -> [Finding] {
        var findings: [Finding] = []
        for (source, targets) in current.sorted(by: { $0.key < $1.key }) {
            let added = Set(targets).subtracting(baseline[source] ?? [])
            for target in added.sorted() {
                findings.append(Finding(severity: .info, message: "new edge: \(source) -> \(target)"))
            }
        }
        for (source, targets) in baseline.sorted(by: { $0.key < $1.key }) {
            let removed = Set(targets).subtracting(current[source] ?? [])
            for target in removed.sorted() {
                findings.append(Finding(severity: .info, message: "removed edge: \(source) -> \(target)"))
            }
        }
        return findings
    }
}
