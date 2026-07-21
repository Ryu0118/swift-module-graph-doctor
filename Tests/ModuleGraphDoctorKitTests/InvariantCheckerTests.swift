import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct InvariantCheckerTests {
    @Test("設定のinvariants節がエンジンのルールへ変換される")
    func convertsSpecsToRules() throws {
        let configuration = Configuration(
            root: ["P/App"],
            invariants: [
                .init(name: "feature-no-live", forbidEdge: .init(from: "feature", to: "live")),
                .init(name: "interface-no-sdk", forbidReach: .init(from: "interface", to: "sdk")),
                .init(name: "heavy-confined", forbidDependents: .init(of: "heavy", except: ["live"])),
            ],
        )

        let rules = try InvariantChecker.makeRules(configuration: configuration)

        #expect(rules == [
            .forbidEdge(name: "feature-no-live", from: "feature", to: "live"),
            .forbidReach(name: "interface-no-sdk", from: "interface", to: "sdk"),
            .forbidDependents(name: "heavy-confined", heavy: "heavy", except: ["live"]),
        ])
    }

    @Test("ルール本体が0個または2個以上のinvariantはエラーになる")
    func ambiguousSpecThrows() {
        let empty = Configuration(
            root: ["P/App"],
            invariants: [.init(name: "broken")],
        )
        let double = Configuration(
            root: ["P/App"],
            invariants: [.init(
                name: "broken",
                forbidEdge: .init(from: "a", to: "b"),
                forbidReach: .init(from: "a", to: "b"),
            )],
        )

        #expect(throws: InvariantChecker.Error.self) {
            try InvariantChecker.makeRules(configuration: empty)
        }
        #expect(throws: InvariantChecker.Error.self) {
            try InvariantChecker.makeRules(configuration: double)
        }
    }

    @Test("labels/invariants入りYAMLがデコードできる")
    func decodesLabelsAndInvariantsYAML() throws {
        let yaml = """
        root: MyApp/AppFeature
        labels:
          explicit:
            SharedKit: model
          rules:
            - { pattern: "Feature$", label: feature }
            - { pattern: "(Client|UseCase)Live$", label: live }
          sdk: ["SomeDatabaseSDK"]
        invariants:
          - name: feature-no-live
            forbidEdge: { from: feature, to: live }
        check:
          violationsBaseline: "custom-violations.yml"
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.labels?.explicit == ["SharedKit": "model"])
        #expect(configuration.labels?.rules?.count == 2)
        #expect(configuration.labels?.sdk == ["SomeDatabaseSDK"])
        #expect(configuration.invariants?.first?.name == "feature-no-live")
        #expect(configuration.check?.violationsBaseline == "custom-violations.yml")
    }

    @Test("違反baselineの保存はソート済みで冪等、未存在ファイルは空集合を返す")
    func violationsBaselineRoundTripsAndDefaultsToEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("invariant-checker-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("violations-baseline.yml")

        #expect(try InvariantChecker.ViolationsBaseline.load(from: url).isEmpty)

        let keys: Set = ["rule: B/x -> B/y", "rule: A/x -> A/y"]
        try InvariantChecker.ViolationsBaseline.save(keys, to: url)
        let first = try String(contentsOf: url, encoding: .utf8)
        try InvariantChecker.ViolationsBaseline.save(keys, to: url)
        let second = try String(contentsOf: url, encoding: .utf8)

        #expect(first == second)
        #expect(try InvariantChecker.ViolationsBaseline.load(from: url) == keys)
    }
}
