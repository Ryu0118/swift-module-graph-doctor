@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct WorkSpanAnalyzerTests {
    private func target(_ name: String) -> TargetID {
        TargetID(packageName: "P", targetName: name)
    }

    /// Flat graph Root -> Leaf1..4 (dependencies build first, root last)
    private func makeFlatGraph() -> ModuleGraph {
        let root = target("Root")
        let leaves = (1 ... 4).map { target("Leaf\($0)") }
        return ModuleGraph(
            nodes: Set([root] + leaves),
            edges: [root: Set(leaves)],
            externalDependencies: [:],
            testTargets: [],
        )
    }

    @Test("直列チェーンのmakespanは並列度に関係なくT∞に一致する")
    func serialChainMakespanEqualsCriticalPathBound() {
        let chain = ["A", "B", "C", "D"].map(target)
        let graph = ModuleGraph(
            nodes: Set(chain),
            edges: [
                chain[0]: [chain[1]],
                chain[1]: [chain[2]],
                chain[2]: [chain[3]],
            ],
            externalDependencies: [:],
            testTargets: [],
        )

        let metrics = WorkSpanAnalyzer.analyze(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 2.0,
            parallelism: 10,
        )

        #expect(metrics.criticalPathLength == 4)
        #expect(metrics.criticalPathBound == 8.0)
        #expect(metrics.simulatedMakespan == 8.0)
        #expect(metrics.bindingConstraint == .criticalPath)
    }

    @Test("フラットグラフのmakespanは葉の並列実行+root直列になる")
    func flatGraphMakespanFollowsParallelism() {
        let graph = makeFlatGraph()

        // p=2: 4 leaves in 2 rounds of 2 in parallel (2s) -> root (1s) = 3s
        let metrics = WorkSpanAnalyzer.analyze(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 1.0,
            parallelism: 2,
        )

        #expect(metrics.simulatedMakespan == 3.0)
        #expect(metrics.totalWork == 5.0)
        #expect(metrics.parallelBound == 2.5)
        #expect(metrics.bindingConstraint == .parallelism)
    }

    @Test("p=1のmakespanはT₁に一致する")
    func singleProcessorMakespanEqualsTotalWork() {
        let graph = makeFlatGraph()

        let metrics = WorkSpanAnalyzer.analyze(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 1.0,
            parallelism: 1,
        )

        #expect(metrics.simulatedMakespan == 5.0)
    }

    @Test("T∞とT₁/pの差が10%以内ならbalanced（膝到達）と判定される")
    func nearEqualBoundsAreJudgedBalanced() {
        // D=2, N=20, p=10 -> T_inf = 2c and T_1/p = 2c match exactly
        let root = target("Root")
        let leaves = (1 ... 19).map { target("Leaf\($0)") }
        let graph = ModuleGraph(
            nodes: Set([root] + leaves),
            edges: [root: Set(leaves)],
            externalDependencies: [:],
            testTargets: [],
        )

        let metrics = WorkSpanAnalyzer.analyze(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 1.0,
            parallelism: 10,
        )

        #expect(metrics.criticalPathBound == 2.0)
        #expect(metrics.parallelBound == 2.0)
        #expect(metrics.bindingConstraint == .balanced)
    }

    @Test("widthProfileは深さごとの幅を昇順で返す")
    func widthProfileListsLayersInDepthOrder() {
        let graph = makeFlatGraph()

        let metrics = WorkSpanAnalyzer.analyze(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 1.0,
            parallelism: 2,
        )

        #expect(metrics.widthProfile.map(\.depth) == [1, 2])
        #expect(metrics.widthProfile.map(\.width) == [4, 1])
        #expect(metrics.widthProfile[1].targets == ["Root"])
    }

    @Test("critical-path-first優先度により長いチェーン側が先に実行される")
    func criticalPathFirstPriorityAvoidsMakespanInflation() {
        // Chain A -> B -> C (heights 3, 2, 1) plus independent nodes X, Y. p=2, c=1.
        // CP-first: at t=0, among C (dependency-free end of the height-3 path) and X/Y,
        // height priority runs C first.
        // Optimal schedule: C,X -> B,Y -> A = 3s.
        // Wrong priority runs X,Y first, delaying the chain to 4s
        let nodeA = target("A")
        let nodeB = target("B")
        let nodeC = target("C")
        let nodeX = target("X")
        let nodeY = target("Y")
        let graph = ModuleGraph(
            nodes: [nodeA, nodeB, nodeC, nodeX, nodeY],
            edges: [nodeA: [nodeB], nodeB: [nodeC]],
            externalDependencies: [:],
            testTargets: [],
        )

        let makespan = WorkSpanAnalyzer.simulateMakespan(
            graph: graph,
            scope: graph.nonTestNodes,
            costPerTarget: 1.0,
            parallelism: 2,
        )

        #expect(makespan == 3.0)
    }
}
