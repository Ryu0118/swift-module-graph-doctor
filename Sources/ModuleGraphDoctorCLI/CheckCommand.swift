import ArgumentParser
import Foundation
import ModuleGraphDoctorKit

/// Gates module-graph regressions against a committed baseline
struct CheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Compare the module graph against the committed baseline and fail on regressions",
    )

    @Option(name: [.customShort("c"), .customLong("config")], help: "Path to module-graph-doctor.yml")
    var configPath: String = "module-graph-doctor.yml"

    @Flag(name: .customLong("update-baseline"), help: "Rewrite the baseline with the current graph")
    var updateBaseline = false

    func run() async throws {
        let configURL = URL(filePath: configPath)
        let configuration = try Configuration.loadOrDefault(from: configURL)
        let baseDirectory = configURL.absoluteURL.deletingLastPathComponent()
        let runner = CheckRunner()

        if updateBaseline {
            let url = try await runner.updateBaseline(
                configuration: configuration,
                baseDirectory: baseDirectory,
            )
            print("baseline updated: \(url.path(percentEncoded: false))")
            return
        }

        let result = try await runner.run(configuration: configuration, baseDirectory: baseDirectory)
        if result.findings.isEmpty {
            print("module graph check passed: no changes against baseline")
            return
        }
        for finding in result.findings {
            print("[\(finding.severity.rawValue)] \(finding.message)")
        }
        if result.hasError {
            throw ExitCode(1)
        }
    }
}
