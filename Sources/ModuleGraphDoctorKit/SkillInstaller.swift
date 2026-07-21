import FileManagerProtocol
import Foundation

/// Installs a bundled agent skill into an AI client's skills directory.
///
/// All decisions live here so the CLI command stays a thin argument mapper:
/// directory resolution (`claude` -> ~/.claude/skills, `agents` ->
/// ~/.agents/skills, `auto` -> whichever client directory exists, claude
/// winning ties), idempotency, and uninstall
package struct SkillInstaller {
    /// Target client kind for skill installation
    package enum Client: String, Sendable {
        /// Whichever client directory exists (claude wins ties)
        case auto
        /// Claude Code (~/.claude/skills)
        case claude
        /// AGENTS-style clients (~/.agents/skills)
        case agents
    }

    /// Outcome of an install or uninstall, for the CLI to report
    package enum Outcome: Equatable, Sendable {
        /// The skill was written to this path
        case installed(path: String)
        /// The skill already exists at this path and `force` was false
        case alreadyInstalled(path: String)
        /// The skill was removed from this path
        case uninstalled(path: String)
        /// Nothing was installed at this path
        case nothingToUninstall(path: String)
    }

    private let fileManager: any FileManagerProtocol
    private let homeDirectory: URL

    /// Creates an installer rooted at the given home directory
    package init(
        fileManager: any FileManagerProtocol = FileManager.default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    /// Writes `markdown` as `<skills dir>/<name>/SKILL.md`
    package func install(
        markdown: String,
        name: String,
        client: Client,
        destination: String?,
        force: Bool,
    ) throws -> Outcome {
        let directory = skillDirectory(name: name, client: client, destination: destination)
        let file = directory.appendingPathComponent("SKILL.md")
        let path = file.path(percentEncoded: false)
        if fileManager.fileExists(atPath: path), !force {
            return .alreadyInstalled(path: path)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try markdown.write(to: file, atomically: true, encoding: .utf8)
        return .installed(path: path)
    }

    /// Removes the installed skill directory
    package func uninstall(
        name: String,
        client: Client,
        destination: String?,
    ) throws -> Outcome {
        let directory = skillDirectory(name: name, client: client, destination: destination)
        let path = directory.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else {
            return .nothingToUninstall(path: path)
        }
        try fileManager.removeItem(at: directory)
        return .uninstalled(path: path)
    }

    private func skillDirectory(name: String, client: Client, destination: String?) -> URL {
        if let destination {
            return URL(filePath: destination).appendingPathComponent(name)
        }
        let claude = homeDirectory.appendingPathComponent(".claude/skills")
        let agents = homeDirectory.appendingPathComponent(".agents/skills")
        let base = switch client {
        case .claude: claude
        case .agents: agents
        case .auto: resolveAuto(claude: claude, agents: agents)
        }
        return base.appendingPathComponent(name)
    }

    private func resolveAuto(claude: URL, agents: URL) -> URL {
        let hasAgents = fileManager.fileExists(
            atPath: homeDirectory.appendingPathComponent(".agents").path(percentEncoded: false),
        )
        let hasClaude = fileManager.fileExists(
            atPath: homeDirectory.appendingPathComponent(".claude").path(percentEncoded: false),
        )
        return hasClaude || !hasAgents ? claude : agents
    }
}
