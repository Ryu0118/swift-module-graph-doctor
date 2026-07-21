import ArgumentParser
import Foundation
import ModuleGraphDoctorKit

/// Subcommand that computes and reports work-span metrics from the dependency graph
struct DiagnoseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Analyze the module graph and report work-span metrics",
    )

    @Option(name: [.customShort("c"), .customLong("config")], help: "Path to module-graph-doctor.yml")
    var configPath: String = "module-graph-doctor.yml"

    @Option(help: "Output format: text or json")
    var format: OutputFormat = .text

    enum OutputFormat: String, ExpressibleByArgument {
        case text
        case json
    }

    func run() async throws {
        let configURL = URL(filePath: configPath)
        let configuration = try Configuration.loadOrDefault(from: configURL)
        let baseDirectory = configURL.absoluteURL.deletingLastPathComponent()

        let report = try await DiagnoseRunner().run(
            configuration: configuration,
            baseDirectory: baseDirectory,
        )

        switch format {
        case .text:
            print(DiagnoseReportRenderer.text(report))
        case .json:
            try print(DiagnoseReportRenderer.json(report))
        }
    }
}
