import ArgumentParser
import Foundation
import ModuleGraphDoctorKit
import ModuleGraphKit

/// Generates the target weights file from an XCLogParser JSON build report
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
        let baseDirectory = configURL.absoluteURL.deletingLastPathComponent()

        let data = try Data(contentsOf: URL(filePath: logPath))
        let weights = try WeightsGenerator.generate(fromXCLogParserJSON: data)

        let rawOutput = outputPath ?? configuration.weights ?? "weights.yml"
        let outputURL = rawOutput.hasPrefix("/")
            ? URL(filePath: rawOutput)
            : baseDirectory.appendingPathComponent(rawOutput)
        try weights.save(to: outputURL)
        print("weights written: \(outputURL.path(percentEncoded: false)) (\(weights.seconds.count) targets)")
    }
}
