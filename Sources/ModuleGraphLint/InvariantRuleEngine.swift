import Foundation
import ModuleGraphKit

/// Evaluates architecture invariants as reachability predicates over the labeled DAG.
///
/// All rules are O(V+E) reachability queries:
/// - `forbid-edge`:       for every s labeled `from` and t labeled `to`: edge (s -> t) must not exist
/// - `forbid-reach`:      for every s labeled `from`: reach(s) must contain no node/external labeled `to`
/// - `forbid-dependents`: for every h labeled `heavy`: dependents*(h) must only carry labels in `except`
package enum InvariantRuleEngine {
    /// A declarative invariant rule
    package enum Rule: Sendable, Equatable {
        /// Forbids direct edges from label `from` to label `to`
        case forbidEdge(name: String, from: String, to: String)
        /// Forbids transitive reachability from label `from` to label `to`
        /// (`to` may also match SDK-labeled external products)
        case forbidReach(name: String, from: String, to: String)
        /// Restricts transitive dependents of label `heavy` to labels in `except`
        case forbidDependents(name: String, heavy: String, except: Set<String>)

        /// Rule name used in reports and the violations baseline
        package var name: String {
            switch self {
            case let .forbidEdge(name, _, _), let .forbidReach(name, _, _),
                 let .forbidDependents(name, _, _):
                name
            }
        }
    }

    /// A single rule violation. `key` is the stable identity used by the baseline
    package struct Violation: Sendable, Equatable {
        /// Rule name
        package let rule: String
        /// Stable identity, e.g. `feature-no-live: Foo/BarFeature -> Foo/BazClientLive`
        package let key: String
        /// Witness path (source -> ... -> offending node) for human review
        package let path: [String]

        /// Creates a violation
        package init(rule: String, key: String, path: [String]) {
            self.rule = rule
            self.key = key
            self.path = path
        }
    }

    /// Immutable evaluation inputs shared by all rule evaluators
    private struct Context: Sendable {
        let graph: ModuleGraph
        let scope: Set<TargetID>
        let labels: [TargetID: String]
        /// Exact names per layer, used to match external products
        let externalNames: [String: Set<String>]
    }

    /// Evaluates all rules over the closure `scope`.
    /// Reachability scans per source target are independent and run in parallel
    package static func evaluate(
        rules: [Rule],
        graph: ModuleGraph,
        scope: Set<TargetID>,
        labels: [TargetID: String],
        externalNames: [String: Set<String>] = [:],
    ) async -> [Violation] {
        let context = Context(graph: graph, scope: scope, labels: labels, externalNames: externalNames)
        var violations: [Violation] = []
        for rule in rules {
            switch rule {
            case let .forbidEdge(name, from, to):
                violations += forbidEdge(name: name, from: from, to: to, context: context)
            case let .forbidReach(name, from, to):
                violations += await forbidReach(name: name, from: from, to: to, context: context)
            case let .forbidDependents(name, heavy, except):
                violations += forbidDependents(name: name, heavy: heavy, except: except, context: context)
            }
        }
        return violations.sorted { $0.key < $1.key }
    }

    private static func forbidEdge(
        name: String,
        from: String,
        to: String,
        context: Context,
    ) -> [Violation] {
        var violations: [Violation] = []
        for source in context.scope where context.labels[source] == from {
            for target in context.graph.dependencies(of: source) where context.labels[target] == to {
                violations.append(Violation(
                    rule: name,
                    key: "\(name): \(source) -> \(target)",
                    path: [source.description, target.description],
                ))
            }
        }
        return violations
    }

    /// BFS from each `from`-labeled node; records the first witness path per offending node
    private static func forbidReach(
        name: String,
        from: String,
        to: String,
        context: Context,
    ) async -> [Violation] {
        let sources = context.scope.filter { context.labels[$0] == from }
        return await withTaskGroup(of: [Violation].self) { group in
            for source in sources {
                group.addTask {
                    reachViolations(name: name, source: source, to: to, context: context)
                }
            }
            var violations: [Violation] = []
            for await batch in group {
                violations += batch
            }
            return violations
        }
    }

    private static func reachViolations(
        name: String,
        source: TargetID,
        to targetLabel: String,
        context: Context,
    ) -> [Violation] {
        var violations: [Violation] = []
        var parent: [TargetID: TargetID] = [:]
        var queue: [TargetID] = [source]
        var visited: Set<TargetID> = [source]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            // External leak: unresolved dependencies whose names belong to the target layer
            for external in (context.graph.externalDependencies[current] ?? []).sorted()
                where context.externalNames[targetLabel]?.contains(external) == true
            {
                violations.append(Violation(
                    rule: name,
                    key: "\(name): \(source) -> \(external)",
                    path: witnessPath(to: current, parent: parent) + [external],
                ))
            }
            for next in context.graph.dependencies(of: current) where context.scope.contains(next) {
                if context.labels[next] == targetLabel, next != source {
                    violations.append(Violation(
                        rule: name,
                        key: "\(name): \(source) -> \(next)",
                        path: witnessPath(to: current, parent: parent) + [next.description],
                    ))
                }
                if !visited.contains(next) {
                    visited.insert(next)
                    parent[next] = current
                    queue.append(next)
                }
            }
        }
        return violations
    }

    private static func forbidDependents(
        name: String,
        heavy heavyLabel: String,
        except: Set<String>,
        context: Context,
    ) -> [Violation] {
        var violations: [Violation] = []
        for heavy in context.scope where context.labels[heavy] == heavyLabel {
            for dependent in context.graph.transitiveDependents(of: heavy, within: context.scope) {
                let label = context.labels[dependent]
                if label == nil || !except.contains(label ?? "") {
                    violations.append(Violation(
                        rule: name,
                        key: "\(name): \(dependent) -> \(heavy)",
                        path: [dependent.description, heavy.description],
                    ))
                }
            }
        }
        return violations
    }

    /// Reconstructs source -> ... -> node from BFS parent pointers
    private static func witnessPath(to node: TargetID, parent: [TargetID: TargetID]) -> [String] {
        var path: [String] = [node.description]
        var current = node
        while let previous = parent[current] {
            path.insert(previous.description, at: 0)
            current = previous
        }
        return path
    }
}
