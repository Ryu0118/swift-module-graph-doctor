import Foundation

/// Output formatting for `DiagnoseReport`
package enum DiagnoseReportRenderer {
    /// Human-readable text format
    package static func text(_ report: DiagnoseReport) -> String {
        var lines: [String] = []
        let workSpan = report.workSpan
        lines.append("Module Graph Diagnosis")
        lines.append("  roots: \(report.roots.joined(separator: ", "))")
        lines.append("  c=\(format(report.costPerTarget))s/target, p=\(report.parallelism)")
        lines.append("")
        lines.append("Work-span metrics (makespan >= max(T_inf, T_1/p))")
        lines.append("  N  (targets in closure)   = \(workSpan.targetCount)")
        lines.append("  D  (critical path length) = \(workSpan.criticalPathLength)")
        lines.append("  T_1   = \(format(workSpan.totalWork))s")
        lines.append("  T_inf = \(format(workSpan.criticalPathBound))s")
        lines.append("  T_1/p = \(format(workSpan.parallelBound))s")
        lines.append("  makespan^ (simulated)      = \(format(workSpan.simulatedMakespan))s")
        lines.append("  binding constraint         = \(bindingDescription(workSpan.bindingConstraint))")
        lines.append("")
        lines.append("Critical path:")
        lines.append("  " + workSpan.criticalPath.joined(separator: " -> "))
        lines.append("")
        lines.append("Width profile (narrow layers kill parallelism):")
        for level in workSpan.widthProfile {
            let sample = level.targets.prefix(5).joined(separator: ", ")
            let ellipsis = level.targets.count > 5 ? ", …" : ""
            lines.append(String(
                format: "  depth %2d: width %3d  %@%@",
                level.depth,
                level.width,
                sample,
                ellipsis,
            ))
        }
        if let costs = report.topFeatureCosts, !costs.isEmpty {
            lines.append("")
            lines.append("Top feature cost (measured build seconds pulled into the closure):")
            for entry in costs {
                lines.append(String(format: "  %8.1fs  %@", entry.cost, entry.target))
            }
        }
        if !report.topInterfaceLoads.isEmpty {
            lines.append("")
            lines.append("Top interface load (public-import transitive closure size):")
            for entry in report.topInterfaceLoads {
                lines.append(String(format: "  %4d  %@", entry.load, entry.target))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Machine-readable JSON format (sorted keys, pretty-printed)
    package static func json(_ report: DiagnoseReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func bindingDescription(_ binding: WorkSpanMetrics.BindingConstraint) -> String {
        switch binding {
        case .criticalPath:
            "critical path (T_inf) — reduce dependency chain depth"
        case .parallelism:
            "parallelism (T_1/p) — reduce total work or add cores"
        case .balanced:
            "balanced (knee) — neither depth nor width alone will help"
        }
    }
}
