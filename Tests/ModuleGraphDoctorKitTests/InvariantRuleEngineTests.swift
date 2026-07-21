@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct InvariantRuleEngineTests {
    private func target(_ name: String) -> TargetID {
        TargetID(packageName: "P", targetName: name)
    }

    private func layers(for scope: Set<TargetID>, weights: TargetWeights? = nil) throws -> [TargetID: String] {
        let labeler = try TargetLabeler(layers: [
            "live": .regex("(Client|UseCase)Live$"),
            "feature": .regex("Feature$"),
            "interface": .regex("(Client|UseCase)$"),
        ])
        return try labeler.resolveLayers(for: scope, weights: weights)
    }

    @Test("A -> B（直接辺の禁止）はFeature→Liveの辺を検出する")
    func forbidEdgeDetectsFeatureToLive() async throws {
        let feature = target("HomeFeature")
        let live = target("FooClientLive")
        let graph = ModuleGraph(
            nodes: [feature, live],
            edges: [feature: [live]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try await InvariantRuleEngine.evaluate(
            rules: [.forbidEdge(name: "feature -> live", from: "feature", to: "live")],
            graph: graph,
            scope: graph.nonTestNodes,
            labels: layers(for: graph.nonTestNodes),
        )

        #expect(violations.map(\.key) == ["feature -> live: P/HomeFeature -> P/FooClientLive"])
    }

    @Test("A => B（推移到達の禁止）は中間ノード経由のリークをwitness path付きで検出する")
    func forbidReachDetectsTransitiveLeak() async throws {
        let interface = target("FooClient")
        let middle = target("Helper")
        let live = target("BarUseCaseLive")
        let graph = ModuleGraph(
            nodes: [interface, middle, live],
            edges: [interface: [middle], middle: [live]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try await InvariantRuleEngine.evaluate(
            rules: [.forbidReach(name: "interface => live", from: "interface", to: "live")],
            graph: graph,
            scope: graph.nonTestNodes,
            labels: layers(for: graph.nonTestNodes),
        )

        #expect(violations.count == 1)
        #expect(violations[0].path == ["P/FooClient", "P/Helper", "P/BarUseCaseLive"])
    }

    @Test("完全一致layerは外部product依存のリークにもマッチする")
    func forbidReachDetectsExternalSDKLeak() async throws {
        let interface = target("FooClient")
        let middle = target("Helper")
        let graph = ModuleGraph(
            nodes: [interface, middle],
            edges: [interface: [middle]],
            externalDependencies: [middle: ["SomeDatabaseSDK", "HarmlessLib"]],
            testTargets: [],
        )

        let violations = try await InvariantRuleEngine.evaluate(
            rules: [.forbidReach(name: "interface => sdk", from: "interface", to: "sdk")],
            graph: graph,
            scope: graph.nonTestNodes,
            labels: layers(for: graph.nonTestNodes),
            externalNames: ["sdk": ["SomeDatabaseSDK"]],
        )

        #expect(violations.map(\.key) == ["interface => sdk: P/FooClient -> SomeDatabaseSDK"])
        #expect(violations[0].path == ["P/FooClient", "P/Helper", "SomeDatabaseSDK"])
    }

    @Test("* => B（依存元の制限）はallow外の依存元だけを違反にする")
    func forbidDependentsAllowsOnlyListedLayers() async throws {
        let heavy = target("HeavyClientLive")
        let allowed = target("OtherUseCaseLive")
        let offender = target("HomeFeature")
        let graph = ModuleGraph(
            nodes: [heavy, allowed, offender],
            edges: [allowed: [heavy], offender: [heavy]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try await InvariantRuleEngine.evaluate(
            rules: [.forbidDependents(name: "* => live", heavy: "live", except: ["live", "app"])],
            graph: graph,
            scope: graph.nonTestNodes,
            labels: layers(for: graph.nonTestNodes),
        )

        #expect(violations.contains { $0.key == "* => live: P/HomeFeature -> P/HeavyClientLive" })
        #expect(!violations.contains { $0.key.contains("OtherUseCaseLive ->") })
    }

    @Test("完全一致layerはregexより優先され、未マッチのtargetはlayerなしになる")
    func exactNamesWinOverRegex() throws {
        let labeler = try TargetLabeler(layers: [
            "model": .names(["SpecialFeature"]),
            "feature": .regex("Feature$"),
        ])

        let resolved = try labeler.resolveLayers(
            for: [target("SpecialFeature"), target("NormalFeature"), target("Unmatched")],
            weights: nil,
        )

        #expect(resolved[target("SpecialFeature")] == "model")
        #expect(resolved[target("NormalFeature")] == "feature")
        #expect(resolved[target("Unmatched")] == nil)
    }

    @Test("1 targetが複数regexにマッチしたら順序で黙って解決せずエラーになる")
    func ambiguousRegexLayersThrow() throws {
        let labeler = try TargetLabeler(layers: [
            "a": .regex("Feature$"),
            "b": .regex("^Home"),
        ])

        #expect(throws: TargetLabeler.Error.self) {
            try labeler.resolveLayers(for: [target("HomeFeature")], weights: nil)
        }
    }

    @Test("不正なregexパターンはエラーになる")
    func invalidRegexPatternThrows() {
        #expect(throws: TargetLabeler.Error.self) {
            try TargetLabeler(layers: ["broken": .regex("([")])
        }
    }
}
