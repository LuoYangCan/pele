---
name: visual-brief
description: Carry structure in one inline diagram and conclusions in a few lines of text, instead of a long paragraph of explanation. Use when explaining a multi-step plan, an implementation approach, a trade-off between approaches, or a set of investigation and architecture conclusions (call chains, data flow, module dependencies, root-cause chains, blast radius of a change) to the user; must be used when the user says "draw a diagram", "visualize this", "show it as a diagram", "just draw it if you can't explain it". Pure Q&A, single-step operations, command output, code diffs themselves, and step-by-step progress reports during execution do not trigger.
---

# Visual brief

Structural information — order, branching, dependencies, hierarchy, spatial relations — reads an order of magnitude faster by eye than in sentences. Leave in text only the few lines a person must read word by word: judgments, risks, and the questions someone has to decide.

## Output shape

Three parts, fixed order:

1. **One-line framing** (≤1 line): what question this diagram answers.
2. **Diagram**: one `mcp__visualize__show_widget` call. All structure goes into the diagram.
3. **Key conclusions**: 3–5 bullets, only the things the diagram cannot draw.

The easiest mistake is part 3 restating in words the boxes and arrows the diagram already has. Test: delete a bullet that describes the diagram's *content*; keep one that gives its *meaning*.

## What is worth drawing

The test is "is the information structural", not "is the content important".

| What you are explaining | What to draw |
| --- | --- |
| Multi-step plan / implementation approach | Step flow. Nodes are acceptance-checkable outputs, not actions like "go read some file"; use color to separate done / in progress / to do |
| Trade-off between approaches | Side-by-side cards, one column per approach, rows are the same set of evaluation dimensions; mark the recommendation with an accent border, do not state it only in text |
| Root cause / call chain / data flow | flowchart, color the failing edge or node alone and leave the rest gray — the contrast is itself the conclusion |
| Module dependencies / layered architecture | structural diagram, same layer in a row, dependency direction uniformly downward |
| Blast radius of a change | Module map, color the touched boxes, leave the untouched ones gray |
| Sequencing / race conditions | Swimlanes + timeline, pull the interleaved stretch out on its own and enlarge it |

Not worth drawing: single-step operations, two boxes and one arrow (a sentence is faster), things that already are a list, commands and diffs themselves.

**Self-check**: with the diagram removed, could the same length of text say it just as clearly? If yes, do not draw it — a diagram that says nothing new wastes more of the user's attention than a paragraph does.

## How to draw

First confirm the medium: with `mcp__visualize__show_widget` take path A (Claude hosts usually have it), without it take path B (hosts such as Codex).

### A. inline widget

Call `mcp__visualize__read_me` and pick the closest `modules` value: `diagram` (plan / architecture / flow — the vast majority), `chart` (data), `mockup` (UI approaches). It brings the full design system.

Its return is about 63k characters, which exceeds the single tool-return cap and gets written to a file. Do not read the whole thing: list the sections with `grep -n '^#'` first, then take the parts you need with `sed -n`. Core Design System, Color palette, and SVG setup are required reading; take the specific diagram type by what you are drawing.

Ramp classes like `c-teal`, CSS variables like `--text-primary`, and `sendPrompt()` are all provided by the host and exist only inside the widget — hang details that do not fit in a box on `sendPrompt('expand step 3')` so the user asks when they want to see them, which is exactly the effect "the least text" is after. This assumes the diagram really is sparse; do not promise click-through while piling all the content in.

### B. Standalone HTML file

Write self-contained HTML to the scratchpad, then open it:

```bash
open "$SCRATCHPAD/visual-brief-<slug>.html"
```

If `SendUserFile` exists, send it along too.

This path has **no** host CSS variables, ramp classes, or `sendPrompt`; bring all of it yourself: define your own set of color variables on `:root`, override the whole set with `@media (prefers-color-scheme: dark)`, and give `body` an explicit background color. Miss this step and a dark system gets black text on a black background — a standalone file has no host fallback. Details cannot be expanded by clicking; only the bullets under the diagram can carry them.

Do **not** publish it as a claude.ai Artifact — treat local project content as company-confidential unless the user explicitly asks for a shareable link. If neither path works, fall back to plain text; do not force it with ASCII art.

### Hard constraints shared by both paths

- Put **only visual elements** in the diagram. Titles, lead-ins, and explanatory prose belong in your reply body, not in the diagram.
- It must work in both light and dark, and colors are not hardcoded in one place: widgets use ramp classes and CSS variables, standalone files use custom variables + a dark override.
- Box subtitles ≤5 words; ≤2 color families per diagram; ≤4 boxes per row — past that, wrap or split into two diagrams, "overview + detail".
- Color encodes semantics, not order: same kind of node, same color; neutral structure in gray. Step 1 blue, step 2 orange, step 3 red is noise.
- No emoji, no gradient shadows, no `position: fixed`.
- Work out the coordinates before drawing SVG: size each box's width by its longest line of text, and check every arrow for crossing another box. Overlaps and arrows through boxes make the diagram read as broken outright, and correct content will not save it.

## Relationship to the planning flow

The diagram is a summary for humans, not the source of truth for requirements. In Plan mode, `ExitPlanMode` still submits the full text plan; the diagram goes before that submission so the user sees the scope at a glance before approving. Decisions the user makes off the diagram must also land back in the text plan / ExecPlan — a decision that lives only in a diagram is not recorded.
