import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct GraphAssemblerTests {
    /// Mirrors the real case where the same target name (e.g. `AppFeature`) exists in
    /// two packages of one workspace (a main app package and a companion app package).
    /// Keying by name alone lets one overwrite the other and breaks the closure
    @Test("同名ターゲットを持つ2パッケージが別ノードとして合成される")
    func sameNamedTargetsInTwoPackagesStayDistinct() {
        let mainApp = DescribedPackage(
            name: "MainApp",
            products: [],
            targets: [
                .init(name: "AppFeature", type: "library", targetDependencies: ["FeatureA"]),
                .init(name: "FeatureA", type: "library"),
            ],
        )
        let companionApp = DescribedPackage(
            name: "CompanionApp",
            products: [],
            targets: [
                .init(name: "AppFeature", type: "library", targetDependencies: ["FeatureB"]),
                .init(name: "FeatureB", type: "library"),
            ],
        )

        let graph = GraphAssembler.assemble(packages: [mainApp, companionApp])

        let mainRoot = TargetID(packageName: "MainApp", targetName: "AppFeature")
        let companionRoot = TargetID(packageName: "CompanionApp", targetName: "AppFeature")
        #expect(graph.nodes.count == 4)
        #expect(graph.closure(of: mainRoot) == [
            mainRoot, TargetID(packageName: "MainApp", targetName: "FeatureA"),
        ])
        #expect(graph.closure(of: companionRoot) == [
            companionRoot, TargetID(packageName: "CompanionApp", targetName: "FeatureB"),
        ])
    }

    @Test("パッケージ跨ぎのproduct依存が構成ターゲットへの辺として解決される")
    func crossPackageProductDependencyResolvesToConstituentTargets() {
        let core = DescribedPackage(
            name: "Core",
            products: [.init(name: "SharedModel", targets: ["SharedModelCore", "SharedModelFirebase"])],
            targets: [
                .init(name: "SharedModelCore", type: "library"),
                .init(name: "SharedModelFirebase", type: "library"),
            ],
        )
        let app = DescribedPackage(
            name: "App",
            products: [],
            targets: [
                .init(name: "HomeFeature", type: "library", productDependencies: ["SharedModel"]),
            ],
        )

        let graph = GraphAssembler.assemble(packages: [core, app])

        let home = TargetID(packageName: "App", targetName: "HomeFeature")
        #expect(graph.dependencies(of: home) == [
            TargetID(packageName: "Core", targetName: "SharedModelCore"),
            TargetID(packageName: "Core", targetName: "SharedModelFirebase"),
        ])
        #expect(graph.externalDependencies[home] == nil)
    }

    @Test("byName形式のターゲット依存が同一パッケージ優先で解決され、無ければproductへフォールバックする")
    func byNameDependencyPrefersLocalTargetThenProduct() {
        let core = DescribedPackage(
            name: "Core",
            products: [.init(name: "Networking", targets: ["NetworkingImpl"])],
            targets: [.init(name: "NetworkingImpl", type: "library")],
        )
        let app = DescribedPackage(
            name: "App",
            products: [],
            targets: [
                // "Networking" does not exist in App -> falls back to Core's product
                .init(name: "Feature", type: "library", targetDependencies: ["Local", "Networking"]),
                .init(name: "Local", type: "library"),
            ],
        )

        let graph = GraphAssembler.assemble(packages: [core, app])

        #expect(graph.dependencies(of: TargetID(packageName: "App", targetName: "Feature")) == [
            TargetID(packageName: "App", targetName: "Local"),
            TargetID(packageName: "Core", targetName: "NetworkingImpl"),
        ])
    }

    @Test("解決できない依存は外部依存として記録され、辺にはならない")
    func unresolvedDependenciesAreRecordedAsExternal() {
        let app = DescribedPackage(
            name: "App",
            products: [],
            targets: [
                .init(
                    name: "Feature",
                    type: "library",
                    productDependencies: ["ComposableArchitecture", "FirebaseFirestore"],
                ),
            ],
        )

        let graph = GraphAssembler.assemble(packages: [app])

        let feature = TargetID(packageName: "App", targetName: "Feature")
        #expect(graph.dependencies(of: feature).isEmpty)
        #expect(graph.externalDependencies[feature] == ["ComposableArchitecture", "FirebaseFirestore"])
    }

    @Test("testターゲットはtestTargetsに分類され、閉包から除外される")
    func classifiesTestTargetsAndExcludesThemFromClosure() {
        let app = DescribedPackage(
            name: "App",
            products: [],
            targets: [
                .init(name: "Feature", type: "library"),
                .init(name: "FeatureTests", type: "test", targetDependencies: ["Feature"]),
            ],
        )

        let graph = GraphAssembler.assemble(packages: [app])

        let tests = TargetID(packageName: "App", targetName: "FeatureTests")
        #expect(graph.testTargets == [tests])
        #expect(graph.nonTestNodes == [TargetID(packageName: "App", targetName: "Feature")])
        #expect(graph.closure(of: tests).isEmpty)
    }

    @Test("実際のdescribe JSON形式（snake_caseキー）をデコードできる")
    func decodesRealDescribeJSONShape() throws {
        let json = """
        {
          "name": "Core",
          "products": [
            { "name": "SharedModel", "targets": ["SharedModel"], "type": { "library": ["automatic"] } }
          ],
          "targets": [
            {
              "name": "SharedModel",
              "type": "library",
              "c99name": "SharedModel",
              "module_type": "SwiftTarget",
              "path": "Sources/SharedModel",
              "sources": ["SharedModel.swift"],
              "target_dependencies": ["Extensions"],
              "product_dependencies": ["Dependencies"]
            },
            {
              "name": "Extensions",
              "type": "library",
              "c99name": "Extensions",
              "module_type": "SwiftTarget",
              "path": "Sources/Extensions",
              "sources": []
            }
          ]
        }
        """

        let package = try DescribedPackage.decode(from: Data(json.utf8))

        #expect(package.name == "Core")
        #expect(package.products.map(\.name) == ["SharedModel"])
        #expect(package.targets.count == 2)
        #expect(package.targets[0].targetDependencies == ["Extensions"])
        #expect(package.targets[0].productDependencies == ["Dependencies"])
        #expect(package.targets[1].targetDependencies == nil)
    }
}
