# 🩺 swift-module-graph-doctor

**Diagnose and gate the module graph of multi-package Swift workspaces.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

Your build is slow and someone proposes "let's split the big module". Will it
actually help? swift-module-graph-doctor answers that question with a formal
model instead of vibes: it extracts the target-level dependency graph across
all your packages, computes the two lower bounds that govern build time, tells
you which one is the real bottleneck — and then **gates regressions in CI** so
the graph never quietly degrades again.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [How It Works: the Work-Span Model](#how-it-works-the-work-span-model)
- [Commands](#commands)
  - [diagnose](#diagnose)
  - [check](#check)
  - [weights](#weights)
- [Configuration](#configuration)
- [Graph Lint](#graph-lint)
- [JSON Output](#json-output)
- [Installation](#installation)
- [Development](#development)
- [License](#license)

## Features

- 📊 **Formal build-time diagnosis** — computes the Graham bound
  `makespan >= max(T_inf, T_1/p)` from your real dependency graph and names the
  binding constraint (depth-bound / width-bound / balanced), so you know
  *before* refactoring whether it can pay off.
- 🚧 **Baseline regression gate** — commit a `graph-baseline.json`; `check`
  fails the build when the simulated makespan regresses, the critical path
  grows, or a feature's closure cost jumps, and prints the exact new edges
  that caused it.
- 🏛️ **Graph lint** — classify targets into layers and deny relations with a
  two-token rule (`deny: feature -> live`, `deny: interface => sdk`); violations
  come with a witness path, and a violations baseline lets legacy codebases
  adopt rules incrementally.
- ⚖️ **Measured weights** — feed an [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser)
  report and every feature gets a real number: how many compile-seconds its
  closure pulls in.
- 🧵 **Fast** — package descriptions load in parallel, reachability scans and
  closure costs fan out on the cooperative thread pool; a ~200-target
  workspace checks in a few seconds.

## Quick Start

```sh
# Zero config: run it in your package (or workspace) directory.
# Packages are discovered automatically and the analysis roots default to
# every target nothing else depends on (typically your app / executable).
cd MyWorkspace
swift-module-graph-doctor diagnose
```

```text
Module graph diagnosis
======================
analyzed roots : MyApp/AppFeature
assumptions    : c = 1.0s build cost per target, p = 10 parallel workers

Model: a build can never finish faster than max(T_inf, T_1/p)
(work-span model, a.k.a. Graham bound). The two lower bounds are
explained below; whichever is larger is the real bottleneck.

N             195 targets   size of the dependency closure (everything the roots pull in)
D             18 targets    longest dependency chain; these can only build one after another
T_1 = N x c   195.0s        total work if everything built on a single worker
T_inf = D x c 18.0s         depth bound: even infinite workers cannot beat the serial chain
T_1/p         19.5s         width bound: 10 workers cannot beat total work / p
makespan^     21.0s         simulated build time with an ideal scheduler on p workers

Verdict: BALANCED -- at the knee (the two bounds are within 10%)
  Neither flattening the dependency chain alone nor adding workers
  alone will make this build meaningfully faster: as soon as one bound
  drops, the other becomes the bottleneck. Only changes that lower
  both (fewer targets, cheaper per-target cost) still pay off.

Critical path (the D-target serial chain; shorten it by removing or
rerouting any edge in this chain):
  MyApp/AppFeature
    -> MyApp/TaskFeature
    -> ...
```

```sh
# Freeze the current state and gate regressions from now on
swift-module-graph-doctor check --update-baseline
git add graph-baseline.json

# Wire `swift-module-graph-doctor check` into your pre-merge checks.
# From now on this is what a bad PR sees:
```

```text
[error] lint violation: feature -> live: MyApp/HomeFeature -> Core/TimelineClientLive (path: MyApp/HomeFeature -> Core/TimelineClientLive)
[info] new edge: MyApp/HomeFeature -> Core/TimelineClientLive
(exit code 1)
```

## How It Works: the Work-Span Model

Building a multi-package workspace is scheduling a DAG of N tasks on p cores.
Classic scheduling theory gives two independent lower bounds:

| Bound | Formula | Meaning | To lower it |
|---|---|---|---|
| depth bound | `T_inf = D x c` | the longest dependency chain must build serially | flatten the graph |
| width bound | `T_1/p = N x c / p` | p workers can never beat total work / p | fewer targets, cheaper targets, more cores |

`makespan >= max(T_inf, T_1/p)` — and the tool's job is to tell you **which
bound binds**. This matters because refactorings only pay off when they attack
the binding constraint: shortening an 18-deep chain does nothing while the
width bound dominates, and buying a bigger machine does nothing while the
depth bound dominates. When the two are within 10% of each other you are *at
the knee*: only changes that lower both still help. The `makespan^` figure is
a critical-path-first list-scheduling simulation, so you can also see how much
headroom an ideal scheduler leaves above the max of the two bounds.

`diagnose` additionally reports:

- **Width profile** — how many targets exist per dependency depth. Layers
  narrower than p are "necks" where workers sit idle; re-export facades
  typically show up here as suspicious width-1..4 serial runs.
- **Interface load** — the transitive closure over `public import` edges
  (SE-0409 aware). `internal import` cuts these edges; the number shows how
  many modules get re-exposed to every consumer.
- **Feature cost** — with measured weights, `cost(F) = Σ w(M) for M ∈ reach(F)`:
  the compile-seconds a feature pulls into its closure.

## Commands

### diagnose

```sh
swift-module-graph-doctor diagnose [--config module-graph-doctor.yml] [--format text|json]
```

Prints the full report above. `--format json` emits a machine-readable version
(schema below) for dashboards or custom gating.

### check

```sh
swift-module-graph-doctor check [--config ...]        # gate against baselines (exit 1 on error)
swift-module-graph-doctor check --update-baseline     # (re)freeze graph-baseline.json
swift-module-graph-doctor check --update-violations   # (re)freeze violations-baseline.yml
```

What is gated, and at which severity:

| Finding | Default severity |
|---|---|
| simulated makespan regressed | warning at +0.5s, **error at +1.0s** |
| critical path grew | warning |
| feature cost regressed | warning at +10s, **error at +30s** |
| new lint violation (not in the violations baseline) | **error**, with witness path |
| violation in baseline no longer observed | info (prune the stale entry) |
| new / removed edges, target count changes | info |

Intentional changes are made visible in review as a diff of the committed
baseline files — the same idea as a snapshot test for your module graph.

### weights

```sh
xclogparser parse --project MyApp --reporter json --output build.json
swift-module-graph-doctor weights --log build.json
```

Sums the durations of `Compile *` steps per target (deliberately ignoring the
"Build target" wall time, which includes waiting on other targets) and writes
a diff-stable `weights.yml`. With weights present, `diagnose` reports feature
costs, `check` gates their regressions, and targets above
`labels.heavyThresholdSeconds` are auto-labeled `heavy` for invariants.

## Configuration

No config file is required. When you want to pin things down, put a
`module-graph-doctor.yml` next to your workspace — the schema is flat and
every key is optional:

```yaml
root: AppFeature                   # target(s) to analyze. Bare name is enough;
                                   # use <package>/<target> only if the name is
                                   # ambiguous (the error will tell you).
                                   # Omit to auto-detect: every non-test target
                                   # nothing else depends on

path: "."                          # a package directory, or a directory whose
                                   # children are packages -- both work.
                                   # Single-package repos just use "." (default)
exclude: [BinaryWrappers]          # package dir names to skip: Scipio-style
                                   # wrappers / vendored code are never
                                   # source-built and would inflate the closure

costPerTarget: 0.63                # measured per-target cost c in seconds (default 1.0)
cores: 10                          # workers p (default: this machine's core count)
topCount: 15                       # rows shown in load / cost rankings

weights: "weights.yml"             # optional, written by the weights command

layers:                            # optional, powers the lint rules.
  app: [AppFeature]                # list   = exact target names (also matches external products)
  live: "(Client|UseCase)Live$"    # string = regex on the target name
  feature: "Feature$"
  interface: "(Client|UseCase)$"
  sdk: [FirebaseFirestore, GRDB]
  heavy: 60                        # number = any target measured at >= 60s

lint:
  - deny: feature -> live          # ->  forbids the direct edge
  - deny: interface => sdk         # =>  forbids any transitive path
  - deny: "* => heavy"             # nobody may depend on heavy targets...
    allow: [live, app]             # ...except these layers

check:
  baseline: "graph-baseline.json"
  violationsBaseline: "violations-baseline.yml"
  makespanWarnSeconds: 0.5
  makespanErrorSeconds: 1.0
  featureCostWarnSeconds: 10
  featureCostErrorSeconds: 30
```

## Graph Lint

Classify targets into **layers**, then **deny** relations between them.
A layer is defined by a regex on the target name (string), an exact name list
(list — these also match external products, which is how `sdk` works), or a
measured-weight threshold in seconds (number). A target matching two layers is
a configuration error, not a silent order-dependent pick.

Three rule shapes, all O(V+E) reachability queries:

| Rule | Meaning |
|---|---|
| `deny: A -> B` | no direct edge from an A-layer target to a B-layer target |
| `deny: A => B` | no transitive path either — catches leaks that import-statement linting cannot see (the SDK arriving through a chain of intermediate modules) |
| `deny: "* => B"` + `allow: [...]` | nothing may depend on B-layer targets except the allowed layers |

Every violation is reported with a witness path
(`A -> B -> C -> FirebaseFirestore`), and known violations live in a committed
`violations-baseline.yml`: only **new** ones fail the build, so you can turn
the rules on today in a codebase with a hundred legacy violations and ratchet
them down over time.

## JSON Output

`diagnose --format json` keys:

| Key | Type | Meaning |
|---|---|---|
| `roots` | `[String]` | closure roots (`package/target`) |
| `costPerTarget`, `parallelism` | `Double`, `Int` | c and p used for the analysis |
| `workSpan.targetCount` | `Int` | N |
| `workSpan.criticalPathLength` | `Int` | D |
| `workSpan.criticalPath` | `[String]` | the chain, root first |
| `workSpan.totalWork` | `Double` | T_1 = N x c (seconds) |
| `workSpan.criticalPathBound` | `Double` | T_inf = D x c (seconds) |
| `workSpan.parallelBound` | `Double` | T_1/p (seconds) |
| `workSpan.simulatedMakespan` | `Double` | list-scheduling simulation (seconds) |
| `workSpan.bindingConstraint` | `String` | `critical-path` / `parallelism` / `balanced` |
| `workSpan.widthProfile[]` | `{depth, width, targets}` | width per depth layer |
| `topInterfaceLoads[]` | `{target, load}` | public-import closure sizes |
| `topFeatureCosts[]?` | `{target, cost}` | closure costs (only with weights) |

## Installation

Via [mise](https://mise.jdx.dev/) with the `spm:` backend (downloads the
artifact bundle attached to GitHub Releases):

```toml
[tools]
"spm:Ryu0118/swift-module-graph-doctor" = { version = "0.1.0", artifactbundle = true }
```

While this repository is private the download needs an authenticated
environment (e.g. `GITHUB_TOKEN` with repo read access); this note goes away
once the repository is public. The bundle ships a macOS universal binary
(arm64 + x86_64) only — the tool shells out to `xcrun swift package describe`,
which does not exist on Linux.

To release: run the `Publish Release` workflow with a semver version. It
builds the universal binary, bumps the version constant, validates the
bundle's `info.json` with a strict JSON parser (a trailing comma there
silently breaks spm-backend installation), then tags and uploads the bundle
with its SHA-256 checksum.

## Development

```sh
mise run setup   # install dev tools + git hooks
mise run check   # swiftformat --lint, swiftlint --strict, AST lint, docsync
mise run test    # swift test
```

- Swift 6.2 / macOS 26+
- Module layout and conventions: [CLAUDE.md](CLAUDE.md)

## License

MIT
