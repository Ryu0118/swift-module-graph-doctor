import Foundation
import Yams

/// Bridges configuration to the invariant engine and applies the violations baseline.
///
/// Known violations are committed to `violations-baseline.yml` (boy-scout style):
/// only violations whose stable keys are absent from the baseline are reported as
/// errors, so a legacy codebase can adopt the rules incrementally.
package enum InvariantChecker {
    /// Errors thrown while interpreting the configuration
    package enum Error: Swift.Error, LocalizedError {
        /// An invariant spec has zero or multiple rule bodies
        case ambiguousRule(String)

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .ambiguousRule(name):
                "invariant '\(name)' must declare exactly one of forbidEdge / forbidReach / forbidDependents"
            }
        }
    }

    /// Builds the labeler from the configuration (empty labeler when unconfigured)
    package static func makeLabeler(configuration: Configuration) throws -> TargetLabeler {
        let labels = configuration.labels
        return try TargetLabeler(
            explicit: labels?.explicit ?? [:],
            regexRules: (labels?.rules ?? []).map {
                TargetLabeler.RegexRule(pattern: $0.pattern, label: $0.label)
            },
            sdkProducts: Set(labels?.sdk ?? []),
        )
    }

    /// Converts invariant specs into engine rules, validating that each spec has exactly one body
    package static func makeRules(configuration: Configuration) throws -> [InvariantRuleEngine.Rule] {
        try (configuration.invariants ?? []).map { spec in
            let bodies = [spec.forbidEdge != nil, spec.forbidReach != nil, spec.forbidDependents != nil]
            guard bodies.count(where: { $0 }) == 1 else {
                throw Error.ambiguousRule(spec.name)
            }
            if let edge = spec.forbidEdge {
                return .forbidEdge(name: spec.name, from: edge.from, to: edge.to)
            }
            if let reach = spec.forbidReach {
                return .forbidReach(name: spec.name, from: reach.from, to: reach.to)
            }
            guard let dependents = spec.forbidDependents else {
                throw Error.ambiguousRule(spec.name)
            }
            return .forbidDependents(
                name: spec.name,
                heavy: dependents.of,
                except: Set(dependents.except),
            )
        }
    }

    /// Evaluates configured invariants over the closure and returns all violations
    package static func evaluate(
        configuration: Configuration,
        graph: ModuleGraph,
        scope: Set<TargetID>,
    ) throws -> [InvariantRuleEngine.Violation] {
        let rules = try makeRules(configuration: configuration)
        guard !rules.isEmpty else { return [] }
        return try InvariantRuleEngine.evaluate(
            rules: rules,
            graph: graph,
            scope: scope,
            labeler: makeLabeler(configuration: configuration),
        )
    }

    /// Violations baseline: a sorted list of stable violation keys stored as YAML
    package enum ViolationsBaseline {
        /// Loads baselined keys (empty set when the file does not exist)
        package static func load(from url: URL) throws -> Set<String> {
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return []
            }
            let yaml = try String(contentsOf: url, encoding: .utf8)
            return try Set(YAMLDecoder().decode([String].self, from: yaml))
        }

        /// Writes keys sorted so the file is diff-stable and idempotent
        package static func save(_ keys: Set<String>, to url: URL) throws {
            let yaml = try YAMLEncoder().encode(keys.sorted())
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
