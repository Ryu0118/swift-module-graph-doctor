import Foundation
@testable import ModuleGraphDoctorKit
import SwiftModuleGraph
import Testing

@Suite
struct TargetWeightsTests {
    private func target(_ name: String) -> TargetID {
        TargetID(packageName: "P", targetName: name)
    }

    @Test("XCLogParserのBuildStep木からtarget別Compile時間が合算される")
    func generatesWeightsFromBuildStepTree() throws {
        let json = """
        {
          "title": "Build MyApp",
          "type": "main",
          "duration": 100.0,
          "subSteps": [
            {
              "title": "Build target HeavyLib",
              "type": "target",
              "duration": 90.0,
              "subSteps": [
                { "title": "Compile A.swift", "type": "detail", "duration": 40.0, "subSteps": [] },
                { "title": "Compile B.swift", "type": "detail", "duration": 20.5, "subSteps": [] },
                { "title": "Link HeavyLib", "type": "detail", "duration": 29.5, "subSteps": [] }
              ]
            },
            {
              "title": "Build target NoCompile",
              "type": "target",
              "duration": 5.0,
              "subSteps": [
                { "title": "Copy resources", "type": "detail", "duration": 5.0, "subSteps": [] }
              ]
            }
          ]
        }
        """

        let weights = try WeightsGenerator.generate(fromXCLogParserJSON: Data(json.utf8))

        // Compile steps only: 40.0 + 20.5. Link time and the misleading
        // "Build target" wall duration (90.0, includes parallel waiting) are excluded
        #expect(weights.weight(of: "HeavyLib") == 60.5)
        #expect(weights.weight(of: "NoCompile") == 0)
        #expect(weights.weight(of: "Unknown") == 0)
    }

    @Test("weightsファイルの保存はソート済みで冪等、往復で値が保存される")
    func weightsFileRoundTripsIdempotently() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("target-weights-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("weights.yml")
        let weights = TargetWeights(seconds: ["Zeta": 1.5, "Alpha": 894.25])

        try weights.save(to: url)
        let first = try String(contentsOf: url, encoding: .utf8)
        try weights.save(to: url)
        let second = try String(contentsOf: url, encoding: .utf8)

        #expect(first == second)
        #expect(try TargetWeights.load(from: url).seconds == ["Zeta": 1.5, "Alpha": 894.25])
    }

    @Test("FeatureCostは閉包内のローカル重みと外部依存重みの和になる")
    func featureCostSumsClosureAndExternalWeights() async {
        let feature = target("HomeFeature")
        let model = target("SharedKit")
        let lean = target("LeanFeature")
        let graph = ModuleGraph(
            nodes: [feature, model, lean],
            edges: [feature: [model], lean: []],
            externalDependencies: [model: ["BigExternal"]],
            testTargets: [],
        )
        let weights = TargetWeights(seconds: [
            "HomeFeature": 5, "SharedKit": 10, "BigExternal": 400, "LeanFeature": 1,
        ])

        let costs = await BuildCostAnalyzer.costs(of: [feature, lean], graph: graph, weights: weights)

        // Heavy external leaking into the closure dominates the cost
        #expect(costs == [
            .init(target: "P/HomeFeature", cost: 415),
            .init(target: "P/LeanFeature", cost: 1),
        ])
    }
}
