import Foundation
@testable import ModuleGraphDoctorCLI
import Testing

@Suite
struct BundledSkillSyncTests {
    @Test("埋め込みskillはskills/module-graph-doctor/SKILL.mdと完全一致する")
    func embeddedSkillMatchesRepositoryFile() throws {
        // Tests/ModuleGraphDoctorCLITests/BundledSkillSyncTests.swift -> repo root
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let skillFile = repoRoot
            .appendingPathComponent("skills/module-graph-doctor/SKILL.md")

        let onDisk = try String(contentsOf: skillFile, encoding: .utf8)

        #expect(
            BundledSkill.markdown == onDisk,
            "SKILL.md and the embedded copy diverged; regenerate BundledSkill.swift from the file",
        )
    }
}
