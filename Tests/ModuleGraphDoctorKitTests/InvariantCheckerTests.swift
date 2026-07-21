import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct InvariantCheckerTests {
    @Test("deny DSLがエンジンのルールへ変換される")
    func parsesDenyDSL() throws {
        let configuration = Configuration(
            root: ["P/App"],
            lint: [
                .init(deny: "feature -> live"),
                .init(deny: "interface => sdk"),
                .init(deny: "* => heavy", allow: ["live", "app"]),
            ],
        )

        let rules = try InvariantChecker.makeRules(configuration: configuration)

        #expect(rules == [
            .forbidEdge(name: "feature -> live", from: "feature", to: "live"),
            .forbidReach(name: "interface => sdk", from: "interface", to: "sdk"),
            .forbidDependents(name: "* => heavy", heavy: "heavy", except: ["live", "app"]),
        ])
    }

    @Test("不正なdeny DSLはエラーになる")
    func malformedDSLThrows() {
        let cases = [
            Configuration(root: ["P/App"], lint: [.init(deny: "feature")]),
            Configuration(root: ["P/App"], lint: [.init(deny: "* -> live")]),
            Configuration(root: ["P/App"], lint: [.init(deny: "a -> b", allow: ["c"])]),
        ]
        for configuration in cases {
            #expect(throws: InvariantChecker.Error.self) {
                try InvariantChecker.makeRules(configuration: configuration)
            }
        }
    }

    @Test("layers/lint入りYAMLがデコードできる")
    func decodesLayersAndLintYAML() throws {
        let yaml = """
        root: MyApp/AppFeature
        layers:
          feature: "Feature$"
          app: [AppFeature]
          sdk: [SomeDatabaseSDK]
          heavy: 60
        lint:
          - deny: feature -> live
          - deny: "* => heavy"
            allow: [live, app]
        check:
          violationsBaseline: "custom-violations.yml"
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.layers?["feature"] == .regex("Feature$"))
        #expect(configuration.layers?["app"] == .names(["AppFeature"]))
        #expect(configuration.layers?["heavy"] == .weightAtLeast(60))
        #expect(configuration.lint?.count == 2)
        #expect(configuration.lint?[1].allow == ["live", "app"])
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
