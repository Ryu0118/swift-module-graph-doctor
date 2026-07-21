import ArgumentParser
import ModuleGraphDoctorKit

/// Installs the bundled agent skill into an AI client's skill directory.
///
/// Thin argument mapper over `SkillInstaller` (which owns directory
/// resolution and idempotency); mirrors the `sim-use init` interface with
/// `--client`, `--dest`, `--print`, `--force`, and `--uninstall`
struct InstallSkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-skills",
        abstract: "Install the module-graph-doctor skill for AI clients (Claude Code, AGENTS-style)",
    )

    @Option(name: .customLong("client"), help: "Target client: auto, claude, or agents")
    var client: SkillInstaller.Client = .auto

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
        let installer = SkillInstaller()
        let outcome = if uninstall {
            try installer.uninstall(name: BundledSkill.name, client: client, destination: dest)
        } else {
            try installer.install(
                markdown: BundledSkill.markdown,
                name: BundledSkill.name,
                client: client,
                destination: dest,
                force: force,
            )
        }
        switch outcome {
        case let .installed(path):
            Log.logger.info("installed: \(path)")
        case let .alreadyInstalled(path):
            Log.logger.error("already installed at \(path) (use --force to overwrite)")
            throw ExitCode(1)
        case let .uninstalled(path):
            Log.logger.info("uninstalled: \(path)")
        case let .nothingToUninstall(path):
            Log.logger.info("nothing to uninstall at \(path)")
        }
    }
}

extension SkillInstaller.Client: ExpressibleByArgument {}
