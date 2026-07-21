// GENERATED CONTENT MIRROR — keep in sync with skills/module-graph-doctor/SKILL.md.
// The skill is embedded as a string because the release artifact bundle ships
// the bare executable only; an SPM resource bundle would not travel with it.
// BundledSkillSyncTests fails whenever this constant and the file diverge.
// The blank line before the closing delimiter preserves the file's trailing
// newline (Swift multiline literals drop the final line break).

/// The bundled agent skill installed by `install-skills`
enum BundledSkill {
    /// Skill directory name
    static let name = "module-graph-doctor"

    /// Full SKILL.md content
    static let markdown = #"""
    ---
    name: module-graph-doctor
    description: Diagnose and gate Swift package module graphs with swift-module-graph-doctor. Use when asked why a multi-package build is slow, whether splitting or flattening modules will help, to measure per-target build cost, to set up module-graph regression gates, or to generate build weights from an Xcode build log.
    ---

    ## What this tool is

    `swift-module-graph-doctor` statically analyzes the target-level dependency
    graph of one or more Swift packages. It has two roles:

    - **diagnose** — measurement, no pass/fail. Computes the work-span model and
      tells you which bound limits the build.
    - **check** — a gate for CI/pre-merge. Compares against the committed
      baseline; exit code 1 on regressions.

    Layer rules (feature/live/sdk boundaries, deny DSL, violations baseline) are
    the sibling tool `swift-module-graph-lint` — use it alongside this one.

    ## Core concepts (read once)

    **Work-span model.** Building N targets on p cores can never finish faster
    than `max(T_inf, T_1/p)` where `T_1 = N x c` (total work), `T_inf = D x c`
    (D = longest dependency chain), c = per-target cost. The *verdict* names the
    binding constraint:

    - `DEPTH-BOUND` — the serial chain limits the build; flatten the graph,
      do not bother adding cores.
    - `WIDTH-BOUND` — total work / cores limits it; reduce targets, cheapen
      targets, or add cores. Flattening alone is useless.
    - `BALANCED` (the knee) — only changes that lower both bounds still pay off.
      Refuse refactoring proposals that attack just one bound.

    **Weights** (`weights.yml`) — measured compile seconds per target, extracted
    from a real Xcode build log. Optional; without it every target costs `c`.

    **Build cost** — `buildCost(T) = sum of w(M) for M in reach(T)`: what building
    target T from scratch costs, dependencies included. This is the number that
    matters for standalone test-suite builds.

    ## Typical workflows

    ### 1. First diagnosis (zero config)

    ```sh
    cd <workspace>          # a root package dir (local deps found recursively) or a dir of packages
    swift-module-graph-doctor diagnose
    ```

    Roots are auto-detected (targets nothing depends on). If several roots are
    reported and some look like dead or unwired modules, that is a finding —
    report it. To focus on one app: `root: AppFeature` in `module-graph-doctor.yml`.

    ### 2. Set up the regression gate

    ```sh
    swift-module-graph-doctor check --update-baseline      # writes graph-baseline.json
    git add graph-baseline.json
    ```

    Wire `swift-module-graph-doctor check` into pre-merge checks. Gates are
    relative (% vs baseline) so re-measuring weights on faster hardware does not
    de-calibrate them. Intentional graph changes are reviewed as baseline diffs —
    run `check --update-baseline` and commit the diff.

    ### 3. Generate weights from a build log

    ```sh
    # Build. -resultBundlePath is REQUIRED for CLI builds: without it Xcode may
    # not regenerate the .xcactivitylog and you will parse a stale log.
    xcodebuild -workspace App.xcworkspace -scheme App \
      -destination "platform=iOS Simulator,id=$UDID" \
      -derivedDataPath /tmp/dd -resultBundlePath /tmp/rb.xcresult build

    # Convert the newest activity log to JSON (brew install xclogparser)
    LOG=$(ls -t /tmp/dd/Logs/Build/*.xcactivitylog | head -1)
    xclogparser parse --file "$LOG" --reporter json --output build.json

    swift-module-graph-doctor weights --log build.json     # writes weights.yml
    ```

    Traps:
    - Use a **clean build** log: incremental logs only contain recompiled targets,
      everything else silently gets weight 0.
    - An interrupted build leaves a log that fails with `not a valid SLF log`;
      fall back to the previous log file.
    - GUI builds log automatically under
      `~/Library/Developer/Xcode/DerivedData/<project>/Logs/Build/`.

    ### 4. Interpreting a failed check

    - `simulated makespan regressed by +X%` / `build cost of T regressed by +X%`
      — inspect the `new edge:` info lines in the same output; they name the
      exact dependency edges that caused the regression.

    ## Configuration reference (module-graph-doctor.yml, all keys optional)

    ```yaml
    root: AppFeature            # bare name; <package>/<target> if ambiguous; omit = auto
    path: "."                   # root package dir (local deps discovered) or dir of packages
    exclude: [VendoredLib]      # skip wrapper/vendored packages (they inflate the closure)
    costPerTarget: 0.63         # measured c in seconds (default 1.0)
    cores: 10                   # p (default: machine cores)
    weights: weights.yml
    check:
      makespanWarnPercent: 5
      makespanErrorPercent: 10
      buildCostWarnPercent: 10
      buildCostErrorPercent: 25
    ```

    `diagnose --format json` emits the machine-readable report (schema in the
    project README) for custom tooling.

    """#
}
