import Foundation
import Yams

/// Per-target build cost weights (seconds), measured from real build logs.
///
/// Weights turn "this module feels heavy" into a number: they are generated from
/// an XCLogParser JSON report by summing the durations of `Compile *` sub-steps
/// per target. Note that per-target compile-time sums are parallel task time,
/// not wall clock -- never compare them against wall-clock makespan directly.
/// The "Build target X" step duration itself is NOT used because it includes
/// time spent waiting for other targets in a parallel build.
package struct TargetWeights: Sendable, Equatable {
    /// Target name -> summed compile duration in seconds
    package let seconds: [String: Double]

    /// Creates weights from a name -> seconds map
    package init(seconds: [String: Double]) {
        self.seconds = seconds
    }

    /// Weight of a target (0 when unmeasured)
    package func weight(of targetName: String) -> Double {
        seconds[targetName] ?? 0
    }

    /// Loads weights from a YAML file (target name -> seconds)
    package static func load(from url: URL) throws -> Self {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try Self(seconds: YAMLDecoder().decode([String: Double].self, from: yaml))
    }

    /// Writes weights sorted by name so the file is diff-stable
    package func save(to url: URL) throws {
        var lines: [String] = []
        for (name, value) in seconds.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(String(format: "%.3f", value))")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
