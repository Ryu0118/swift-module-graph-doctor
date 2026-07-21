import ArgumentParser
import FileManagerProtocol
import Foundation

/// Installs the bundled agent skill into an AI client's skill directory.
///
/// Mirrors the `sim-use init` interface: pick a client (or auto-detect),
/// write `SKILL.md` into its skills directory, and support `--print`,
/// `--force`, and `--uninstall`.
struct InstallSkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-skills",
        abstract: "Install the module-graph-doctor skill for AI clients (Claude Code, AGENTS-style)",
    )

    enum Client: String, ExpressibleByArgument {
        case auto
        case claude
        case agents
    }

    @Option(name: .customLong("client"), help: "Target client: auto, claude, or agents")
    var client: Client = .auto

    @Option(name: .customLong("dest"), help: "Custom skills directory (overrides --client)")
    var dest: String?

    @Flag(name: .customLong("force"), help: "Overwrite an existing installation")
    var force = false

    @Flag(name: .customLong("uninstall"), help: "Remove the installed skill instead of installing")
    var uninstall = false

    @Flag(name: .customLong("print"), help: "Print the skill markdown to stdout and exit")
    var printOnly = false

    func run() async throws {
        if printOnly {
            print(BundledSkill.markdown)
            return
        }
        let fileManager: any FileManagerProtocol = FileManager.default
        let skillDirectory = try resolveSkillsDirectory(fileManager: fileManager)
            .appendingPathComponent(BundledSkill.name)
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        let path = skillFile.path(percentEncoded: false)

        if uninstall {
            guard fileManager.fileExists(atPath: skillDirectory.path(percentEncoded: false)) else {
                print("nothing to uninstall at \(path)")
                return
            }
            try fileManager.removeItem(at: skillDirectory)
            print("uninstalled: \(path)")
            return
        }

        if fileManager.fileExists(atPath: path), !force {
            print("already installed at \(path) (use --force to overwrite)")
            throw ExitCode(1)
        }
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try BundledSkill.markdown.write(to: skillFile, atomically: true, encoding: .utf8)
        print("installed: \(path)")
    }

    /// `claude` -> ~/.claude/skills, `agents` -> ~/.agents/skills,
    /// `auto` -> whichever client directory exists (claude wins)
    private func resolveSkillsDirectory(fileManager: any FileManagerProtocol) throws -> URL {
        if let dest {
            return URL(filePath: dest)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claude = home.appendingPathComponent(".claude/skills")
        let agents = home.appendingPathComponent(".agents/skills")
        switch client {
        case .claude:
            return claude
        case .agents:
            return agents
        case .auto:
            let hasAgents = fileManager.fileExists(
                atPath: home.appendingPathComponent(".agents").path(percentEncoded: false),
            )
            let hasClaude = fileManager.fileExists(
                atPath: home.appendingPathComponent(".claude").path(percentEncoded: false),
            )
            return hasClaude || !hasAgents ? claude : agents
        }
    }
}
