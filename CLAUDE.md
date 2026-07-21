# swift-module-graph-doctor

Swiftパッケージ群のモジュール依存グラフを静的解析するCLI。(1) work-spanモデル（Graham限界 `makespan >= max(T_inf, T_1/p)`）に基づく診断レポート（`diagnose`）と、(2) baseline突合・アーキテクチャ不変条項による後退防止ゲート（`check`）を提供する。

初期ユースケースは大規模なマルチパッケージ構成のiOSワークスペース。設計の背景・各機能の仕様はこのリポジトリのIssue #1〜#7に記録されている。

## Directory Structure

| Path | Purpose |
|------|---------|
| `Sources/swift-module-graph-doctor/` | Entry point only - just calls ModuleGraphDoctorCLI |
| `Sources/ModuleGraphDoctorCLI/` | CLI command definitions (ArgumentParser). Thin layer, no business logic |
| `Sources/ModuleGraphDoctorKit/` | **All implementation**. Graph extraction, metrics, rule evaluation |
| `Tests/ModuleGraphDoctorCLITests/` | CLI module unit tests |
| `Tests/ModuleGraphDoctorKitTests/` | Kit unit tests |

## Naming Conventions

| Pattern | Purpose |
|---------|---------|
| `*Runner.swift` | Command execution logic |
| `*Validator.swift` | Input validation before running |

## Commands

タスクランナーはmise（`.mise.toml`）。Makefileは置かない。

| Command | Purpose |
|---------|---------|
| `mise run setup` | ツール導入 + git hooks設定 |
| `mise run check` | lint + docsync の一括チェック（コミット前に実行） |
| `mise run format` | SwiftFormatでフォーマット |
| `mise run lint` | format差分 + SwiftLint --strict + AST lint |
| `mise run test` | `swift test` |

## Notes

- Swift 6.2 / macOS 26+
- Use `package` access modifier for cross-module types
- コメントはすべて英語で書く。public/package宣言にはdoc comment必須（AST lintが強制）。work-spanモデルに触れるコメントには式（例: makespan >= max(T_inf, T_1/p)）を明記する
- ターゲット識別は必ず`TargetID`（(packageName, targetName)複合キー）で行う。同一ワークスペース内の2パッケージ（本体アプリ用と併設アプリ用など）に同名ターゲット（例: `AppFeature`）が存在しうるため、名前単体キーは黙って片方を上書きしてしまい禁止
- **swift-subprocessは`exact: "0.2.1"`でpinしている**。ProcessRunning 0.2.1はSubprocess 0.2.1のAPI前提で、0.3系の`Execution`generic化（破壊的変更）を取り込むとProcessRunning自体がビルド不能になる（2026-07-21に実際に踏んだ）。ProcessRunningが追随したらpinを外す
- Scipio系のバイナリラッパーパッケージ（外部SDKをローカルproductとして再輸出するもの）やvendorコードは解析対象から除外する。含めるとprebuilt済み（ソースビルドされない）targetで閉包サイズが黙って水増しされ、ビルド速度解析として誤った数値になる
- コミットは小さく論理単位で分割する。マージは通常マージ（squash禁止）
