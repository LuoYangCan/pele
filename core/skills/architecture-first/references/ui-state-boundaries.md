# UI state and event-flow boundaries

Read only when `architecture-first` has already confirmed an unresolved material choice in source-of-truth, state lifecycle, or cross-screen event flow. A single view's local state, an ordinary binding, or staying on the existing UI architecture does not trigger it.

## Facts that must be frozen

- which object is the authoritative state owner;
- whether the state lifecycle is view, flow, feature, session, or process;
- how user events, async results, and external events enter;
- who starts, cancels, and returns IO/effects;
- whether there is a dual write, an update cycle, or multiple competing sources-of-truth;
- whether tests need to observe state, events, effects, or navigation results.

## Shape routing

| Constraint | Preferred shape | Boundary requirement |
| --- | --- | --- |
| view-local, short-lived, not shared | Platform-native local state / plain MVC | State does not escape; no global store |
| Testable derived state and async entry points for one screen/feature | MVVM / Presenter | The ViewModel/Presenter holds no concrete view toolkit; effect dependencies are injectable |
| Explicit state transitions and illegal events | Explicit state machine | A single transition owner; transitions and concurrency ordering are testable |
| Multi-source events, complex effects, traceable actions needed | Reducer / unidirectional flow | A single store; mutation only in the reducer/transition; effects return explicitly |
| Cross-screen flow/navigation ownership | Coordinator/router | Features do not own global navigation directly; avoid a God coordinator |
| State shared across features/sessions | Lift to the smallest common owner | Consumers read-only or send events; do not copy mutable state |

## Selection rules

- Reuse the project's UI state shape when it is already stable; screen line count or team size is not sufficient reason to switch architecture.
- A simple screen does not get a store/reducer automatically for "testability"; first verify that real state or effect complexity exists.
- Do not hide network, database, time, or randomness inside a reducer/pure transition; feed results in through the effect boundary.
- Do not let multiple ViewModels/stores each maintain the same business entity; name one owner and an explicit sync direction.
- When navigation is only a single push/present, call the existing router directly; add a coordinator seam only when flow ownership spans screens.
- When introducing a new state owner, spell out the removal order for the old owner; long-lived dual writes are forbidden.

## Consequences: minimum requirements

Record in `architecture_decision`:

- the source-of-truth and its lifecycle;
- event/effect direction of flow and cancellation points;
- the migration boundary from old state to new state;
- targeted tests for transitions, effects, and navigation.

Do not output an MVC/MVVM/TCA encyclopedia; state only why the current owner/flow needs the chosen shape, and why the nearest candidate cannot satisfy the invariants.
