import Foundation

/// Model of the parts of `swift package describe --type json` output needed for graph assembly
package struct DescribedPackage: Decodable, Sendable {
    /// Package name (`name` in `Package.swift`)
    package let name: String
    /// Products the package exposes
    package let products: [Product]
    /// Targets in the package
    package let targets: [Target]

    /// A product declaration. A product consists of one or more targets
    package struct Product: Decodable, Sendable {
        /// Product name
        package let name: String
        /// Names of the targets that make up the product
        package let targets: [String]

        /// Builds a product directly, for tests
        package init(name: String, targets: [String]) {
            self.name = name
            self.targets = targets
        }
    }

    /// A target declaration
    package struct Target: Decodable, Sendable {
        /// Target name
        package let name: String
        /// Target type (`library` / `executable` / `test` / `macro`, etc.)
        package let type: String
        /// Target source path relative to the package directory (e.g. `Sources/SharedModel`)
        package let path: String?
        /// Source file paths within the target (relative to `path`)
        package let sources: [String]?
        /// Target dependencies within the same package (`swift package describe` returns target names only)
        package let targetDependencies: [String]?
        /// Product dependencies (cross-package; `swift package describe` returns product names only)
        package let productDependencies: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case type
            case path
            case sources
            case targetDependencies = "target_dependencies"
            case productDependencies = "product_dependencies"
        }

        /// Builds a target directly, for tests
        package init(
            name: String,
            type: String,
            path: String? = nil,
            sources: [String]? = nil,
            targetDependencies: [String]? = nil,
            productDependencies: [String]? = nil,
        ) {
            self.name = name
            self.type = type
            self.path = path
            self.sources = sources
            self.targetDependencies = targetDependencies
            self.productDependencies = productDependencies
        }
    }

    /// Builds a package directly, for tests
    package init(name: String, products: [Product], targets: [Target]) {
        self.name = name
        self.products = products
        self.targets = targets
    }

    /// Decodes from describe output JSON data
    package static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
