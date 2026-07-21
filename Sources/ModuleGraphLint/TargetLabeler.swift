import Foundation
import ModuleGraphKit

/// Resolves layer membership for targets from the `layers:` configuration.
///
/// Precedence per target: exact names > regex > weight threshold. Within the
/// regex tier a target matching two different layers is a configuration error
/// (reported with the target and both layers) rather than being resolved by
/// declaration order -- YAML mapping order is not reliable, and silent
/// order-dependent resolution would be a trap
package struct TargetLabeler: Sendable {
    private let exactNames: [String: String]
    private let regexes: [(layer: String, regex: NSRegularExpression)]
    private let weightThresholds: [(layer: String, seconds: Double)]
    /// Exact names per layer; used to match external products (e.g. SDKs)
    package let externalNames: [String: Set<String>]

    /// Errors thrown while building or applying the layer configuration
    package enum Error: Swift.Error, LocalizedError, Equatable {
        /// A regex pattern failed to compile
        case invalidPattern(layer: String, pattern: String)
        /// A target matches two layers in the same tier
        case ambiguousLayer(target: String, layers: [String])

        /// Human-readable error message
        package var errorDescription: String? {
            switch self {
            case let .invalidPattern(layer, pattern):
                "layer '\(layer)' has an invalid regex: \(pattern)"
            case let .ambiguousLayer(target, layers):
                "target '\(target)' matches multiple layers (\(layers.joined(separator: ", "))); "
                    + "make the definitions unambiguous"
            }
        }
    }

    /// Builds a resolver from `layers:` (layer name -> spec)
    package init(layers: [String: LayerSpec]) throws {
        var exact: [String: String] = [:]
        var regexList: [(String, NSRegularExpression)] = []
        var thresholds: [(String, Double)] = []
        var externals: [String: Set<String>] = [:]

        for (layer, spec) in layers.sorted(by: { $0.key < $1.key }) {
            switch spec {
            case let .names(names):
                for name in names {
                    exact[name] = layer
                }
                externals[layer] = Set(names)
            case let .regex(pattern):
                guard let regex = try? NSRegularExpression(pattern: pattern) else {
                    throw Error.invalidPattern(layer: layer, pattern: pattern)
                }
                regexList.append((layer, regex))
            case let .weightAtLeast(seconds):
                thresholds.append((layer, seconds))
            }
        }
        exactNames = exact
        regexes = regexList
        weightThresholds = thresholds
        externalNames = externals
    }

    /// Resolves the layer of every target in `scope`. Unmatched targets are absent
    package func resolveLayers(
        for scope: Set<TargetID>,
        weights: TargetWeights?,
    ) throws -> [TargetID: String] {
        var resolved: [TargetID: String] = [:]
        for target in scope {
            if let layer = try layer(of: target, weights: weights) {
                resolved[target] = layer
            }
        }
        return resolved
    }

    private func layer(of target: TargetID, weights: TargetWeights?) throws -> String? {
        if let byFullName = exactNames[target.description] {
            return byFullName
        }
        if let byName = exactNames[target.targetName] {
            return byName
        }
        let name = target.targetName
        let range = NSRange(name.startIndex..., in: name)
        let regexMatches = regexes
            .filter { $0.regex.firstMatch(in: name, range: range) != nil }
            .map(\.layer)
        if regexMatches.count > 1 {
            throw Error.ambiguousLayer(target: target.description, layers: regexMatches.sorted())
        }
        if let layer = regexMatches.first {
            return layer
        }
        guard let weights else { return nil }
        let weightMatches = weightThresholds
            .filter { weights.weight(of: name) >= $0.seconds }
            .map(\.layer)
        if weightMatches.count > 1 {
            throw Error.ambiguousLayer(target: target.description, layers: weightMatches.sorted())
        }
        return weightMatches.first
    }
}
