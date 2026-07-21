import Foundation
import Yams

/// Model of `module-graph-doctor.yml`.
///
/// Every key is optional; the file itself is optional too. The zero-config
/// behavior scans the current directory and auto-detects roots:
///
/// ```yaml
/// root: AppFeature          # target to analyze; omit to auto-detect
/// packagePath: "."          # your root package dir (local deps discovered)
/// exclude: [VendoredLib]    # package dir names to skip
/// costPerTarget: 0.63       # measured seconds per target (default 1.0)
/// cores: 10                 # parallel workers (default: machine cores)
/// weights: .module-graph-doctor/weights.yml   # optional measured weights (default)
/// ```
package struct Configuration: Decodable, Sendable, Equatable {
    /// Where to look for packages: a single package directory, or a directory
    /// whose immediate children are packages. Relative to the config file.
    /// Defaults to ["."]
    package let packagePath: [String]
    /// Package directory names to exclude. Scipio-style binary wrapper packages
    /// re-export prebuilt SDKs as local products and vendored code is never
    /// source-built; including either silently inflates the closure
    package let exclude: [String]
    /// Targets to analyze. Accepts a bare target name (`AppFeature`) or
    /// `<package>/<target>` when the name is ambiguous. Empty means auto-detect:
    /// every non-test target that nothing else depends on
    package let root: [String]
    /// Per-target cost in seconds. Defaults to 1.0 (a relative unit)
    package let costPerTarget: Double?
    /// Parallel workers (core count). Defaults to the executing machine's cores
    package let cores: Int?
    /// Number of rows in the load / cost rankings. Defaults to 15
    package let topCount: Int?
    /// Baseline gate settings (optional; defaults apply when omitted)
    package let check: Check?
    /// Target weights file path (YAML, target name -> seconds). Optional
    package let weights: String?

    enum CodingKeys: String, CodingKey {
        case packagePath
        case exclude
        case root
        case costPerTarget
        case cores
        case topCount
        case check
        case weights
    }

    /// Decodes the flat schema; `path` and `root` accept a string or a list
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packagePath = try Self.stringOrList(container, .packagePath) ?? ["."]
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
        root = try Self.stringOrList(container, .root) ?? []
        costPerTarget = try container.decodeIfPresent(Double.self, forKey: .costPerTarget)
        cores = try container.decodeIfPresent(Int.self, forKey: .cores)
        topCount = try container.decodeIfPresent(Int.self, forKey: .topCount)
        check = try container.decodeIfPresent(Check.self, forKey: .check)
        weights = try container.decodeIfPresent(String.self, forKey: .weights)
    }

    private static func stringOrList(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
    ) throws -> [String]? {
        if let single = try? container.decodeIfPresent(String.self, forKey: key) {
            return [single]
        }
        return try container.decodeIfPresent([String].self, forKey: key)
    }

    /// Baseline gate settings
    package struct Check: Decodable, Sendable, Equatable {
        /// Baseline file path (relative to the config file, or absolute).
        /// Defaults to .module-graph-doctor/graph-baseline.json
        package let baseline: String?
        /// Makespan regression (percent of baseline) at or above which check warns. Defaults to 5
        package let makespanWarnPercent: Double?
        /// Makespan regression (percent of baseline) at or above which check errors. Defaults to 10
        package let makespanErrorPercent: Double?
        /// Build-cost regression (percent of baseline) at or above which check warns. Defaults to 10
        package let buildCostWarnPercent: Double?
        /// Build-cost regression (percent of baseline) at or above which check errors. Defaults to 25
        package let buildCostErrorPercent: Double?

        /// Builds directly, for tests
        package init(
            baseline: String? = nil,
            makespanWarnPercent: Double? = nil,
            makespanErrorPercent: Double? = nil,
            buildCostWarnPercent: Double? = nil,
            buildCostErrorPercent: Double? = nil,
        ) {
            self.baseline = baseline
            self.makespanWarnPercent = makespanWarnPercent
            self.makespanErrorPercent = makespanErrorPercent
            self.buildCostWarnPercent = buildCostWarnPercent
            self.buildCostErrorPercent = buildCostErrorPercent
        }
    }

    /// Builds directly, for tests and for the zero-config default
    package init(
        packagePath: [String] = ["."],
        exclude: [String] = [],
        root: [String] = [],
        costPerTarget: Double? = nil,
        cores: Int? = nil,
        topCount: Int? = nil,
        check: Check? = nil,
        weights: String? = nil,
    ) {
        self.packagePath = packagePath
        self.exclude = exclude
        self.root = root
        self.costPerTarget = costPerTarget
        self.cores = cores
        self.topCount = topCount
        self.check = check
        self.weights = weights
    }

    /// Decodes from a YAML string
    package static func decode(yaml: String) throws -> Self {
        try YAMLDecoder().decode(Self.self, from: yaml)
    }

    /// Loads the configuration file
    package static func load(from url: URL) throws -> Self {
        try decode(yaml: String(contentsOf: url, encoding: .utf8))
    }

    /// Loads the config file when it exists; otherwise returns the zero-config
    /// default (scan the current directory, auto-detect roots)
    package static func loadOrDefault(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return Configuration()
        }
        return try load(from: url)
    }
}
