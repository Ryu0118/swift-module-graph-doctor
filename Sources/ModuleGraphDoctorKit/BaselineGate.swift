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

    /// Thresholds for simulated-makespan regression (seconds)
    package struct Thresholds: Sendable, Equatable {
        /// Regression at or above this value warns
        package let makespanWarnSeconds: Double
        /// Regression at or above this value errors
        package let makespanErrorSeconds: Double
        /// FeatureCost regression (seconds) at or above this value warns
        package let featureCostWarnSeconds: Double
        /// FeatureCost regression (seconds) at or above this value errors
        package let featureCostErrorSeconds: Double

        /// Creates thresholds (defaults: makespan warn 0.5s / error 1.0s, featureCost warn 10s / error 30s)
        package init(
            makespanWarnSeconds: Double = 0.5,
            makespanErrorSeconds: Double = 1.0,
            featureCostWarnSeconds: Double = 10,
            featureCostErrorSeconds: Double = 30,
        ) {
            self.makespanWarnSeconds = makespanWarnSeconds
            self.makespanErrorSeconds = makespanErrorSeconds
            self.featureCostWarnSeconds = featureCostWarnSeconds
            self.featureCostErrorSeconds = featureCostErrorSeconds
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
        findings.append(contentsOf: evaluateFeatureCosts(
            baseline: baseline.featureCosts,
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
        let delta = current.simulatedMakespan - baseline.simulatedMakespan
        let formatted = String(format: "%+.2f", delta)
        let message = "simulated makespan changed by \(formatted)s "
            + "(\(baseline.simulatedMakespan) -> \(current.simulatedMakespan))"
        if delta >= thresholds.makespanErrorSeconds {
            return [Finding(severity: .error, message: message)]
        }
        if delta >= thresholds.makespanWarnSeconds {
            return [Finding(severity: .warning, message: message)]
        }
        return []
    }

    /// Compares per-target closure costs; only regressions at or above the thresholds are reported
    private static func evaluateFeatureCosts(
        baseline: [String: Double]?,
        current: [String: Double]?,
        thresholds: Thresholds,
    ) -> [Finding] {
        guard let baseline, let current else { return [] }
        var findings: [Finding] = []
        for (target, cost) in current.sorted(by: { $0.key < $1.key }) {
            guard let previous = baseline[target] else { continue }
            let delta = cost - previous
            guard delta >= thresholds.featureCostWarnSeconds else { continue }
            let message = "feature cost of \(target) changed by "
                + String(format: "%+.1f", delta)
                + "s (\(String(format: "%.1f", previous)) -> \(String(format: "%.1f", cost)))"
            findings.append(Finding(
                severity: delta >= thresholds.featureCostErrorSeconds ? .error : .warning,
                message: message,
            ))
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
