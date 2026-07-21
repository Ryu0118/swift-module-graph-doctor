@testable import ModuleGraphDoctorKit
@testable import ModuleGraphKit
import Testing

@Suite
struct ImportScannerTests {
    @Test("修飾なしimportとpublic importはインターフェース露出、internal等は非露出")
    func classifiesAccessLevels() {
        let source = """
        import Foundation
        public import SwiftUI
        internal import FirebaseFirestore
        package import SharedKit
        private import SecretKit
        """

        let scanned = ImportScanner.scan(source: source)

        #expect(scanned == [
            .init(module: "Foundation", isInterfaceVisible: true),
            .init(module: "SwiftUI", isInterfaceVisible: true),
            .init(module: "FirebaseFirestore", isInterfaceVisible: false),
            .init(module: "SharedKit", isInterfaceVisible: false),
            .init(module: "SecretKit", isInterfaceVisible: false),
        ])
    }

    @Test("属性付きimport（@preconcurrency / @testable / @_exported）もモジュール名を拾う")
    func handlesAttributedImports() {
        let source = """
        @preconcurrency import FirebaseRemoteConfig
        @preconcurrency internal import FirebaseAuth
        @_exported import SharedEntity
        @testable import MyModule
        """

        let scanned = ImportScanner.scan(source: source)

        #expect(scanned == [
            .init(module: "FirebaseRemoteConfig", isInterfaceVisible: true),
            .init(module: "FirebaseAuth", isInterfaceVisible: false),
            .init(module: "SharedEntity", isInterfaceVisible: true),
            .init(module: "MyModule", isInterfaceVisible: true),
        ])
    }

    @Test("サブモジュールimportと宣言種別importはトップモジュール名に正規化される")
    func normalizesSubmoduleAndKindImports() {
        let source = """
        import UIKit.UIView
        import func Darwin.exit
        """

        let scanned = ImportScanner.scan(source: source)

        #expect(scanned.map(\.module) == ["UIKit", "Darwin"])
    }

    @Test("import文以外の行（コメント・文字列中）からは抽出しない")
    func ignoresNonImportLines() {
        let source = """
        // import Commented
        let text = "import NotReal"
        func doImport() {}
        """

        let scanned = ImportScanner.scan(source: source)

        #expect(scanned.isEmpty)
    }
}
