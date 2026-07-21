import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct WeightsRunnerTests {
    private let logJSON = """
    {
      "title": "Build",
      "type": "main",
      "duration": 100.0,
      "subSteps": [
        {
          "title": "Build target Foo",
          "type": "target",
          "duration": 60.0,
          "subSteps": [
            { "title": "Compile A.swift", "type": "detail", "duration": 40.0, "subSteps": [] }
          ]
        }
      ]
    }
    """

    @Test("default出力は<base>/.module-graph-doctor/weights.ymlで、ディレクトリごと生成される")
    func defaultPathCreatesToolDirectory() throws {
        let base = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("weights-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let output = try WeightsRunner().run(
            configuration: Configuration(),
            baseDirectory: base,
            logData: Data(logJSON.utf8),
            outputOverride: nil,
        )

        let expected = base.appendingPathComponent(".module-graph-doctor/weights.yml")
        #expect(output.url.path(percentEncoded: false) == expected.path(percentEncoded: false))
        #expect(output.targetCount == 1)
        let written = try String(contentsOf: expected, encoding: .utf8)
        #expect(written == "Foo: 40.000\n")
    }

    @Test("outputOverrideはconfigured pathより優先される")
    func overrideWinsOverConfiguration() throws {
        let base = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("weights-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let output = try WeightsRunner().run(
            configuration: Configuration(weights: "configured.yml"),
            baseDirectory: base,
            logData: Data(logJSON.utf8),
            outputOverride: "override.yml",
        )

        #expect(output.url.lastPathComponent == "override.yml")
    }
}
