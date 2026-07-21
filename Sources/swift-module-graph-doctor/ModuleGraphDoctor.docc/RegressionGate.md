# The Regression Gate

Why `check` compares percentages instead of seconds, and what each finding
severity means.

## Overview

<doc:WorkSpanModel> explains what `makespan^` and build cost mean on their
own. This article covers what happens once you have measured them once: how
`check` turns those numbers into a pass/fail CI gate without breaking every
time someone measures on a different machine.

## Why the thresholds are percentages, not seconds

A baseline is measured on one machine, at one point in time. `check` compares
today's numbers against it on every run — possibly from a different machine,
a different CI runner, months later. If the gate compared absolute seconds
(`error if makespan > 25.0s`), it would silently de-calibrate the moment
anything about the measurement environment changed: re-measuring `weights.yml`
on a faster CI runner rescales every number down by roughly the same factor,
which would make an absolute-seconds gate stop firing on real regressions (it
looks "faster" even though the *shape* of the graph got worse); re-measuring
on a slower one would make it fire on everything (every build "regressed"
even though nothing about the graph changed at all).

Expressing thresholds as **percent of the baseline** cancels that scaling
factor out. A rescale by machine speed multiplies both the baseline and the
current measurement by (approximately) the same constant, so their ratio —
and therefore the percentage delta — stays roughly stable. This is the same
reasoning that makes `diagnose`'s binding-constraint verdict itself
scale-invariant: `T_inf` and `T_1/p` both scale linearly with `c`
(cost-per-target), so which one is larger does not depend on what machine
measured `c`.

## Why there is also an absolute noise floor

Percentages alone break down at small baselines: a target that goes from
0.05s to 0.08s "regressed" by 60%, which is a real percentage but not a real
signal — it is measurement noise on a number too small to mean anything. Each
gated metric therefore also has a small absolute floor
(`BaselineGate.Thresholds.makespanFloor`, `.buildCostFloor`) that a delta must
clear before the percentage check even runs. A regression must be
**meaningful in absolute terms and large in relative terms** to fire — either
alone is insufficient.

## What gets gated, and at what severity

`check`'s `evaluate` unifies several kinds of change into one finding list:

| Finding | Gated on | Severity |
| --- | --- | --- |
| simulated makespan regression | percent + floor, relative to baseline | warn / **error** |
| a target's build cost regression | percent + floor, relative to that target's baseline cost | warn / **error** |
| critical path length increased | any increase | warning |
| target count changed | any change | info |
| new / removed edges | any diff | info |

Only makespan and build cost have warn/error tiers — everything else is
either a fixed warning or purely informational. That asymmetry is
deliberate: **the width profile (parallelism-killing "necks") is never gated
directly**, because adding a narrow serial layer or lengthening the critical
path always shows up as a makespan increase already — gating the width
profile too would just double-count the same underlying regression under a
different name.

## Edges are context, not a separate signal

The new/removed edge list is always `info`, never a failing severity, because
edges by themselves do not tell you whether something got worse — a new edge
could be a harmless refactor or the actual root cause of a regression above
it in the report. What it *is* good for is **explaining** a regression once
one has already been flagged: when the makespan check fires, the edge diff in
the same report is usually where the actual new dependency responsible for it
shows up, without you having to `git blame` your way to it.

## Where to go next

<doc:WorkSpanModel> covers what the numbers being gated here actually mean;
the [project README](https://github.com/Ryu0118/swift-module-graph-doctor)
covers every config key and default threshold value.
