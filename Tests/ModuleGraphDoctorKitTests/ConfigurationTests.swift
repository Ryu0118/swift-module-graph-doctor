@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct ConfigurationTests {
    @Test("フラットスキーマの全項目入りYAMLをデコードできる")
    func decodesFullYAML() throws {
        let yaml = """
        root: [AppFeature, WidgetExtension]
        packagePath: "MyPackages"
        exclude: [BinaryWrappers, VendoredLib]
        costPerTarget: 0.629
        cores: 10
        topCount: 20
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.root == ["AppFeature", "WidgetExtension"])
        #expect(configuration.packagePath == ["MyPackages"])
        #expect(configuration.exclude == ["BinaryWrappers", "VendoredLib"])
        #expect(configuration.costPerTarget == 0.629)
        #expect(configuration.cores == 10)
        #expect(configuration.topCount == 20)
    }

    @Test("packagePathとrootは文字列でもリストでも書ける")
    func packagePathAndRootAcceptScalarOrList() throws {
        let scalar = try Configuration.decode(yaml: "root: AppFeature\npackagePath: .")
        let list = try Configuration.decode(yaml: "root: [AppFeature]\npackagePath: [\".\"]")

        #expect(scalar.root == ["AppFeature"])
        #expect(scalar.packagePath == ["."])
        #expect(scalar.root == list.root)
        #expect(scalar.packagePath == list.packagePath)
    }

    @Test("空のYAMLでも全てデフォルトで成立する（ゼロコンフィグ）")
    func emptyYAMLFallsBackToDefaults() throws {
        let configuration = try Configuration.decode(yaml: "{}")

        #expect(configuration.packagePath == ["."])
        #expect(configuration.root.isEmpty)
        #expect(configuration.exclude.isEmpty)
        #expect(configuration.costPerTarget == nil)
        #expect(configuration.cores == nil)
    }
}
