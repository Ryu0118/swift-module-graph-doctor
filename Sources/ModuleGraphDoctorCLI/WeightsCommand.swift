import ArgumentParser
import Foundation
import ModuleGraphDoctorKit

/// Generates the target weights file from an XCLogParser JSON build report.
/// Thin argument mapper over `WeightsRunner`
struct WeightsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "weights",
        abstract: "Generate target weights (seconds) from an XCLogParser --reporter json report",
    )

    @Option(name: [.customShort("c"), .customLong("config")], help: "Path to module-graph-doctor.yml")
    var configPath: String = "module-graph-doctor.yml"

    @Option(name: .customLong("log"), help: "Path to the XCLogParser --reporter json output")
    var logPath: String

    @Option(name: .customLong("output"), help: "Output path (defaults to the configured weights path)")
    var outputPath: String?

    func run() async throws {
        let configURL = URL(filePath: configPath)
        let configuration = try Configuration.loadOrDefault(from: configURL)
        let output = try WeightsRunner().run(
            configuration: configuration,
            baseDirectory: configURL.absoluteURL.deletingLastPathComponent(),
            logData: Data(contentsOf: URL(filePath: logPath)),
            outputOverride: outputPath,
        )
        Log.logger.info(
            "weights written: \(output.url.path(percentEncoded: false)) (\(output.targetCount) targets)",
        )
    }
}
