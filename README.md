# swift-module-graph-doctor

Diagnose and gate Swift package module graphs.

A CLI tool that statically analyzes target-level dependency graphs spanning multiple Swift packages. It provides (1) build-speed diagnostics based on a formal model (the work-span model) and (2) mechanical detection of structural regressions.

## What it does

- **diagnose** — computes work-span metrics from the dependency graph and reports them
  - `N` (number of targets in the closure) / `D` (longest dependency chain) / necks (narrow layers that kill parallelism)
  - `makespan̂` (a build-time prediction from a list-scheduling simulation) and the binding constraint (T∞ vs T₁/p), based on Graham's bound `makespan >= max(T_inf, T_1/p)`
- **check** — compares against a committed baseline and detects structural regressions (critical-path growth, new necks, heavy dependencies creeping in) via exit codes
- **Architecture invariants** — mechanically verifies layering rules such as "Features must not depend on Live implementations" or "Interfaces must not reach external SDKs" as reachability rules over a labeled DAG

## Usage

```sh
swift-module-graph-doctor diagnose --config module-graph-doctor.yml [--format text|json]
swift-module-graph-doctor check --config module-graph-doctor.yml
```

Configuration file (`module-graph-doctor.yml`):

```yaml
packages:
  roots: ["MyPackages"]          # package scan roots (relative to the config file, or absolute)
  exclude: ["BinaryWrappers"]    # directory names to exclude (Scipio-style binary wrappers, vendor code, etc. — anything never source-built)
analysis:
  roots: ["MyApp/AppFeature"]    # closure roots (<package>/<target> form, multiple allowed)
  costPerTarget: 0.629           # per-target cost in seconds (defaults to 1.0 = relative values)
  parallelism: 10                # core count (defaults to the machine's core count)
  topLoadCount: 15               # number of entries in the load ranking (defaults to 15)
```

### `--format json` schema

| Key | Type | Meaning |
|---|---|---|
| `roots` | `[String]` | Closure roots (`package/target`) |
| `costPerTarget` / `parallelism` | `Double` / `Int` | Analysis parameters (c, p) |
| `workSpan.targetCount` | `Int` | N: number of local targets in the closure |
| `workSpan.criticalPathLength` | `Int` | D: length of the longest dependency chain |
| `workSpan.criticalPath` | `[String]` | The longest chain (starting from the root side) |
| `workSpan.totalWork` | `Double` | T₁ = N×c (seconds) |
| `workSpan.criticalPathBound` | `Double` | T∞ = D×c (seconds) |
| `workSpan.parallelBound` | `Double` | T₁/p (seconds) |
| `workSpan.simulatedMakespan` | `Double` | Prediction from critical-path-first list scheduling (seconds) |
| `workSpan.bindingConstraint` | `String` | `critical-path` / `parallelism` / `balanced` (within 10% = at the knee) |
| `workSpan.widthProfile[]` | `{depth, width, targets}` | Width per depth layer (neck detection) |
| `topInterfaceLoads[]` | `{target, load}` | Largest transitive closures of public imports |

## Development

```sh
mise run setup   # install tools + git hooks
mise run check   # lint + docsync (run before committing)
mise run test    # swift test
```

- Swift 6.2 / macOS 26+
- Module layout and conventions: see [CLAUDE.md](CLAUDE.md)

## License

MIT
