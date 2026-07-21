import ArgumentParser
@testable import ModuleGraphDoctorCLI
import Testing

@Suite
struct ModuleGraphDoctorCommandTests {
    @Test("バージョン文字列はsemver形式")
    func versionIsSemver() {
        let components = ModuleGraphDoctorCommand.version.split(separator: ".")

        #expect(components.count == 3)
        #expect(components.allSatisfy { Int($0) != nil })
    }
}
