/// Target-level dependency DAG composed from multiple packages.
///
/// All analysis (metrics computation, rule evaluation) runs on this type.
/// Nodes are identified by `TargetID` (the (package, target) composite key).
package struct ModuleGraph: Sendable {
    /// All local targets in the graph (including test targets)
    package let nodes: Set<TargetID>
    /// Dependency edges. `edges[t]` is the set of local targets `t` directly depends on
    package let edges: [TargetID: Set<TargetID>]
    /// External product dependencies that could not be resolved within the local packages.
    /// `externalDependencies[t]` is the set of external product names `t` directly depends on
    package let externalDependencies: [TargetID: Set<String>]
    /// Set of test targets (excluded from closure analysis by default)
    package let testTargets: Set<TargetID>

    /// Builds a graph from nodes, edges, external dependencies, and the test-target set
    package init(
        nodes: Set<TargetID>,
        edges: [TargetID: Set<TargetID>],
        externalDependencies: [TargetID: Set<String>],
        testTargets: Set<TargetID>,
    ) {
        self.nodes = nodes
        self.edges = edges
        self.externalDependencies = externalDependencies
        self.testTargets = testTargets
    }
}

package extension ModuleGraph {
    /// Local targets excluding test targets
    var nonTestNodes: Set<TargetID> {
        nodes.subtracting(testTargets)
    }

    /// Direct dependencies of `target` (local only)
    func dependencies(of target: TargetID) -> Set<TargetID> {
        edges[target] ?? []
    }

    /// Builds a reverse-edge index. `result[t]` is the set of targets that directly depend on `t`
    func reverseEdges() -> [TargetID: Set<TargetID>] {
        var reversed: [TargetID: Set<TargetID>] = [:]
        for (source, targets) in edges {
            for target in targets {
                reversed[target, default: []].insert(source)
            }
        }
        return reversed
    }

    /// Targets reachable from `root` along the dependency direction (including `root` itself).
    /// Test targets are not traversed
    func closure(of root: TargetID) -> Set<TargetID> {
        var visited: Set<TargetID> = []
        var stack: [TargetID] = [root]
        while let current = stack.popLast() {
            guard !visited.contains(current), !testTargets.contains(current) else { continue }
            visited.insert(current)
            stack.append(contentsOf: dependencies(of: current))
        }
        return visited
    }

    /// Union of the closures of multiple roots
    func closure(of roots: some Sequence<TargetID>) -> Set<TargetID> {
        var union: Set<TargetID> = []
        for root in roots {
            union.formUnion(closure(of: root))
        }
        return union
    }

    /// Targets that depend on `target` directly or transitively (excluding `target` itself).
    /// `within` restricts the search space (usually the closure of the root)
    func transitiveDependents(
        of target: TargetID,
        within scope: Set<TargetID>,
    ) -> Set<TargetID> {
        let reversed = reverseEdges()
        var visited: Set<TargetID> = []
        var stack: [TargetID] = [target]
        while let current = stack.popLast() {
            for dependent in reversed[current] ?? [] where scope.contains(dependent) && !visited.contains(dependent) {
                visited.insert(dependent)
                stack.append(dependent)
            }
        }
        return visited
    }

    /// Longest dependency chain (critical path).
    ///
    /// In the return value, `depth` is the number of targets on the chain
    /// (edge count + 1), and `path` is ordered from the root side to the leaf side.
    func longestPath(within scope: Set<TargetID>) -> (depth: Int, path: [TargetID]) {
        var memo: [TargetID: (depth: Int, path: [TargetID])] = [:]

        func visit(_ node: TargetID) -> (depth: Int, path: [TargetID]) {
            if let cached = memo[node] {
                return cached
            }
            var best: (depth: Int, path: [TargetID]) = (1, [node])
            for dependency in dependencies(of: node) where scope.contains(dependency) {
                let sub = visit(dependency)
                if sub.depth + 1 > best.depth {
                    best = (sub.depth + 1, [node] + sub.path)
                }
            }
            memo[node] = best
            return best
        }

        var overall: (depth: Int, path: [TargetID]) = (0, [])
        for node in scope.sorted() {
            let candidate = visit(node)
            if candidate.depth > overall.depth {
                overall = candidate
            }
        }
        return overall
    }

    /// Targets grouped by depth (the longest chain length starting at that target).
    /// Used for the width profile (detecting parallelism-killing "necks")
    func depthLevels(within scope: Set<TargetID>) -> [Int: Set<TargetID>] {
        var memo: [TargetID: Int] = [:]

        func depth(of node: TargetID) -> Int {
            if let cached = memo[node] {
                return cached
            }
            var best = 1
            for dependency in dependencies(of: node) where scope.contains(dependency) {
                best = max(best, depth(of: dependency) + 1)
            }
            memo[node] = best
            return best
        }

        var levels: [Int: Set<TargetID>] = [:]
        for node in scope {
            levels[depth(of: node), default: []].insert(node)
        }
        return levels
    }
}
