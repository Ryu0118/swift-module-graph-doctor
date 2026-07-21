import Foundation

/// Aggregates target weights from an XCLogParser `--reporter json` build report
package enum WeightsGenerator {
    /// Minimal decodable slice of XCLogParser's BuildStep tree
    package struct BuildStep: Decodable, Sendable {
        /// Step title (e.g. `Build target Foo`, `Compile Foo.swift`)
        package let title: String
        /// Step type (`main` / `target` / `detail`)
        package let type: String
        /// Step duration in seconds
        package let duration: Double?
        /// Nested steps
        package let subSteps: [BuildStep]?

        /// Builds directly, for tests
        package init(title: String, type: String, duration: Double?, subSteps: [BuildStep]?) {
            self.title = title
            self.type = type
            self.duration = duration
            self.subSteps = subSteps
        }
    }

    /// Parses the JSON report and sums `Compile *` detail durations per target.
    /// Target step titles look like `Build target Foo`; the prefix is stripped
    package static func generate(fromXCLogParserJSON data: Data) throws -> TargetWeights {
        let root = try JSONDecoder().decode(BuildStep.self, from: data)
        var seconds: [String: Double] = [:]
        collect(step: root, into: &seconds)
        return TargetWeights(seconds: seconds)
    }

    private static func collect(step: BuildStep, into seconds: inout [String: Double]) {
        if step.type == "target" {
            let name = step.title.hasPrefix("Build target ")
                ? String(step.title.dropFirst("Build target ".count))
                : step.title
            let compileTotal = compileDuration(of: step)
            if compileTotal > 0 {
                seconds[name, default: 0] += compileTotal
            }
            return
        }
        for sub in step.subSteps ?? [] {
            collect(step: sub, into: &seconds)
        }
    }

    /// Sums every `Compile *` step nested under a target step
    private static func compileDuration(of step: BuildStep) -> Double {
        var total = 0.0
        for sub in step.subSteps ?? [] {
            if sub.title.hasPrefix("Compile ") {
                total += sub.duration ?? 0
            }
            total += compileDuration(of: sub)
        }
        return total
    }
}
