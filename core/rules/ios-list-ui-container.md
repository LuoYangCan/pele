# iOS list container choice: virtualize repeated homogeneous items by default

On iOS, a "collection of repeated homogeneous items" (scrolling list / table) always defaults to a virtualized container: `UICollectionView` / `UITableView` / SwiftUI `List` / `LazyVStack`. **Do not** use "is the data bounded or unbounded right now" to decide whether `UIStackView` is acceptable.

## Triggers

Writing / refactoring iOS list UI — any scrolling collection of homogeneous items (feed / list / table / sectioned list).

## Does not trigger

- Multi-row composition inside a cell / tag-chip flow layout / button groups (the container is nested inside an already virtualized cell)
- Detail pages / forms with a fixed set of fields or sections (what repeats is heterogeneous sections, not homogeneous items; a fully scrolling page is fine)
- macOS (this rule constrains iOS only)

## Rules

- **Repeated homogeneous item collection → virtualized container** (collectionView / tableView / List / LazyVStack), chosen by default, in the first version
- **Fixed heterogeneous composition → `UIStackView` / `ScrollView+VStack`**

The criterion is **shape**, not data volume: repeated homogeneous → virtualized; fixed heterogeneous → stack/VStack.

## Forbidden

- ❌ Rendering a scrolling homogeneous list by `addArrangedSubview`-ing everything into a `UIStackView`, then hand-adding a cap / collapse "so it does not stutter" — that only confirms it should have been a list container (a pure-IA top-N summary preview is the exception)
- ❌ Arguing for stackView from "there is not much data now / it is bounded" — the bound drifts with requirements, it can go from bounded to unbounded without the client code changing, and nobody comes back to re-pick the container

## Why (core)

Asymmetric cost: choosing a virtualized container upfront only costs a bit more boilerplate; guessing stackView and guessing wrong = a production perf cliff + an after-the-fact migration (which also has to add diffable / cell reuse). Design for performance from the start; pay the cost in the first version.

## Related

- The reviewer's performance anti-pattern check (`~/.claude/commands/review.md`, correctness reviewer item 7, iOS performance anti-patterns; advisory / non-blocking) flags against this rule
- Counter-example: <TasksModule> `TasksDoneVC` (paging accumulates into a stackView + collapse-5 cannot contain the growth in section count)
