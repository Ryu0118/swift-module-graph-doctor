/// Pure logic that composes describe results of multiple packages into a single `ModuleGraph`.
///
/// Dependency resolution rules:
/// 1. Target dependencies (`target_dependencies`) resolve to targets within the same package.
///    If no such target exists in the same package, resolution as a product name is attempted
///    (a `.byName` dependency can resolve to either a target or a product)
/// 2. Product dependencies (`product_dependencies`) resolve through the product table of the
///    local packages, adding edges to the product's constituent targets
/// 3. Dependencies that resolve as neither are recorded as external dependencies
///    (products of external packages)
package enum GraphAssembler {
    /// Assembles a graph from an array of describe results
    package static func assemble(packages: [DescribedPackage]) -> ModuleGraph {
        let productTable = buildProductTable(packages: packages)

        var nodes: Set<TargetID> = []
        var testTargets: Set<TargetID> = []
        var edges: [TargetID: Set<TargetID>] = [:]
        var externals: [TargetID: Set<String>] = [:]

        for package in packages {
            let localTargetNames = Set(package.targets.map(\.name))
            for target in package.targets {
                let id = TargetID(packageName: package.name, targetName: target.name)
                nodes.insert(id)
                if target.type == "test" {
                    testTargets.insert(id)
                }

                var (resolved, unresolved) = resolve(
                    target: target,
                    packageName: package.name,
                    localTargetNames: localTargetNames,
                    productTable: productTable,
                )
                // Drop self-edges (a product name resolving to the target itself)
                resolved.remove(id)
                edges[id] = resolved
                if !unresolved.isEmpty {
                    externals[id] = unresolved
                }
            }
        }

        return ModuleGraph(
            nodes: nodes,
            edges: edges,
            externalDependencies: externals,
            testTargets: testTargets,
        )
    }

    /// Product name -> TargetIDs of its constituent targets. Assumes product names are unique workspace-wide
    private static func buildProductTable(packages: [DescribedPackage]) -> [String: [TargetID]] {
        var table: [String: [TargetID]] = [:]
        for package in packages {
            for product in package.products {
                table[product.name, default: []].append(
                    contentsOf: product.targets.map {
                        TargetID(packageName: package.name, targetName: $0)
                    },
                )
            }
        }
        return table
    }

    /// Resolves the dependencies of one target. Returns (resolved local edges, unresolved = external dependency names)
    private static func resolve(
        target: DescribedPackage.Target,
        packageName: String,
        localTargetNames: Set<String>,
        productTable: [String: [TargetID]],
    ) -> (resolved: Set<TargetID>, unresolved: Set<String>) {
        var resolved: Set<TargetID> = []
        var unresolved: Set<String> = []

        for dependency in target.targetDependencies ?? [] {
            if localTargetNames.contains(dependency) {
                resolved.insert(TargetID(packageName: packageName, targetName: dependency))
            } else if let productTargets = productTable[dependency] {
                resolved.formUnion(productTargets)
            } else {
                unresolved.insert(dependency)
            }
        }
        for dependency in target.productDependencies ?? [] {
            if let productTargets = productTable[dependency] {
                resolved.formUnion(productTargets)
            } else {
                unresolved.insert(dependency)
            }
        }
        return (resolved, unresolved)
    }
}
