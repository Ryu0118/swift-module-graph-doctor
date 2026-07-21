import Foundation

/// Assigns architecture-layer labels to targets.
///
/// Resolution order (first match wins):
/// 1. Explicit per-target labels (e.g. `SharedModel: model`)
/// 2. Regex rules evaluated in declaration order (e.g. `(Client|UseCase)Live$ -> live`)
/// 3. Unlabeled targets stay label-less; rules simply do not match them.
///
/// External products (dependencies not resolved to local targets) are labeled
/// separately via the `sdk` name list, so rules like `forbid-reach: interface -> sdk`
/// can gate transitive leaks of external SDKs.
package struct TargetLabeler: Sendable {
    /// A single regex labeling rule
    package struct RegexRule: Sendable {
        /// Regular expression matched against the target name
        package let pattern: String
        /// Label assigned on match
        package let label: String

        /// Creates a rule from a pattern and label
        package init(pattern: String, label: String) {
            self.pattern = pattern
            self.label = label
        }
    }

    private let explicit: [String: String]
    private let regexRules: [(NSRegularExpression, String)]
    private let sdkProducts: Set<String>

    /// Errors thrown while building the labeler
    package enum Error: Swift.Error, LocalizedError {
        /// A regex pattern failed to compile
        case invalidPattern(String)

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .invalidPattern(pattern): "invalid label regex pattern: \(pattern)"
            }
        }
    }

    /// Builds a labeler. `explicit` maps target names (or `package/target`) to labels;
    /// `sdkProducts` lists external product names to label as SDKs
    package init(
        explicit: [String: String],
        regexRules: [RegexRule],
        sdkProducts: Set<String>,
    ) throws {
        self.explicit = explicit
        self.regexRules = try regexRules.map { rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else {
                throw Error.invalidPattern(rule.pattern)
            }
            return (regex, rule.label)
        }
        self.sdkProducts = sdkProducts
    }

    /// Returns the label for a local target, or nil when nothing matches
    package func label(of target: TargetID) -> String? {
        if let byFullName = explicit[target.description] {
            return byFullName
        }
        if let byName = explicit[target.targetName] {
            return byName
        }
        for (regex, label) in regexRules {
            let range = NSRange(target.targetName.startIndex..., in: target.targetName)
            if regex.firstMatch(in: target.targetName, range: range) != nil {
                return label
            }
        }
        return nil
    }

    /// Whether an external product name is labeled as an SDK
    package func isSDK(externalProduct: String) -> Bool {
        sdkProducts.contains(externalProduct)
    }
}
