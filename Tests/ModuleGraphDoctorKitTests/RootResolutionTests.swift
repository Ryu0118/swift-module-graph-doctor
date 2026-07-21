@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct RootResolutionTests {
    private let appA = TargetID(packageName: "AppA", targetName: "AppFeature")
    private let appB = TargetID(packageName: "AppB", targetName: "AppFeature")
    private let shared = TargetID(packageName: "Core", targetName: "SharedKit")
    private let tests = TargetID(packageName: "Core", targetName: "SharedKitTests")

    private func makeGraph() -> ModuleGraph {
        ModuleGraph(
            nodes: [appA, appB, shared, tests],
            edges: [appA: [shared], appB: [shared], tests: [shared]],
            externalDependencies: [:],
            testTargets: [tests],
        )
    }

    @Test("root省略時は誰にも依存されないtargetが自動検出される（testターゲット除外）")
    func emptyRootAutoDetectsSinks() throws {
        let roots = try GraphAnalysisSession.resolveRoots([], graph: makeGraph())

        #expect(roots == [appA, appB])
    }

    @Test("bare名は一意なら解決され、曖昧なら候補付きエラーになる")
    func bareNameResolvesUniquelyOrThrows() throws {
        let graph = makeGraph()

        #expect(try GraphAnalysisSession.resolveRoots(["SharedKit"], graph: graph) == [shared])
        #expect(throws: GraphAnalysisSession.Error.self) {
            try GraphAnalysisSession.resolveRoots(["AppFeature"], graph: graph)
        }
    }

    @Test("package/target形式は曖昧さを解消し、存在しないrootはエラーになる")
    func qualifiedNameDisambiguates() throws {
        let graph = makeGraph()

        #expect(try GraphAnalysisSession.resolveRoots(["AppA/AppFeature"], graph: graph) == [appA])
        #expect(throws: GraphAnalysisSession.Error.self) {
            try GraphAnalysisSession.resolveRoots(["Nope/Missing"], graph: graph)
        }
        #expect(throws: GraphAnalysisSession.Error.self) {
            try GraphAnalysisSession.resolveRoots(["Missing"], graph: graph)
        }
    }
}
