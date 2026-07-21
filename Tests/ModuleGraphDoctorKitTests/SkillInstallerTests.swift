import Foundation
@testable import ModuleGraphDoctorKit
import Testing

@Suite
struct SkillInstallerTests {
    private let home: URL

    init() throws {
        home = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("skill-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    private func installer() -> SkillInstaller {
        SkillInstaller(homeDirectory: home)
    }

    @Test("install→already→force→uninstall→nothingの全遷移")
    func fullLifecycle() throws {
        let expected = home.appendingPathComponent(".claude/skills/doc/SKILL.md")
            .path(percentEncoded: false)

        let first = try installer().install(
            markdown: "# skill", name: "doc", client: .claude, destination: nil, force: false,
        )

        #expect(first == .installed(path: expected))
        #expect(try String(contentsOfFile: expected, encoding: .utf8) == "# skill")

        let second = try installer().install(
            markdown: "# skill", name: "doc", client: .claude, destination: nil, force: false,
        )

        #expect(second == .alreadyInstalled(path: expected))

        let forced = try installer().install(
            markdown: "# v2", name: "doc", client: .claude, destination: nil, force: true,
        )

        #expect(forced == .installed(path: expected))
        #expect(try String(contentsOfFile: expected, encoding: .utf8) == "# v2")

        let removed = try installer().uninstall(name: "doc", client: .claude, destination: nil)

        if case .uninstalled = removed {} else {
            Issue.record("expected .uninstalled, got \(removed)")
        }

        let again = try installer().uninstall(name: "doc", client: .claude, destination: nil)

        if case .nothingToUninstall = again {
        } else {
            Issue.record("expected .nothingToUninstall, got \(again)")
        }
    }

    @Test("auto解決: .claude存在→claude / .agentsのみ→agents / どちらも無し→claude")
    func autoResolution() throws {
        // Neither directory exists: claude is the default
        let fresh = try installer().install(
            markdown: "m", name: "s", client: .auto, destination: nil, force: false,
        )

        #expect(fresh == .installed(
            path: home.appendingPathComponent(".claude/skills/s/SKILL.md").path(percentEncoded: false),
        ))
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude"))

        // Only .agents exists: agents wins
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".agents"), withIntermediateDirectories: true,
        )
        let agentsOnly = try installer().install(
            markdown: "m", name: "s", client: .auto, destination: nil, force: false,
        )

        #expect(agentsOnly == .installed(
            path: home.appendingPathComponent(".agents/skills/s/SKILL.md").path(percentEncoded: false),
        ))

        // Both exist: claude wins the tie
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true,
        )
        let both = try installer().install(
            markdown: "m", name: "s", client: .auto, destination: nil, force: false,
        )

        #expect(both == .installed(
            path: home.appendingPathComponent(".claude/skills/s/SKILL.md").path(percentEncoded: false),
        ))
    }

    @Test("destはclientより優先される")
    func destinationOverridesClient() throws {
        let dest = home.appendingPathComponent("custom").path(percentEncoded: false)

        let outcome = try installer().install(
            markdown: "m", name: "s", client: .claude, destination: dest, force: false,
        )

        #expect(outcome == .installed(path: dest + "/s/SKILL.md"))
    }
}
