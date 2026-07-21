import ArgumentParser

/// Root command of swift-module-graph-doctor.
/// Subcommands (diagnose / check / weights) are added as each issue is implemented.
public struct ModuleGraphDoctorCommand: AsyncParsableCommand {
    /// Command configuration. Subcommands are added when each feature is implemented
    public static let configuration = CommandConfiguration(
        commandName: "swift-module-graph-doctor",
        abstract: "Diagnose and gate Swift package module graphs",
        discussion: """
        Analyzes target-level dependency graphs across multiple Swift packages, \
        reports work-span metrics (critical path, parallel width, simulated makespan), \
        and gates regressions against a committed baseline.
        """,
        version: Self.version,
        subcommands: [DiagnoseCommand.self, CheckCommand.self, WeightsCommand.self, InstallSkillsCommand.self],
    )

    /// Tool version. Keep in sync with the release tag
    public static let version = "0.1.0"

    /// Default initializer required by ArgumentParser
    public init() {}
}
