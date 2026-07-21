import FileManagerProtocol
import Foundation

/// Enumerates package directories (those containing `Package.swift`) under scan roots.
///
/// This is the CLI's convenience layer over the kit's explicit-path API: the
/// configuration `path:` key may point at a package directory itself or at a
/// "package container" directory such as a workspace's `Packages/`. If the
/// root has a `Package.swift`, it is returned; otherwise the immediate
/// subdirectories (one level only) are examined. Hidden directories such as
/// `.build` are skipped.
package enum PackageLocator {
    /// Enumerates package directories under the scan roots (sorted, deduplicated)
    package static func locatePackages(
        under roots: [URL],
        fileManager: any FileManagerProtocol = FileManager.default,
    ) -> [URL] {
        var found: [URL] = []
        var seen: Set<String> = []

        for root in roots {
            for candidate in candidates(under: root, fileManager: fileManager) {
                let path = candidate.standardizedFileURL.path(percentEncoded: false)
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                found.append(candidate.standardizedFileURL)
            }
        }
        return found.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    private static func candidates(under root: URL, fileManager: any FileManagerProtocol) -> [URL] {
        if hasManifest(root, fileManager: fileManager) {
            return [root]
        }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }
        return entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && hasManifest(entry, fileManager: fileManager)
        }
    }

    private static func hasManifest(_ directory: URL, fileManager: any FileManagerProtocol) -> Bool {
        fileManager.fileExists(
            atPath: directory.appendingPathComponent("Package.swift").path(percentEncoded: false),
        )
    }
}
