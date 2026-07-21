import ModuleGraphDoctorCLI

@main
struct SwiftModuleGraphDoctor {
    static func main() async throws {
        await ModuleGraphDoctorCommand.main()
    }
}
