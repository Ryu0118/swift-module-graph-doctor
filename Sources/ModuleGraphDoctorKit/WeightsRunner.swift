import Foundation

/// Generates the target-weights file from an XCLogParser JSON report and
/// writes it to the configured (or overridden) output path.
///
/// Owns the path resolution and file IO so the CLI command stays a thin
/// argument mapper
package struct WeightsRunner {
    /// What was written, for the CLI to report
    package struct Output: Equatable, Sendable {
        /// Where the weights file was written
        package let url: URL
        /// Number of targets with a measured weight
        package let targetCount: Int
    }

    /// Creates a runner
    package init() {}

    /// Parses `logData` (XCLogParser `--reporter json` output) and writes the
    /// weights file. `outputOverride` wins over the configured path, which
    /// wins over the default `.module-graph-doctor/weights.yml`
    package func run(
        configuration: Configuration,
        baseDirectory: URL,
        logData: Data,
        outputOverride: String?,
    ) throws -> Output {
        let weights = try WeightsGenerator.generate(fromXCLogParserJSON: logData)
        let raw = outputOverride ?? configuration.weights ?? ".module-graph-doctor/weights.yml"
        let url = raw.hasPrefix("/") ? URL(filePath: raw) : baseDirectory.appendingPathComponent(raw)
        try weights.save(to: url)
        return Output(url: url, targetCount: weights.seconds.count)
    }
}
