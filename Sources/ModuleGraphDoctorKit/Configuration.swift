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
    /// Target labeling settings for architecture invariants (optional)
    package let labels: Labels?
    /// Architecture invariant rules (optional)
    package let invariants: [InvariantSpec]?
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
        case labels
        case invariants
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
        labels = try container.decodeIfPresent(Labels.self, forKey: .labels)
        invariants = try container.decodeIfPresent([InvariantSpec].self, forKey: .invariants)
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

    /// Target labeling settings. Resolution order: explicit -> regex rules (declaration order)
    package struct Labels: Decodable, Sendable, Equatable {
        /// Explicit target-name (or `package/target`) to label mapping
        package let explicit: [String: String]?
        /// Regex rules matched against the target name, evaluated in order
        package let rules: [Rule]?
        /// External product names labeled as SDKs (for `forbid-reach: ... -> sdk`)
        package let sdk: [String]?
        /// Auto-label targets whose measured weight is at or above this many seconds as `heavy`
        package let heavyThresholdSeconds: Double?

        /// A regex labeling rule
        package struct Rule: Decodable, Sendable, Equatable {
            /// Regular expression matched against the target name
            package let pattern: String
            /// Label assigned on match
            package let label: String

            /// Builds directly, for tests
            package init(pattern: String, label: String) {
                self.pattern = pattern
                self.label = label
            }
        }

        /// Builds directly, for tests
        package init(
            explicit: [String: String]? = nil,
            rules: [Rule]? = nil,
            sdk: [String]? = nil,
            heavyThresholdSeconds: Double? = nil,
        ) {
            self.explicit = explicit
            self.rules = rules
            self.sdk = sdk
            self.heavyThresholdSeconds = heavyThresholdSeconds
        }
    }

    /// Declarative invariant rule. Exactly one of the three rule bodies must be present
    package struct InvariantSpec: Decodable, Sendable, Equatable {
        /// Rule name used in reports and the violations baseline
        package let name: String
        /// Forbids direct edges between two labels
        package let forbidEdge: LabelPair?
        /// Forbids transitive reachability between two labels (`to: sdk` also matches externals)
        package let forbidReach: LabelPair?
        /// Restricts transitive dependents of a label to an allowlist of labels
        package let forbidDependents: DependentsSpec?

        /// A (from, to) label pair
        package struct LabelPair: Decodable, Sendable, Equatable {
            /// Source label
            package let from: String
            /// Destination label
            package let to: String

            /// Builds directly, for tests
            package init(from: String, to: String) {
                self.from = from
                self.to = to
            }
        }

        /// Body of a forbid-dependents rule
        package struct DependentsSpec: Decodable, Sendable, Equatable {
            /// Label of the protected (heavy) targets
            package let of: String
            /// Labels allowed to depend on them
            package let except: [String]

            /// Builds directly, for tests
            package init(of: String, except: [String]) {
                self.of = of
                self.except = except
            }
        }

        /// Builds directly, for tests
        package init(
            name: String,
            forbidEdge: LabelPair? = nil,
            forbidReach: LabelPair? = nil,
            forbidDependents: DependentsSpec? = nil,
        ) {
            self.name = name
            self.forbidEdge = forbidEdge
            self.forbidReach = forbidReach
            self.forbidDependents = forbidDependents
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
        package let featureCostWarnSeconds: Double?
        /// FeatureCost regression (seconds) at or above which check errors. Defaults to 30
        package let featureCostErrorSeconds: Double?

        /// Builds directly, for tests
        package init(
            baseline: String? = nil,
            makespanWarnSeconds: Double? = nil,
            makespanErrorSeconds: Double? = nil,
            violationsBaseline: String? = nil,
            featureCostWarnSeconds: Double? = nil,
            featureCostErrorSeconds: Double? = nil,
        ) {
            self.baseline = baseline
            self.makespanWarnSeconds = makespanWarnSeconds
            self.makespanErrorSeconds = makespanErrorSeconds
            self.violationsBaseline = violationsBaseline
            self.featureCostWarnSeconds = featureCostWarnSeconds
            self.featureCostErrorSeconds = featureCostErrorSeconds
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
        labels: Labels? = nil,
        invariants: [InvariantSpec]? = nil,
        weights: String? = nil,
    ) {
        self.path = path
        self.exclude = exclude
        self.root = root
        self.costPerTarget = costPerTarget
        self.cores = cores
        self.topCount = topCount
        self.check = check
        self.labels = labels
        self.invariants = invariants
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
