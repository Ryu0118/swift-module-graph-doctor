@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct BaselineGateTests {
    private func makeBaseline(
        makespan: Double = 10.0,
        depth: Int = 5,
        count: Int = 50,
        edges: [String: [String]] = [:],
    ) -> GraphBaseline {
        GraphBaseline(
            roots: ["P/App"],
            costPerTarget: 1.0,
            parallelism: 10,
            targetCount: count,
            criticalPathLength: depth,
            simulatedMakespan: makespan,
            edges: edges,
        )
    }

    private func makeMetrics(
        makespan: Double = 10.0,
        depth: Int = 5,
        count: Int = 50,
    ) -> WorkSpanMetrics {
        WorkSpanMetrics(
            targetCount: count,
            criticalPathLength: depth,
            criticalPath: [],
            totalWork: Double(count),
            criticalPathBound: Double(depth),
            parallelBound: Double(count) / 10.0,
            simulatedMakespan: makespan,
            bindingConstraint: .balanced,
            widthProfile: [],
        )
    }

    @Test("baselineと同一なら判定は空")
    func identicalGraphYieldsNoFindings() {
        let findings = BaselineGate.evaluate(
            baseline: makeBaseline(),
            current: makeMetrics(),
            currentEdges: [:],
        )

        #expect(findings.isEmpty)
    }

    @Test("makespan悪化は警告閾値とエラー閾値で段階的に判定される")
    func makespanRegressionEscalatesBySeverity() {
        let baseline = makeBaseline(makespan: 10.0)

        let ok = BaselineGate.evaluate(
            baseline: baseline, current: makeMetrics(makespan: 10.4), currentEdges: [:],
        )
        let warn = BaselineGate.evaluate(
            baseline: baseline, current: makeMetrics(makespan: 10.6), currentEdges: [:],
        )
        let error = BaselineGate.evaluate(
            baseline: baseline, current: makeMetrics(makespan: 11.2), currentEdges: [:],
        )

        #expect(ok.isEmpty)
        #expect(warn.map(\.severity) == [.warning])
        #expect(error.map(\.severity) == [.error])
    }

    @Test("makespan改善は判定を出さない")
    func makespanImprovementIsSilent() {
        let findings = BaselineGate.evaluate(
            baseline: makeBaseline(makespan: 10.0),
            current: makeMetrics(makespan: 8.0),
            currentEdges: [:],
        )

        #expect(findings.isEmpty)
    }

    @Test("クリティカルパス伸長は警告、ターゲット数変化はinfoになる")
    func depthIncreaseWarnsAndCountChangeInforms() {
        let findings = BaselineGate.evaluate(
            baseline: makeBaseline(depth: 5, count: 50),
            current: makeMetrics(depth: 6, count: 51),
            currentEdges: [:],
        )

        #expect(findings.contains(BaselineGate.Finding(
            severity: .warning,
            message: "critical path length increased: 5 -> 6",
        )))
        #expect(findings.contains(BaselineGate.Finding(
            severity: .info,
            message: "target count changed: 50 -> 51",
        )))
    }

    @Test("新規辺と削除辺がinfoとして列挙される")
    func edgeDiffListsAddedAndRemovedEdges() {
        let findings = BaselineGate.evaluate(
            baseline: makeBaseline(edges: ["P/A": ["P/B"], "P/B": []]),
            current: makeMetrics(),
            currentEdges: ["P/A": ["P/C"], "P/B": []],
        )

        #expect(findings.contains(BaselineGate.Finding(severity: .info, message: "new edge: P/A -> P/C")))
        #expect(findings.contains(BaselineGate.Finding(severity: .info, message: "removed edge: P/A -> P/B")))
    }

    @Test("カスタム閾値が既定値を上書きする")
    func customThresholdsOverrideDefaults() {
        let findings = BaselineGate.evaluate(
            baseline: makeBaseline(makespan: 10.0),
            current: makeMetrics(makespan: 10.3),
            currentEdges: [:],
            thresholds: BaselineGate.Thresholds(makespanWarnSeconds: 0.2, makespanErrorSeconds: 0.25),
        )

        #expect(findings.map(\.severity) == [.error])
    }
}
