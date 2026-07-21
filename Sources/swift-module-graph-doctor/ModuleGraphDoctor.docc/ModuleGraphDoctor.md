# ``swift_module_graph_doctor``

Diagnose and gate the module graph of multi-package Swift workspaces.

## Overview

`swift-module-graph-doctor` has no library API of its own — every type in
`ModuleGraphDoctorKit` is package-internal, because this project ships as a
CLI, not a library other packages link against (the graph model it works on
lives in the public
[SwiftModuleGraph](https://github.com/Ryu0118/swift-module-graph) library
instead). What belongs here is not a symbol reference, but the reasoning the
CLI's output depends on: the scheduling theory behind `diagnose`'s verdict,
and the reasoning behind `check`'s regression gate. The
[project README](https://github.com/Ryu0118/swift-module-graph-doctor)
documents every command and config key; these articles are the "why," which
a flag list cannot carry.

## Topics

### The model

- <doc:WorkSpanModel>

### The gate

- <doc:RegressionGate>
