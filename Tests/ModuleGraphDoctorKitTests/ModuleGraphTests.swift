@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct ModuleGraphTests {
    private let nodeA = TargetID(packageName: "P", targetName: "A")
    private let nodeB = TargetID(packageName: "P", targetName: "B")
    private let nodeC = TargetID(packageName: "P", targetName: "C")
    private let nodeD = TargetID(packageName: "P", targetName: "D")

    /// Diamond-like graph: serial A -> B -> C -> D plus a shortcut edge A -> C
    private func makeDiamondGraph() -> ModuleGraph {
        ModuleGraph(
            nodes: [nodeA, nodeB, nodeC, nodeD],
            edges: [
                nodeA: [nodeB, nodeC],
                nodeB: [nodeC],
                nodeC: [nodeD],
            ],
            externalDependencies: [:],
            testTargets: [],
        )
    }

    @Test("closureはrootから到達可能な全ノードを返す")
    func closureCollectsAllReachableNodes() {
        let graph = makeDiamondGraph()

        #expect(graph.closure(of: nodeA) == [nodeA, nodeB, nodeC, nodeD])
        #expect(graph.closure(of: nodeC) == [nodeC, nodeD])
    }

    @Test("longestPathはショートカット辺ではなく最長チェーンを返す")
    func longestPathPrefersLongerChain() {
        let graph = makeDiamondGraph()
        let scope = graph.closure(of: nodeA)

        let result = graph.longestPath(within: scope)

        #expect(result.depth == 4)
        #expect(result.path == [nodeA, nodeB, nodeC, nodeD])
    }

    @Test("transitiveDependentsは間接的な依存元も全て返し、自分自身は含まない")
    func transitiveDependentsCollectsAllUpstreamNodes() {
        let graph = makeDiamondGraph()
        let scope = graph.closure(of: nodeA)

        let dependents = graph.transitiveDependents(of: nodeD, within: scope)

        #expect(dependents == [nodeA, nodeB, nodeC])
    }

    @Test("transitiveDependentsはscope外の依存元を含めない")
    func transitiveDependentsRespectsScope() {
        let graph = makeDiamondGraph()
        // Exclude nodeA from the scope -> dependents are only B and C
        let scope: Set<TargetID> = [nodeB, nodeC, nodeD]

        let dependents = graph.transitiveDependents(of: nodeD, within: scope)

        #expect(dependents == [nodeB, nodeC])
    }

    @Test("depthLevelsは各ノードを最長チェーン長の層に分類する（幅プロファイル）")
    func depthLevelsBuildWidthProfile() {
        let graph = makeDiamondGraph()
        let scope = graph.closure(of: nodeA)

        let levels = graph.depthLevels(within: scope)

        #expect(levels[1] == [nodeD])
        #expect(levels[2] == [nodeC])
        #expect(levels[3] == [nodeB])
        #expect(levels[4] == [nodeA])
    }

    @Test("複数rootのclosureは和集合になる")
    func multiRootClosureIsUnion() {
        let left = TargetID(packageName: "P", targetName: "Left")
        let right = TargetID(packageName: "P", targetName: "Right")
        let shared = TargetID(packageName: "P", targetName: "Shared")
        let graph = ModuleGraph(
            nodes: [left, right, shared],
            edges: [left: [shared], right: [shared]],
            externalDependencies: [:],
            testTargets: [],
        )

        #expect(graph.closure(of: [left, right]) == [left, right, shared])
    }
}
