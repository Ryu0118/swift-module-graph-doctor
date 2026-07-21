import Foundation
import ProcessRunning
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Abstracts the execution of `swift package describe`. Tests swap in a stub that returns fixture JSON
package protocol PackageDescribing: Sendable {
    /// Returns the describe JSON (`--type json`) for the package in the given directory
    func describe(packageDirectory: URL) async throws -> Data
}

/// Implementation that actually runs `swift package describe --type json`
package struct SwiftPackageDescriber: PackageDescribing {
    private let processRunner: any ProcessRunning

    /// Creates an instance with an injected process runner (defaults to real process execution)
    package init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Failure of the describe invocation
    package enum Error: Swift.Error, LocalizedError {
        /// Non-zero exit. Includes stderr contents
        case describeFailed(directory: String, exitCode: Int32, stderr: String)

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .describeFailed(directory, exitCode, stderr):
                "swift package describe failed at \(directory) (exit \(exitCode)): \(stderr)"
            }
        }
    }

    /// Runs `swift package describe --type json` in the target directory and returns stdout
    package func describe(packageDirectory: URL) async throws -> Data {
        // Running swift via xcrun respects xcode-select / DEVELOPER_DIR toolchain selection
        let result = try await processRunner.run(
            .path("/usr/bin/xcrun"),
            arguments: Arguments(["swift", "package", "describe", "--type", "json"]),
            environment: .inherit,
            workingDirectory: FilePath(packageDirectory.path(percentEncoded: false)),
            platformOptions: PlatformOptions(),
            input: .none,
            output: .bytes(limit: .max),
            error: .bytes(limit: .max),
        )

        switch result.terminationStatus {
        case let .exited(code) where code != 0:
            throw Error.describeFailed(
                directory: packageDirectory.path(percentEncoded: false),
                exitCode: code,
                stderr: String(bytes: result.standardError, encoding: .utf8) ?? "",
            )
        case .unhandledException:
            throw Error.describeFailed(
                directory: packageDirectory.path(percentEncoded: false),
                exitCode: -1,
                stderr: "Unhandled exception",
            )
        default:
            return Data(result.standardOutput)
        }
    }
}
