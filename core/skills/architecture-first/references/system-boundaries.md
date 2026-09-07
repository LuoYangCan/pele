# Module, dependency, and side-effect boundaries

Read only when `architecture-first` has already confirmed an unresolved material choice in module ownership, dependency direction, a public seam, or the IO/persistence boundary. A helper inside one module, a local service, or an ordinary test double does not trigger it.

## Boundary facts

- the existing module graph and the allowed dependency directions;
- the public contract's owner, callers, and compatibility window;
- which layer holds volatile dependencies, IO, time, randomness, and persistence;
- whether business invariants can run independently of the framework/SDK;
- how migration, rollback, and old callers transition.

## Shape routing

| Constraint | Preferred shape | Rejection condition |
| --- | --- | --- |
| The project already has a legal dependency direction and owner | Reuse the existing module/API | Do not create a lateral dependency for local convenience |
| Inner business logic needs a swappable external capability | Port/interface + adapter | There is only one local call and it does not cross a boundary |
| A third-party/legacy API must not leak into the business | Adapter | The internal interface is an isomorphic forward of the original API |
| Business rules can be pure computation and IO can be centralized | Functional core + imperative shell | The business itself is almost entirely IO orchestration |
| Multiple callers need a stable business action | Application service/use case | It only renames a single function |
| Common orchestration across subsystems must be hidden | Facade | Callers need fine-grained control, or it wraps a single call |
| A stable business capability is shared across modules | Sink it into the smallest neutral layer | The sharing is only code similarity; the semantics will evolve independently |

## Dependency rules

- Dependency arrows obey the project invariants; do not add a lateral dependency the invariants do not authorize just for local reuse. Even where the project allows it, still name the contract owner and who owns its evolution.
- Put the protocol/interface on the side that needs the stable contract; do not default to placing it next to the implementation or in a "common" junk drawer.
- A volatile SDK may only expose, through an adapter, the minimum semantics the business needs.
- The owner of IO, database, clock, and randomness must be explicit; inject from the boundary when deterministic tests are needed.
- A public contract change must record source/binary compatibility, the version window, and the caller migration order.
- A new shared module needs an explicit owner, a dependency budget, and at least two real consumers; otherwise keep it inside the existing boundary.
- Do not substitute a name like Clean/Hexagonal for a concrete module graph; the decision must spell out who depends on whom and who owns the contract.

## Consequences: minimum requirements

Record in `architecture_decision`:

- affected modules and the new dependency direction;
- contract owner, adapter layer, and compatibility strategy;
- data/persistence migration and rollback (where applicable);
- boundary tests, contract tests, and existing caller behavior that must be preserved.

Do not produce architecture tutorials or examples unrelated to the project; output only the boundary choice that facts in the current repository support.
