import Foundation
import Yams

/// Model of `module-graph-doctor.yml`.
///
/// ```yaml
/// packages:
///   roots: ["MyPackages"]
///   exclude: ["BinaryWrappers", "VendoredLib"]
/// analysis:
///   roots: ["MyApp/AppFeature"]
///   costPerTarget: 0.629
///   parallelism: 10
///   topLoadCount: 15
/// ```
package struct Configuration: Decodable, Sendable, Equatable {
    /// Package scanning settings
    package let packages: Packages
    /// Analysis parameters
    package let analysis: Analysis
    /// Baseline gate settings (optional; defaults apply when omitted)
    package let check: Check?

    /// Package scanning settings
    package struct Packages: Decodable, Sendable, Equatable {
        /// Scan roots (relative to the config file, or absolute paths)
        package let roots: [String]
        /// Package directory names to exclude (Scipio-style binary wrapper packages
        /// re-export external SDKs as local products; including them or vendor code
        /// pollutes the closure with targets that are never source-built, so the
        /// closure size gets silently inflated by prebuilt wrapper targets)
        package let exclude: [String]?

        /// Builds directly, for tests
        package init(roots: [String], exclude: [String]? = nil) {
            self.roots = roots
            self.exclude = exclude
        }
    }

    /// Analysis parameters
    package struct Analysis: Decodable, Sendable, Equatable {
        /// Closure roots (`<package>/<target>` form)
        package let roots: [String]
        /// Per-target cost in seconds. Defaults to 1.0 (interpreted as a relative value)
        package let costPerTarget: Double?
        /// Parallelism (core count). Defaults to the executing machine's core count
        package let parallelism: Int?
        /// Number of entries shown in the Load ranking. Defaults to 15
        package let topLoadCount: Int?

        /// Builds directly, for tests
        package init(
            roots: [String],
            costPerTarget: Double? = nil,
            parallelism: Int? = nil,
            topLoadCount: Int? = nil,
        ) {
            self.roots = roots
            self.costPerTarget = costPerTarget
            self.parallelism = parallelism
            self.topLoadCount = topLoadCount
        }
    }

    /// Baseline gate settings
    package struct Check: Decodable, Sendable, Equatable {
        /// Baseline file path (relative to the config file, or absolute). Defaults to graph-baseline.json
        package let baseline: String?
        /// Makespan regression (seconds) at or above which check warns. Defaults to 0.5
        package let makespanWarnSeconds: Double?
        /// Makespan regression (seconds) at or above which check errors. Defaults to 1.0
        package let makespanErrorSeconds: Double?

        /// Builds directly, for tests
        package init(
            baseline: String? = nil,
            makespanWarnSeconds: Double? = nil,
            makespanErrorSeconds: Double? = nil,
        ) {
            self.baseline = baseline
            self.makespanWarnSeconds = makespanWarnSeconds
            self.makespanErrorSeconds = makespanErrorSeconds
        }
    }

    /// Builds directly, for tests
    package init(packages: Packages, analysis: Analysis, check: Check? = nil) {
        self.packages = packages
        self.analysis = analysis
        self.check = check
    }

    /// Decodes from a YAML string
    package static func decode(yaml: String) throws -> Self {
        try YAMLDecoder().decode(Self.self, from: yaml)
    }

    /// Loads the configuration file
    package static func load(from url: URL) throws -> Self {
        try decode(yaml: String(contentsOf: url, encoding: .utf8))
    }
}

package extension Configuration {
    /// Parses a `<package>/<target>` string into a `TargetID`. Returns nil for malformed input
    static func parseTargetID(_ raw: String) -> TargetID? {
        let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return TargetID(packageName: parts[0], targetName: parts[1])
    }
}
