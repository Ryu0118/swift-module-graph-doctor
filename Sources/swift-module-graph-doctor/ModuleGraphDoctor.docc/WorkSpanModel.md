# The Work-Span Model

Why `diagnose` computes two bounds instead of one number, and what the
verdict actually means.

## Overview

"Split this module" and "add more build machine cores" are both real
refactoring proposals, and they attack two *different* bottlenecks. Without a
model that separates them, a build-speed conversation collapses into
guessing. This article derives the two-bound model `diagnose` reports, shows
why neither bound alone is trustworthy, and explains what the third number
(`makespan^`) adds on top.

## The problem is DAG scheduling, not arithmetic

A multi-package build is `N` compilation tasks (targets) connected by a
dependency DAG, executed on `p` parallel workers (cores). This is a textbook
scheduling problem, and textbook scheduling theory gives an unavoidable fact:
no scheduler, however clever, can finish faster than the larger of two
independent lower bounds.

**The depth bound.** Let `D` be the number of targets on the longest
dependency chain (the *critical path* — computed by
`ModuleGraph.longestPath(within:)` in
[SwiftModuleGraph](https://github.com/Ryu0118/swift-module-graph)), and `c`
the average cost to build one target. Every target on that chain must finish
before the next one can even start — that is what "depends on" means. So:

```
T_inf = D * c
```

is a hard floor. Even with infinite parallel workers, a build cannot finish
faster than this chain, because the chain has nothing to parallelize *within
itself* — its N steps are strictly sequential by construction.

**The width bound.** Let `T_1 = N * c` be the total work: what building
everything would cost on a single worker with zero idle time. Spread evenly
across `p` workers:

```
T_1 / p
```

is the other hard floor — no matter how shallow the dependency chain is, `p`
workers cannot do `T_1` seconds of total work faster than `T_1 / p`, because
that would require doing more than `p` things at once.

**The Graham bound.** These two bounds are independent — one comes from the
*shape* of the graph (how deep the chain is), the other from its *size* (how
much total work there is) — and a real schedule is bound by whichever is
larger:

```
makespan >= max(T_inf, T_1 / p)
```

This is why `diagnose` never reports one number: reporting only `T_inf`
would hide a build with too many parallel targets and too few cores;
reporting only `T_1 / p` would hide a build crippled by one long serial
chain. **Neither bound is meaningful in isolation** — you need both to know
which one is real.

## The binding constraint decides which refactor pays off

`diagnose` names the larger bound the **binding constraint**, because that is
the only bound a refactor can actually move:

| Binding constraint | What's true | What helps | What does nothing |
| --- | --- | --- | --- |
| depth-bound (`T_inf` larger) | one long serial chain dominates | flattening the chain, removing/rerouting an edge on it | adding cores |
| width-bound (`T_1/p` larger) | total work dominates, chain is comparatively shallow | fewer targets, cheaper targets, more cores | flattening a chain that isn't the bottleneck |
| balanced (within 10%) | the two bounds are close | only changes that lower **both** | either kind of change alone — as soon as one bound drops, the other becomes the new floor |

The 10% "balanced" threshold exists because at the knee, spending a week
flattening the critical path only to have the width bound immediately take
over as the new floor is a common and expensive mistake — the model exists
specifically to catch that trap before you spend the week.

## `makespan^`: the number above the theoretical floor

`max(T_inf, T_1/p)` is a *lower bound* — the best any scheduler could
possibly do, not what a real one achieves, because a real scheduler cannot
always keep every worker busy (a worker can go idle waiting for a dependency
that has not finished yet, even when other independent work theoretically
exists but happens to run out at the wrong moment). `makespan^` closes that
gap: it is a **critical-path-first list-scheduling simulation** — at every
step, run up to `p` ready targets (all dependencies finished) in parallel,
always preferring targets with greater *upward height* (the longest chain of
targets that depend on them) when more are ready than there are free
workers. This priority rule is not arbitrary: targets deep in the graph's
downstream have the least slack, so starving them first is what would most
likely blow the schedule out — running them first is the standard heuristic
for minimizing simulated makespan on a DAG.

The gap between `makespan^` and `max(T_inf, T_1/p)` is your **scheduling
headroom** — how much a smarter task ordering could still claw back even
without touching the graph's shape at all. A small gap means the two
theoretical bounds already describe your real build well. A large gap is a
signal worth investigating on its own (a build system not exploiting
available parallelism, for instance), separate from the shape-changing
refactors the binding constraint points at.

## Where to go next

Read <doc:RegressionGate> for how these numbers, once measured once, become a
CI gate instead of a one-off report.
