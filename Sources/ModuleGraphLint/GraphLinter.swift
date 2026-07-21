import Foundation
import ModuleGraphKit

/// Bridges `layers:` / `lint:` declarations to the rule engine.
///
/// Parses the deny DSL into engine rules and evaluates them over a graph
/// closure, without knowing anything about the configuration file format.
package enum GraphLinter {
    /// Errors thrown while interpreting the lint declarations
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
    package static func makeRules(lint: [LintRule]) throws -> [InvariantRuleEngine.Rule] {
        try lint.map { rule in
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

    /// Evaluates the lint rules over the closure and returns all violations
    package static func evaluate(
        layers: [String: LayerSpec],
        lint: [LintRule],
        graph: ModuleGraph,
        scope: Set<TargetID>,
        weights: TargetWeights? = nil,
    ) async throws -> [InvariantRuleEngine.Violation] {
        let rules = try makeRules(lint: lint)
        guard !rules.isEmpty else { return [] }
        let labeler = try TargetLabeler(layers: layers)
        return try await InvariantRuleEngine.evaluate(
            rules: rules,
            graph: graph,
            scope: scope,
            labels: labeler.resolveLayers(for: scope, weights: weights),
            externalNames: labeler.externalNames,
        )
    }
}
