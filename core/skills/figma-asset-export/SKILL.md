---
name: figma-asset-export
description: Rules for exporting assets from Figma (icons / illustrations / logos) into an iOS project — deciding export vs reproducing with the design system / SF Symbol, choosing the export format, never redrawing from geometry. Use when: exporting assets from figma / exporting custom icons / illustrations / logos into iOS, deciding export vs reproduce, choosing an export format, diagnosing "icon asset renders in the wrong color / too large / blurry". Skip when: no custom assets this round (all icons come from the design system / SF Symbol) / not iOS / the user exports assets by hand.
---

# figma-asset-export

Rules for exporting assets from Figma into iOS. The figma MCP **can export assets**: for a node containing exportable assets, `get_design_context` returns **asset download URLs** (SVG / PNG) — that is the export entry point (`get_screenshot` is a whole-node raster, not an asset export). The essentials: first decide **whether to export at all**, then pick the **format**, and finally **use the exported file, do not redraw from geometry**.

## Triggers / does not trigger

Triggers:

- exporting assets from figma / exporting custom icons / illustrations / logos into iOS
- deciding whether a given graphic should be exported or reproduced with the design system / SF Symbol
- choosing an export format (vector vs @1x/@2x/@3x)
- diagnosing "the exported asset renders in the wrong color / too large / blurry / misaligned"

Does not trigger:

- no custom assets this round (all icons come from the design system / SF Symbol)
- not iOS
- the user explicitly exports assets by hand

## Step 1: export the asset, or reproduce it in code?

| Graphic | What to do |
|---|---|
| Already a design-system component / expressible as an SF Symbol | **Do not export** — use the component / SF Symbol (resolve to the real component when Code Connect exists); size / optical conventions are already encoded in the component |
| Plain monochrome simple shape (arrow / check / plus, etc.) approximable by an SF Symbol | SF Symbol first; export only under pixel-level requirements |
| Custom icon / illustration / logo / multi-color graphic / brand asset | **Export** — code cannot draw it, and what it draws will drift |

## Export mechanics (how to get the file)

1. `get_design_context({nodeId})` → the return includes **asset download URLs** (exportable nodes / image-fill nodes). figma gives **SVG / PNG** URLs, **not PDF directly** (PDF is an SVG→PDF conversion on the iOS side).
2. `curl -sL "<asset_url>" -o .specs/<slug>-assets/<semantic-name>.<svg|png>` downloads the exported file.
3. **Export box = the outer frame, not the cropped path**: a figma icon is usually a fixed outer frame wrapping a smaller glyph + optical padding; the export must carry the outer-frame padding (otherwise the asset is cropped to the glyph bbox and renders too large / breaks alignment). A known MCP bug crops the SVG to the path bbox → check the size after downloading and, if needed, set the box explicitly to the metadata outer-frame size.

## Step 2: format selection (iOS)

| Asset type | figma export format | iOS handling |
|---|---|---|
| Monochrome, scalable (most icons) | **SVG** (figma gives SVG, not PDF) | Into the asset catalog (Xcode 12+ takes SVG directly, or convert to PDF on the iOS side), check **Preserve Vector Data** + **Single Scale**; set render to **template** and **tint** with a `<DesignSystemPackage>` / Color token (**do not hard-code the color**) |
| Multi-color vector (illustration / color logo) | **SVG** | Same, but render **original** (keeps the colors) |
| Bitmap / photo / complex gradient | **PNG** | Put **one each at @1x / @2x / @3x** in the `.imageset` (pt size = the @1x one); the device picks by scale automatically |

- **Monochrome icons must be template + token tint**: cross-check against the design token name (via figma-precise-extract's variable_defs), do not hard-code hex — that is what keeps colors from bleeding in dark mode / multi-theme.
- On iOS 18, SVG straight into the asset catalog also works; older projects conventionally convert to PDF. Follow the project's existing practice.

## Do not redraw from geometry

Once you have the exported file, **use it**; do not read `get_design_context`'s path data and redraw a `Path` / assemble shapes in code. Even when the frozen HTML (see `figma-precise-extract`) contains inline `<svg>` paths, the implementation owner does not redraw from that geometry; icons use only the exported assets listed in the final plan.

## Where this sits in plan-first delivery

- **Root/source prep**: in Default mode, before any source is written, freeze the exported assets into `.specs/<slug>-assets/` and write the format, render mode and tint token into the final plan or ExecPlan. Asset export sits alongside the measurement HTML: the former gives binary assets, the latter layout measurements.
- Include file/node/version (when available) and each exported asset's SHA-256 in the design binding; with no immutable version, accept against the frozen bundle only and do not re-download latest during review.
- If the export result raises new behavior, scope, architecture or acceptance decisions, Root returns to DISCOVER/PLAN_READY to update the authoritative plan before implementation continues.
- **implementation owner**: wires the frozen assets into the asset catalog and sets template/original, tint token and Preserve Vector Data; when the design source changes Root re-freezes, assets are not swapped ad hoc during implementation.
- **ui-reviewer**: after a runnable build PASSes, checks size, color and sharpness against the frozen PNG.

## Hard constraints

- ❌ Do not use `get_screenshot` as an asset export (it is a whole-node raster, not an asset file)
- ❌ Do not redraw custom icons / illustrations in code from path geometry
- ❌ Do not hard-code hex colors in monochrome icons — template + token tint
- ❌ The implementation worker does not re-export assets; frozen assets and the shared list are managed by Root
- ✅ Export custom assets via `get_design_context` asset URLs (figma gives SVG / PNG); export box = the outer frame
- ✅ Monochrome scalable → SVG (used directly in Xcode or converted to PDF) template + token tint; multi-color → original; bitmap → @1x/2x/3x

## Why (core)

The two root causes of asset drift are code redraws losing optical detail, and exports cropped to the glyph bbox or with hard-coded colors. Freeze the assets first; the implementation owner only wires them in.
