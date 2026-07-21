import Foundation
@testable import ModuleGraphDoctorKit
import Testing

/// Smoke tests against a real repository.
///
/// Runs only when the environment variables `SMGD_SMOKE_PACKAGES_ROOT` (path to
/// the package container directory) and `SMGD_SMOKE_ROOT_TARGET` (root in
/// `<package>/<target>` form) are set. `SMGD_SMOKE_EXCLUDE_DIRS` (comma-separated
/// directory names) can exclude packages that are never source-built, such as
/// Scipio wrapper packages (which re-export Firebase etc. as local products and
/// would otherwise pollute the closure) and vendor code.
/// Real-graph values change as the repository evolves, so exact values are not
/// pinned; only lower bounds on scale are asserted and measured values are
/// printed (exact values are checked in the run log).
@Suite
struct RealRepositorySmokeTests {
    private static var packagesRoot: String? {
        ProcessInfo.processInfo.environment["SMGD_SMOKE_PACKAGES_ROOT"]
    }

    @Test(
        "実リポジトリからグラフを抽出しrootの閉包と最長路を出力する",
        .enabled(if: packagesRoot != nil),
    )
    func extractsRealRepositoryGraph() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try #require(Self.packagesRoot)
        let rootTarget = try #require(environment["SMGD_SMOKE_ROOT_TARGET"])
        let parts = rootTarget.split(separator: "/", maxSplits: 1).map(String.init)
        try #require(parts.count == 2)
        let rootID = TargetID(packageName: parts[0], targetName: parts[1])

        let excludedDirectories = Set(
            (environment["SMGD_SMOKE_EXCLUDE_DIRS"] ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
        )
        let directories = PackageLocator.locatePackages(under: [URL(filePath: root)])
            .filter { !excludedDirectories.contains($0.lastPathComponent) }

        let graph = try await GraphExtractor().extract(packageDirectories: directories)
        let closure = graph.closure(of: rootID)
        let longest = graph.longestPath(within: closure)

        print("SMOKE: total nodes=\(graph.nodes.count) (test targets=\(graph.testTargets.count))")
        print("SMOKE: closure of \(rootID) = \(closure.count) targets")
        print("SMOKE: longest chain depth=\(longest.depth)")
        print("SMOKE: path=\(longest.path.map(\.targetName).joined(separator: " -> "))")

        #expect(closure.contains(rootID))
        #expect(closure.count > 100)
        #expect(longest.depth >= 15)
    }
}
