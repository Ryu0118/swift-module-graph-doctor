import Foundation

/// How a layer's members are declared: a regex on the target name,
/// an exact name list (which also matches external products), or a
/// measured-weight threshold in seconds
package enum LayerSpec: Decodable, Sendable, Equatable {
    /// Regex matched against the target name
    case regex(String)
    /// Exact target names; also matches external product names
    case names([String])
    /// Every target whose measured weight is at least this many seconds
    case weightAtLeast(Double)

    /// Decodes from a string (regex), list (names), or number (seconds)
    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let names = try? container.decode([String].self) {
            self = .names(names)
        } else if let seconds = try? container.decode(Double.self) {
            self = .weightAtLeast(seconds)
        } else {
            self = try .regex(container.decode(String.self))
        }
    }
}

/// A lint rule. `deny` uses a tiny DSL over layer names:
/// `A -> B` forbids direct edges, `A => B` forbids transitive reachability,
/// and `* => B` with `allow:` restricts who may depend on B at all
package struct LintRule: Decodable, Sendable, Equatable {
    /// The denied relation, e.g. `feature -> live` or `interface => sdk`
    package let deny: String
    /// Layers still allowed to depend on the target of a `* => B` rule
    package let allow: [String]?

    /// Builds directly, for tests
    package init(deny: String, allow: [String]? = nil) {
        self.deny = deny
        self.allow = allow
    }
}
