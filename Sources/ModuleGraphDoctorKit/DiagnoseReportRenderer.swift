import Foundation
import ModuleGraphKit

/// Renders a `DiagnoseReport` for humans (text) or machines (JSON).
///
/// The text format is deliberately self-explanatory: every metric is printed
/// with its unit, its formula, and a one-line meaning, and the verdict section
/// spells out what would (and would not) make the build faster. Nobody should
/// need this source file to interpret the output.
package enum DiagnoseReportRenderer {
    /// Human-readable text report
    package static func text(_ report: DiagnoseReport) -> String {
        var sections: [String] = []
        sections.append(header(report))
        sections.append(metrics(report))
        sections.append(verdict(report.workSpan))
        sections.append(criticalPath(report.workSpan))
        sections.append(widthProfile(report))
        if let costs = report.topBuildCosts, !costs.isEmpty {
            sections.append(buildCosts(costs))
        }
        if !report.topInterfaceLoads.isEmpty {
            sections.append(interfaceLoads(report.topInterfaceLoads))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Machine-readable JSON (sorted keys, pretty-printed)
    package static func json(_ report: DiagnoseReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    private static func header(_ report: DiagnoseReport) -> String {
        var hint = ""
        if report.rootsAutoDetected, report.roots.count > 1 {
            hint = """


            note: \(report.roots.count) roots were auto-detected (targets nothing else
            depends on) and the metrics below cover their union. If some of these
            look like dead or unwired modules, that is a finding in itself; to focus
            on one app, set `root:` in module-graph-doctor.yml.
            """
        }
        return """
        Module graph diagnosis
        ======================
        analyzed roots : \(report.roots.joined(separator: ", "))\(hint)
        assumptions    : c = \(seconds(report.costPerTarget)) build cost per target, \
        p = \(report.parallelism) parallel workers

        Model: a build can never finish faster than max(T_inf, T_1/p)
        (work-span model, a.k.a. Graham bound). The two lower bounds are
        explained below; whichever is larger is the real bottleneck.
        """
    }

    private static func metrics(_ report: DiagnoseReport) -> String {
        let workSpan = report.workSpan
        let rows: [(String, String, String)] = [
            ("N", "\(workSpan.targetCount) targets",
             "size of the dependency closure (everything the roots pull in)"),
            ("D", "\(workSpan.criticalPathLength) targets",
             "longest dependency chain; these can only build one after another"),
            ("T_1 = N x c", seconds(workSpan.totalWork),
             "total work if everything built on a single worker"),
            ("T_inf = D x c", seconds(workSpan.criticalPathBound),
             "depth bound: even infinite workers cannot beat the serial chain"),
            ("T_1/p", seconds(workSpan.parallelBound),
             "width bound: \(report.parallelism) workers cannot beat total work / p"),
            ("makespan^", seconds(workSpan.simulatedMakespan),
             "simulated build time with an ideal scheduler on p workers"),
        ]
        return rows.map { name, value, meaning in
            name.padding(toLength: 14, withPad: " ", startingAt: 0)
                + value.padding(toLength: 14, withPad: " ", startingAt: 0)
                + meaning
        }
        .joined(separator: "\n")
    }

    private static func verdict(_ workSpan: WorkSpanMetrics) -> String {
        switch workSpan.bindingConstraint {
        case .criticalPath:
            """
            Verdict: DEPTH-BOUND (T_inf > T_1/p)
              The serial dependency chain is the bottleneck. Flattening the graph
              (shortening the critical path below) will speed the build up;
              adding workers or shrinking unrelated targets will not.
            """
        case .parallelism:
            """
            Verdict: WIDTH-BOUND (T_1/p > T_inf)
              Total work divided by workers is the bottleneck. Reducing the number
              of targets, cheapening the per-target cost, or adding workers will
              speed the build up; shortening the dependency chain alone will not.
            """
        case .balanced:
            """
            Verdict: BALANCED -- at the knee (the two bounds are within 10%)
              Neither flattening the dependency chain alone nor adding workers
              alone will make this build meaningfully faster: as soon as one bound
              drops, the other becomes the bottleneck. Only changes that lower
              both (fewer targets, cheaper per-target cost) still pay off.
            """
        }
    }

    private static func criticalPath(_ workSpan: WorkSpanMetrics) -> String {
        """
        Critical path (the D-target serial chain; shorten it by removing or
        rerouting any edge in this chain):
          \(workSpan.criticalPath.joined(separator: "\n    -> "))
        """
    }

    private static func widthProfile(_ report: DiagnoseReport) -> String {
        var lines: [String] = []
        lines.append("Width profile (targets per dependency depth; a layer narrower than")
        lines.append("p = \(report.parallelism) leaves workers idle while the build passes through it):")
        for level in report.workSpan.widthProfile {
            let sample = level.targets.prefix(4).joined(separator: ", ")
            let ellipsis = level.targets.count > 4 ? ", ..." : ""
            let neck = level.width < report.parallelism ? "  <- narrow" : ""
            lines.append(String(
                format: "  depth %2d | width %3d%@  %@%@",
                level.depth,
                level.width,
                neck,
                sample,
                ellipsis,
            ))
        }
        return lines.joined(separator: "\n")
    }

    private static func buildCosts(_ costs: [BuildCostAnalyzer.CostEntry]) -> String {
        var lines: [String] = []
        lines.append("Build cost (what building each target from scratch costs, dependencies")
        lines.append("included, in measured compile seconds -- e.g. its standalone test suite):")
        for entry in costs {
            lines.append(String(format: "  %8.1fs  %@", entry.cost, entry.target))
        }
        return lines.joined(separator: "\n")
    }

    private static func interfaceLoads(_ loads: [InterfaceLoadAnalyzer.LoadEntry]) -> String {
        var lines: [String] = []
        lines.append("Interface load (modules transitively re-exposed through public imports;")
        lines.append("compiling anything that imports these loads this many extra modules):")
        for entry in loads {
            lines.append(String(format: "  %4d modules  %@", entry.load, entry.target))
        }
        return lines.joined(separator: "\n")
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }
}
