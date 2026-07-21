@testable import ModuleGraphDoctorKit
import ModuleGraphLint
import Testing

@Suite
struct ConfigurationTests {
    @Test("フラットスキーマの全項目入りYAMLをデコードできる")
    func decodesFullYAML() throws {
        let yaml = """
        root: [AppFeature, WidgetExtension]
        path: "MyPackages"
        exclude: [BinaryWrappers, VendoredLib]
        costPerTarget: 0.629
        cores: 10
        topCount: 20
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.root == ["AppFeature", "WidgetExtension"])
        #expect(configuration.path == ["MyPackages"])
        #expect(configuration.exclude == ["BinaryWrappers", "VendoredLib"])
        #expect(configuration.costPerTarget == 0.629)
        #expect(configuration.cores == 10)
        #expect(configuration.topCount == 20)
    }

    @Test("pathとrootは文字列でもリストでも書ける")
    func pathAndRootAcceptScalarOrList() throws {
        let scalar = try Configuration.decode(yaml: "root: AppFeature\npath: .")
        let list = try Configuration.decode(yaml: "root: [AppFeature]\npath: [\".\"]")

        #expect(scalar.root == ["AppFeature"])
        #expect(scalar.path == ["."])
        #expect(scalar.root == list.root)
        #expect(scalar.path == list.path)
    }

    @Test("空のYAMLでも全てデフォルトで成立する（ゼロコンフィグ）")
    func emptyYAMLFallsBackToDefaults() throws {
        let configuration = try Configuration.decode(yaml: "{}")

        #expect(configuration.path == ["."])
        #expect(configuration.root.isEmpty)
        #expect(configuration.exclude.isEmpty)
        #expect(configuration.costPerTarget == nil)
        #expect(configuration.cores == nil)
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
}
