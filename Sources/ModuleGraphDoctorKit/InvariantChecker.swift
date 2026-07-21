import FileManagerProtocol
import Foundation
import Yams

/// Bridges the `layers:` / `lint:` configuration to the rule engine and applies
/// the violations baseline.
///
/// Known violations are committed to `violations-baseline.yml` (boy-scout style):
/// only violations whose stable keys are absent from the baseline are reported as
/// errors, so a legacy codebase can adopt the rules incrementally.
package enum InvariantChecker {
    /// Errors thrown while interpreting the configuration
    package enum Error: Swift.Error, LocalizedError {
        /// The deny DSL string is malformed
        case invalidRule(String)
        /// `allow:` is only meaningful on a `* => layer` rule
        case allowRequiresWildcard(String)

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .invalidRule(rule):
                "lint rule '\(rule)' is malformed; expected 'A -> B' (direct), "
                    + "'A => B' (transitive), or '* => B' with allow:"
            case let .allowRequiresWildcard(rule):
                "lint rule '\(rule)' uses allow:, which only applies to '* => layer' rules"
            }
        }
    }

    /// Parses the deny DSL into engine rules.
    ///
    /// - `A -> B`  : forbid direct edges from layer A to layer B
    /// - `A => B`  : forbid transitive reachability from A to B
    /// - `* => B`  : forbid all dependents of B except the `allow:` layers
    package static func makeRules(configuration: Configuration) throws -> [InvariantRuleEngine.Rule] {
        try (configuration.lint ?? []).map { rule in
            let name = rule.deny.trimmingCharacters(in: .whitespaces)
            let transitive = name.contains("=>")
            let separator = transitive ? "=>" : "->"
            let parts = name.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw Error.invalidRule(rule.deny)
            }
            if parts[0] == "*" {
                guard transitive else { throw Error.invalidRule(rule.deny) }
                return .forbidDependents(
                    name: name,
                    heavy: parts[1],
                    except: Set(rule.allow ?? []),
                )
            }
            guard rule.allow == nil else { throw Error.allowRequiresWildcard(rule.deny) }
            return transitive
                ? .forbidReach(name: name, from: parts[0], to: parts[1])
                : .forbidEdge(name: name, from: parts[0], to: parts[1])
        }
    }

    /// Evaluates configured lint rules over the closure and returns all violations
    package static func evaluate(
        configuration: Configuration,
        graph: ModuleGraph,
        scope: Set<TargetID>,
        weights: TargetWeights? = nil,
    ) async throws -> [InvariantRuleEngine.Violation] {
        let rules = try makeRules(configuration: configuration)
        guard !rules.isEmpty else { return [] }
        let labeler = try TargetLabeler(layers: configuration.layers ?? [:])
        return try await InvariantRuleEngine.evaluate(
            rules: rules,
            graph: graph,
            scope: scope,
            labels: labeler.resolveLayers(for: scope, weights: weights),
            externalNames: labeler.externalNames,
        )
    }

    /// Violations baseline: a sorted list of stable violation keys stored as YAML
    package enum ViolationsBaseline {
        /// Loads baselined keys (empty set when the file does not exist)
        package static func load(
            from url: URL,
            fileManager: any FileManagerProtocol = FileManager.default,
        ) throws -> Set<String> {
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
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
