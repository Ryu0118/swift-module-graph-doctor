import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct InvariantRuleEngineTests {
    private func target(_ name: String) -> TargetID {
        TargetID(packageName: "P", targetName: name)
    }

    private func makeLabeler(sdk: Set<String> = []) throws -> TargetLabeler {
        try TargetLabeler(
            explicit: [:],
            regexRules: [
                .init(pattern: "(Client|UseCase)Live$", label: "live"),
                .init(pattern: "Feature$", label: "feature"),
                .init(pattern: "(Client|UseCase)$", label: "interface"),
            ],
            sdkProducts: sdk,
        )
    }

    @Test("forbid-edgeはFeature→Liveの直接辺を検出する")
    func forbidEdgeDetectsFeatureToLive() throws {
        let feature = target("HomeFeature")
        let live = target("FooClientLive")
        let graph = ModuleGraph(
            nodes: [feature, live],
            edges: [feature: [live]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try InvariantRuleEngine.evaluate(
            rules: [.forbidEdge(name: "feature-no-live", from: "feature", to: "live")],
            graph: graph,
            scope: graph.nonTestNodes,
            labeler: makeLabeler(),
        )

        #expect(violations.map(\.key) == ["feature-no-live: P/HomeFeature -> P/FooClientLive"])
    }

    @Test("forbid-reachは中間ノード経由の推移的到達をwitness path付きで検出する")
    func forbidReachDetectsTransitiveLeak() throws {
        // interface -> plain -> live: no direct edge, but reachable
        let interface = target("FooClient")
        let middle = target("Helper")
        let live = target("BarUseCaseLive")
        let graph = ModuleGraph(
            nodes: [interface, middle, live],
            edges: [interface: [middle], middle: [live]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try InvariantRuleEngine.evaluate(
            rules: [.forbidReach(name: "no-live-reach", from: "interface", to: "live")],
            graph: graph,
            scope: graph.nonTestNodes,
            labeler: makeLabeler(),
        )

        #expect(violations.count == 1)
        #expect(violations[0].path == ["P/FooClient", "P/Helper", "P/BarUseCaseLive"])
    }

    @Test("forbid-reachのto:sdkは外部product依存のリークを検出する")
    func forbidReachDetectsExternalSDKLeak() throws {
        let interface = target("FooClient")
        let middle = target("Helper")
        let graph = ModuleGraph(
            nodes: [interface, middle],
            edges: [interface: [middle]],
            externalDependencies: [middle: ["SomeDatabaseSDK", "HarmlessLib"]],
            testTargets: [],
        )

        let violations = try InvariantRuleEngine.evaluate(
            rules: [.forbidReach(name: "interface-no-sdk", from: "interface", to: "sdk")],
            graph: graph,
            scope: graph.nonTestNodes,
            labeler: makeLabeler(sdk: ["SomeDatabaseSDK"]),
        )

        #expect(violations.map(\.key) == ["interface-no-sdk: P/FooClient -> SomeDatabaseSDK"])
        #expect(violations[0].path == ["P/FooClient", "P/Helper", "SomeDatabaseSDK"])
    }

    @Test("forbid-dependentsはallowlist外の依存元だけを違反にする")
    func forbidDependentsAllowsOnlyListedLabels() throws {
        let heavy = target("HeavyClientLive")
        let allowed = target("OtherUseCaseLive")
        let offender = target("HomeFeature")
        let graph = ModuleGraph(
            nodes: [heavy, allowed, offender],
            edges: [allowed: [heavy], offender: [heavy]],
            externalDependencies: [:],
            testTargets: [],
        )

        let violations = try InvariantRuleEngine.evaluate(
            rules: [.forbidDependents(name: "heavy-confined", heavy: "live", except: ["live", "app"])],
            graph: graph,
            scope: graph.nonTestNodes,
            labeler: makeLabeler(),
        )

        // The allowed live dependent passes; the feature and any unlabeled dependent violate.
        // Note: heavy targets themselves are labeled live, so allowed -> heavy is fine both ways
        #expect(violations.contains { $0.key == "heavy-confined: P/HomeFeature -> P/HeavyClientLive" })
        #expect(!violations.contains { $0.key.contains("OtherUseCaseLive ->") })
    }

    @Test("ラベル解決は明示指定がregexより優先される")
    func explicitLabelWinsOverRegex() throws {
        let labeler = try TargetLabeler(
            explicit: ["SpecialFeature": "model"],
            regexRules: [.init(pattern: "Feature$", label: "feature")],
            sdkProducts: [],
        )

        #expect(labeler.label(of: target("SpecialFeature")) == "model")
        #expect(labeler.label(of: target("NormalFeature")) == "feature")
        #expect(labeler.label(of: target("Unmatched")) == nil)
    }

    @Test("不正なregexパターンはエラーになる")
    func invalidRegexPatternThrows() {
        #expect(throws: TargetLabeler.Error.self) {
            try TargetLabeler(
                explicit: [:],
                regexRules: [.init(pattern: "([", label: "broken")],
                sdkProducts: [],
            )
        }
    }
}
