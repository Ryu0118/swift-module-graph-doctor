@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct ConfigurationTests {
    @Test("全項目入りのYAMLをデコードできる")
    func decodesFullYAML() throws {
        let yaml = """
        packages:
          roots: ["Packages"]
          exclude: ["BinaryWrappers", "VendoredLib"]
        analysis:
          roots: ["MainApp/AppFeature"]
          costPerTarget: 0.629
          parallelism: 10
          topLoadCount: 20
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.packages.roots == ["Packages"])
        #expect(configuration.packages.exclude == ["BinaryWrappers", "VendoredLib"])
        #expect(configuration.analysis.roots == ["MainApp/AppFeature"])
        #expect(configuration.analysis.costPerTarget == 0.629)
        #expect(configuration.analysis.parallelism == 10)
        #expect(configuration.analysis.topLoadCount == 20)
    }

    @Test("オプション項目は省略できる")
    func optionalFieldsCanBeOmitted() throws {
        let yaml = """
        packages:
          roots: ["."]
        analysis:
          roots: ["App/AppFeature"]
        """

        let configuration = try Configuration.decode(yaml: yaml)

        #expect(configuration.packages.exclude == nil)
        #expect(configuration.analysis.costPerTarget == nil)
        #expect(configuration.analysis.parallelism == nil)
    }

    @Test("parseTargetIDはpackage/target形式のみ受け付ける")
    func parseTargetIDValidatesFormat() {
        #expect(
            Configuration.parseTargetID("MainApp/AppFeature")
                == TargetID(packageName: "MainApp", targetName: "AppFeature"),
        )
        #expect(Configuration.parseTargetID("NoSlash") == nil)
        #expect(Configuration.parseTargetID("/Empty") == nil)
        #expect(Configuration.parseTargetID("Empty/") == nil)
    }
}
