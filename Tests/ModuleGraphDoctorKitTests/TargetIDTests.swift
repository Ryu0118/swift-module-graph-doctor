@testable import ModuleGraphDoctorKit
@testable import ModuleGraphKit
import Testing

@Suite
struct TargetIDTests {
    @Test("同名ターゲットでもパッケージが異なれば別物として区別される")
    func sameTargetNameInDifferentPackagesAreDistinct() {
        let app = TargetID(packageName: "MainApp", targetName: "AppFeature")
        let companionApp = TargetID(packageName: "CompanionApp", targetName: "AppFeature")

        #expect(app != companionApp)
        #expect(Set([app, companionApp]).count == 2)
    }

    @Test("descriptionはpackage/target形式")
    func descriptionFormat() {
        let id = TargetID(packageName: "Core", targetName: "SharedModel")

        #expect(id.description == "Core/SharedModel")
    }

    @Test("Comparableはパッケージ名優先、同一パッケージ内はターゲット名で比較する")
    func comparableOrdersByPackageThenTarget() {
        let first = TargetID(packageName: "A", targetName: "Z")
        let second = TargetID(packageName: "B", targetName: "A")
        let third = TargetID(packageName: "B", targetName: "B")

        #expect([third, second, first].sorted() == [first, second, third])
    }
}
