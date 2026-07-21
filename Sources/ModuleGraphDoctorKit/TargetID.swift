/// Unique identifier for a target in a multi-package workspace.
///
/// Target names can collide across packages: the same target name (e.g.
/// `AppFeature`) can exist in two packages of one workspace (a main app package
/// and a companion app package), so keying by target name
/// alone lets one silently overwrite the other and corrupts the graph.
/// Always identify targets by the (packageName, targetName) composite key.
package struct TargetID: Hashable, Sendable {
    /// Name of the package the target belongs to (`name` in `Package.swift`)
    package let packageName: String
    /// Target name
    package let targetName: String

    /// Creates an identifier from a package name and a target name
    package init(packageName: String, targetName: String) {
        self.packageName = packageName
        self.targetName = targetName
    }
}

extension TargetID: CustomStringConvertible {
    /// Display string in `package/target` form
    package var description: String {
        "\(packageName)/\(targetName)"
    }
}

extension TargetID: Comparable {
    /// Orders by package name first, then by target name within the same package
    package static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.packageName, lhs.targetName) < (rhs.packageName, rhs.targetName)
    }
}
