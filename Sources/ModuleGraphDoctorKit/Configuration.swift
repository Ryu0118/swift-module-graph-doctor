import Foundation
import Yams

/// Model of `module-graph-doctor.yml`.
///
/// Every key is optional; the file itself is optional too. The zero-config
/// behavior scans the current directory and auto-detects roots:
///
/// ```yaml
/// root: AppFeature          # target to analyze; omit to auto-detect
/// path: "."                 # a package dir, or a dir containing packages
/// exclude: [VendoredLib]    # package dir names to skip
/// costPerTarget: 0.63       # measured seconds per target (default 1.0)
/// cores: 10                 # parallel workers (default: machine cores)
/// weights: weights.yml      # optional measured weights
/// ```
package struct Configuration: Decodable, Sendable, Equatable {
    /// Where to look for packages: a single package directory, or a directory
    /// whose immediate children are packages. Relative to the config file.
    /// Defaults to ["."]
    package let path: [String]
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
    /// Layer definitions: layer name -> membership spec (optional)
    package let layers: [String: LayerSpec]?
    /// Lint rules over the layers (optional)
    package let lint: [LintRule]?
    /// Target weights file path (YAML, target name -> seconds). Optional
    package let weights: String?

    enum CodingKeys: String, CodingKey {
        case path
        case exclude
        case root
        case costPerTarget
        case cores
        case topCount
        case check
        case layers
        case lint
        case weights
    }

    /// Decodes the flat schema; `path` and `root` accept a string or a list
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try Self.stringOrList(container, .path) ?? ["."]
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
        root = try Self.stringOrList(container, .root) ?? []
        costPerTarget = try container.decodeIfPresent(Double.self, forKey: .costPerTarget)
        cores = try container.decodeIfPresent(Int.self, forKey: .cores)
        topCount = try container.decodeIfPresent(Int.self, forKey: .topCount)
        check = try container.decodeIfPresent(Check.self, forKey: .check)
        layers = try container.decodeIfPresent([String: LayerSpec].self, forKey: .layers)
        lint = try container.decodeIfPresent([LintRule].self, forKey: .lint)
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

    /// How a layer's members are declared: a regex on the target name,
    /// an exact name list (which also matches external products), or a
    /// measured-weight threshold in seconds
    package enum LayerSpec: Decodable, Sendable, Equatable {
        /// Regex matched against the target name
        case regex(String)
        /// Exact target names; also matches external product names
        case names([String])
        /// Every target whose measured weight is at least this many seconds
        case weightAtLeast(Double)

        /// Decodes from a string (regex), list (names), or number (seconds)
        package init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let names = try? container.decode([String].self) {
                self = .names(names)
            } else if let seconds = try? container.decode(Double.self) {
                self = .weightAtLeast(seconds)
            } else {
                self = try .regex(container.decode(String.self))
            }
        }
    }

    /// A lint rule. `deny` uses a tiny DSL over layer names:
    /// `A -> B` forbids direct edges, `A => B` forbids transitive reachability,
    /// and `* => B` with `allow:` restricts who may depend on B at all
    package struct LintRule: Decodable, Sendable, Equatable {
        /// The denied relation, e.g. `feature -> live` or `interface => sdk`
        package let deny: String
        /// Layers still allowed to depend on the target of a `* => B` rule
        package let allow: [String]?

        /// Builds directly, for tests
        package init(deny: String, allow: [String]? = nil) {
            self.deny = deny
            self.allow = allow
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
        /// Violations baseline file path. Defaults to violations-baseline.yml
        package let violationsBaseline: String?
        /// FeatureCost regression (seconds) at or above which check warns. Defaults to 10
        package let buildCostWarnSeconds: Double?
        /// FeatureCost regression (seconds) at or above which check errors. Defaults to 30
        package let buildCostErrorSeconds: Double?

        /// Builds directly, for tests
        package init(
            baseline: String? = nil,
            makespanWarnSeconds: Double? = nil,
            makespanErrorSeconds: Double? = nil,
            violationsBaseline: String? = nil,
            buildCostWarnSeconds: Double? = nil,
            buildCostErrorSeconds: Double? = nil,
        ) {
            self.baseline = baseline
            self.makespanWarnSeconds = makespanWarnSeconds
            self.makespanErrorSeconds = makespanErrorSeconds
            self.violationsBaseline = violationsBaseline
            self.buildCostWarnSeconds = buildCostWarnSeconds
            self.buildCostErrorSeconds = buildCostErrorSeconds
        }
    }

    /// Builds directly, for tests and for the zero-config default
    package init(
        path: [String] = ["."],
        exclude: [String] = [],
        root: [String] = [],
        costPerTarget: Double? = nil,
        cores: Int? = nil,
        topCount: Int? = nil,
        check: Check? = nil,
        layers: [String: LayerSpec]? = nil,
        lint: [LintRule]? = nil,
        weights: String? = nil,
    ) {
        self.path = path
        self.exclude = exclude
        self.root = root
        self.costPerTarget = costPerTarget
        self.cores = cores
        self.topCount = topCount
        self.check = check
        self.layers = layers
        self.lint = lint
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
