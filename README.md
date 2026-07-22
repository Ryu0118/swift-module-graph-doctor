# 🩺 swift-module-graph-doctor

**Diagnose and gate the module graph of multi-package Swift workspaces.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](https://developer.apple.com/macos/)

**[Full API documentation →](https://ryu0118.github.io/swift-module-graph-doctor/documentation/swift_module_graph_doctor/)**

Your build is slow and someone proposes "let's split the big module". Will it
actually help? swift-module-graph-doctor answers that question with a formal
model instead of vibes: it extracts the target-level dependency graph across
all your packages, computes the two lower bounds that govern build time, tells
you which one is the real bottleneck — and then **gates regressions in CI** so
the graph never quietly degrades again.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Commands](#commands)
  - [diagnose](#diagnose)
  - [check](#check)
  - [weights](#weights)
  - [install-skills](#install-skills)
- [The Model](#the-model)
- [Configuration](#configuration)
- [Agent Skill](#agent-skill)
- [Installation](#installation)
- [Development](#development)
- [License](#license)

## Features

- 📊 **Formal build-time diagnosis** — computes the Graham bound
  `makespan >= max(T_inf, T_1/p)` from your real dependency graph and names
  the binding constraint, so you know *before* refactoring whether it can
  pay off.
- 🚧 **Regression gate** — `check` fails the build when the simulated
  makespan regresses, the critical path grows, or a target's build cost
  jumps, and prints the exact new edges that caused it.
- ⚖️ **Measured build costs** — feed an [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser)
  report and every target gets a real number: what building it from scratch
  costs, dependencies included, in compile-seconds.

## Quick Start

Zero config — run it in your workspace directory:

```sh
swift-module-graph-doctor diagnose
```

```text
T_inf = D x c 18.0s   depth bound: the longest chain, however many workers you have
T_1/p         19.5s   width bound: total work / your core count
makespan^     21.0s   simulated build time

Verdict: BALANCED -- at the knee (the two bounds are within 10%)
```

The verdict tells you which refactor can possibly pay off — see
[The Model](#the-model) for what these numbers mean. Once you're ready to
stop regressions in CI, freeze a baseline and add `check` (see
[check](#check) below).

## Commands

### diagnose

```sh
swift-module-graph-doctor diagnose [--config module-graph-doctor.yml] [--format text|json]
```

Measurement, no pass/fail. Prints the work-span report (see
[The Model](#the-model)) plus:

- **Width profile** — targets per dependency depth; layers narrower than
  your core count are "necks" where workers sit idle.
- **Interface load** — the transitive closure over `public import` edges
  (SE-0409 aware): how many modules each module re-exposes to every consumer.
- **Build cost** — with measured weights,
  `buildCost(T) = sum of w(M) for M in reach(T)`: what building any target
  from scratch costs, dependencies included. This is the number that matters
  for standalone test-suite builds and dev loops.

`--format json` emits the same report machine-readable (keys mirror the text
report: `workSpan.targetCount`, `workSpan.simulatedMakespan`,
`workSpan.bindingConstraint`, `topInterfaceLoads`, `topBuildCosts`, ...) for
dashboards or custom gating.

### check

```sh
swift-module-graph-doctor check [--config ...]        # exit 1 on regression
swift-module-graph-doctor check --update-baseline     # (re)freeze the baseline
```

Compares the current graph against the committed baseline
(`.module-graph-doctor/graph-baseline.json` by default) — the same idea as a
snapshot test for your module graph. Intentional changes are reviewed as the
baseline diff.

| Finding | Default severity |
|---|---|
| simulated makespan regressed | warning at +5%, **error at +10%** |
| critical path grew | warning |
| a target's build cost regressed | warning at +10%, **error at +25%** |
| new / removed edges, target count changes | info |

Thresholds are **relative to the baseline**, so re-measuring weights on a
faster machine does not de-calibrate the gates.

### weights

```sh
# CLI builds need -resultBundlePath, or Xcode may leave a stale .xcactivitylog
xcodebuild -workspace App.xcworkspace -scheme App \
  -derivedDataPath /tmp/dd -resultBundlePath /tmp/rb.xcresult build
xclogparser parse --file "$(ls -t /tmp/dd/Logs/Build/*.xcactivitylog | head -1)" \
  --reporter json --output build.json
swift-module-graph-doctor weights --log build.json
```

Turns a real build log into per-target compile-second weights
(`.module-graph-doctor/weights.yml`). With weights present, `diagnose`
reports build costs and `check` gates their regressions.

Two traps:

- Use a **clean-build** log — incremental logs only contain the recompiled
  targets; everything else silently weighs 0.
- `not a valid SLF log` means the newest log came from an interrupted
  build — use the previous one.

### install-skills

```sh
swift-module-graph-doctor install-skills    # install the agent skill (see Agent Skill)
```

## The Model

Building a multi-package workspace is scheduling a DAG of N tasks on p
cores. Classic scheduling theory gives two independent lower bounds, and
`makespan >= max(T_inf, T_1/p)`:

| Bound | Formula | Meaning | To lower it |
|---|---|---|---|
| depth bound | `T_inf = D x c` | the longest dependency chain must build serially | flatten the graph |
| width bound | `T_1/p = N x c / p` | p workers can never beat total work / p | fewer targets, cheaper targets, more cores |

The tool's job is to tell you **which bound binds**, because refactorings
only pay off when they attack the binding constraint: shortening an 18-deep
chain does nothing while the width bound dominates, and buying a bigger
machine does nothing while the depth bound dominates. When the two are
within 10% of each other you are *at the knee* — only changes that lower
both (fewer targets, cheaper per-target cost) still help. `makespan^` is a
critical-path-first list-scheduling simulation on top, showing how much
headroom an ideal scheduler leaves above the max of the two bounds.

## Configuration

No config file is required. When you want to pin things down, put a
`module-graph-doctor.yml` next to your workspace — every key is optional:

```yaml
root: AppFeature                   # target(s) to analyze. Bare name is enough;
                                   # use <package>/<target> only if the name is
                                   # ambiguous (the error will tell you).
                                   # Omit to auto-detect: every non-test target
                                   # nothing else depends on

packagePath: "."                   # your root package dir: local manifest deps are
                                   # discovered recursively. A dir of packages and
                                   # single-package repos ("." default) also work
exclude: [BinaryWrappers]          # package dir names to skip: binary wrapper /
                                   # vendored packages are never source-built and
                                   # would inflate the closure

costPerTarget: 0.63                # measured per-target cost c in seconds (default 1.0)
cores: 10                          # workers p (default: this machine's core count)
topCount: 15                       # rows shown in load / cost rankings

weights: ".module-graph-doctor/weights.yml"              # default
check:
  baseline: ".module-graph-doctor/graph-baseline.json"   # default
  makespanWarnPercent: 5
  makespanErrorPercent: 10
  buildCostWarnPercent: 10
  buildCostErrorPercent: 25
```

Layer classification and deny rules (`feature -> live`, `interface => sdk`)
are the sibling tool
[swift-module-graph-lint](https://github.com/Ryu0118/swift-module-graph-lint):
doctor gates measurements, lint gates layer boundaries. Run both in CI.

## Agent Skill

The repo ships a `module-graph-doctor` skill (concepts, workflows, and the
build-log traps) so AI agents can drive the tool correctly. Install it any of
these ways:

```sh
# Built-in (sim-use style): writes SKILL.md into the client's skills directory
swift-module-graph-doctor install-skills                  # auto-detects the client
swift-module-graph-doctor install-skills --client claude  # ~/.claude/skills
swift-module-graph-doctor install-skills --client agents  # ~/.agents/skills
swift-module-graph-doctor install-skills --dest .claude/skills   # project-local
# also: --print / --force / --uninstall
```

```sh
# Claude Code plugin
/plugin marketplace add Ryu0118/swift-module-graph-doctor
/plugin install module-graph-doctor@module-graph-doctor

# Codex plugin
codex plugin marketplace add Ryu0118/swift-module-graph-doctor
codex plugin add module-graph-doctor@module-graph-doctor

# APM (Agent Package Manager)
apm install Ryu0118/swift-module-graph-doctor

# GitHub CLI (v2.90.0+)
gh skill install Ryu0118/swift-module-graph-doctor module-graph-doctor --agent claude-code

# skills CLI
npx skills add Ryu0118/swift-module-graph-doctor --all
```

The single source of truth is `skills/module-graph-doctor/SKILL.md`; the copy
embedded in the binary for `install-skills` is kept in sync by a unit test.

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
