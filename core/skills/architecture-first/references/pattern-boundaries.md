# Behavior and object pattern boundaries

Read only when `architecture-first` has already confirmed an unresolved material choice and the difference comes mainly from behavior, creation, or adaptation. A local branch, a lint finding, or "we might extend it later" is not enough to trigger it.

## Fix the axis of variation first

| Axis of variation | Preferred shape | When not to escalate |
| --- | --- | --- |
| A closed, stable, small set of cases | `enum` + `switch` / table-driven dispatch | The branching stays inside one existing boundary |
| One action has multiple real, swappable implementations | Strategy | There is only one implementation today, or the difference is just a parameter |
| Behavior is decided by the object's current state and its legal transitions | State / explicit state machine | A standalone boolean expresses it and there is no transition invariant |
| The creation site must hide multiple concrete implementations | Factory / registry | `init` is already the single obvious entry point |
| An external/legacy interface does not match the stable internal contract | Adapter | It is logic-free forwarding, or the dependency never needs swapping |
| Orthogonal capabilities must compose independently | Decorator / middleware | The capabilities are mutually exclusive, or there will only ever be one layer |
| Multiple independent steps need to be pluggable, reordered, or short-circuited | Pipeline / Chain | The steps are fixed and share a lot of intermediate state |
| One event has multiple consumers with independent lifecycles | Observer / event stream | A one-to-one synchronous call expresses it |

## Decision constraints

- Reuse the project's most recent precedent first; do not introduce a second pattern unless that precedent violates a current invariant.
- Build a protocol/interface only when the two sides of the seam have different rates of change, multiple implementations, a cross-module dependency, or test-substitution value.
- One caller, one implementation, a forward-only wrapper — usually not a seam.
- A pattern must reduce caller knowledge or centralize an invariant; reject one that only adds types and indirection layers.
- When choosing State, record legal/illegal transitions, the state owner, and the concurrency serialization point.
- When choosing Observer/event stream, record the subscription owner, teardown timing, ordering, and error propagation.
- When choosing Factory/registry, record the registration owner, missing-implementation behavior, and visibility scope.
- When choosing Adapter, let business requirements decide the internal contract; do not copy the third-party API.

## Nearest-candidate comparison

Compare only the two closest shapes:

- `switch` vs Strategy: do cases grow open-endedly, and does the caller need to swap implementations;
- Strategy vs State: does the difference come from caller intent, or from the same object's current state;
- direct call vs Observer: are consumers genuinely multiple and lifecycle-decoupled;
- direct dependency vs Adapter/port: is the dependency volatile, cross-boundary, or in need of a test double;
- sequential function vs Pipeline: are the steps independent, composable, and stable in input and output.

Write the final choice, the nearest rejected candidate, and the test boundary into `architecture_decision`; do not produce pattern tutorials or example code.
