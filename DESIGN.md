---
name: Image Editor
description: A native Mac photographic light table for precise product-image preparation.
colors:
  checker-light: "rgb(98% 98% 98%)"
  checker-shade: "rgb(90% 90% 90%)"
  handle-fill: "#ffffff"
typography:
  headline:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "22px"
    fontWeight: 600
  title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  label:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "11px"
    fontWeight: 400
  metadata:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "10px"
    fontWeight: 400
rounded:
  field: "5px"
  handle: "1.5px"
  busy: "12px"
spacing:
  field-inset: "8px"
  control-gap: "10px"
  group-gap: "12px"
  section-inset: "18px"
  dialog-inset: "24px"
components:
  pixel-field:
    rounded: "{rounded.field}"
    height: "28px"
    padding: "0 {spacing.field-inset}"
---

# Design System: Image Editor

## Overview

**Creative North Star: "The Photographic Light Table"**

A quiet, precise Mac workbench lets the product image carry the visual weight. Neutral system surfaces, compact controls, and familiar Mac interactions keep attention on image boundaries, placement, and export settings.

This document records the built SwiftUI/AppKit system. The frontmatter's CSS-compatible lengths represent native layout points at 1×; its font stack is the portable equivalent of the macOS system font. Fixed checker values describe AppKit calibrated-white inputs. Dynamic system colors and native control metrics remain owned by macOS, rather than frozen to one screenshot.

**Key Characteristics:**

- Dominant image workspace with compact supporting controls.
- Native system type, SF Symbols, and appearance-aware surfaces.
- Explicit pixel units and stable numeric alignment.
- Selection and transparency remain visually distinct.

## Colors

A restrained neutral palette uses the system accent for actions and selection, with system pink reserved for transient center guides.

### Primary

- **System Accent:** SwiftUI `Color.accentColor` and AppKit `NSColor.controlAccentColor` identify prominent actions, focused numeric fields, selection handles, and accepted drops. The reviewed environment renders it blue; the implementation follows system settings.

### Secondary

- **Alignment Pink:** `NSColor.systemPink` draws center guides while an image snaps during dragging.

### Neutral

- **Window Surround:** `NSColor.windowBackgroundColor` under the canvas.
- **Inspector Surface:** `NSColor.controlBackgroundColor` behind controls.
- **Field Surface:** `NSColor.textBackgroundColor` inside numeric inputs.
- **System Ink:** SwiftUI primary/secondary foreground styles and AppKit `secondaryLabelColor` distinguish content from labels and metadata.
- **Checker Light / Checker Shade:** the fixed frontmatter pair makes transparent pixels visible in either appearance.
- **Handle White:** the fixed handle-fill token keeps corner handles legible against the image.

**The Appearance Rule.** Keep interface colors semantic; image pixels and transparency indicators retain their own colors when macOS appearance changes.

## Typography

**Display Font:** macOS system font (SF), used sparingly for the empty state.
**Body Font:** macOS system font (SF).
**Label/Mono Font:** the same system family, with monospaced digits for measurements and percentages.

### Hierarchy

- **Headline:** the frontmatter headline role introduces the empty workspace.
- **Title:** inspector headings and the toolbar filename use the title role.
- **Body:** empty-state instructions use the body role; native controls retain system sizing.
- **Label:** field labels, helper text, canvas dimensions, disclosure labels, and status use the label role.
- **Metadata:** toolbar dimensions and unit suffixes use the metadata role.

Line height follows the system. Empty-state instructions add four points of line spacing. SF Symbols use native rendering; the empty-state symbol is an ultra-light photo illustration.

## Layout

The spatial grammar is one dominant workspace beside a compact inspector, separated by native dividers. Controls align to a shared inset and stack in small, readable groups. The frontmatter records the repeated spacing values; paired fields use the control gap.

For the editor's exact composition, window sizes, and workflow order, see its [surface brief](.impeccable/surfaces/sources-imageeditor-editorview-swift.md). At smaller supported window sizes, the inspector content scrolls and its export area stays available. The canvas scales with the remaining space. This native desktop implementation has no web or mobile breakpoint system.

## Elevation & Depth

Flat system surfaces and dividers organize controls. A single ambient shadow lifts the image canvas from its surround: AppKit `NSShadow`, black at 16% opacity, offset `(0, -3)`, blur radius 14 points. The busy overlay uses native regular material. Other button, menu, sheet, and alert depth comes from macOS.

**The Canvas Depth Rule.** Keep custom elevation concentrated on the image canvas; preserve native material behavior for dialogs and transient controls.

## Shapes

The image canvas and its selection boundary are rectangular. Small rounded numeric fields, softly rounded handles, and the rounded busy overlay use the frontmatter radii. Native buttons, menus, segmented controls, and sheets keep platform-owned shapes.

Numeric field borders use primary ink at 18% opacity and a half-point stroke; focus replaces this with a two-point accent stroke. The selection outline is one point in accent at 80% opacity. Corner handles are eight-point white squares with an accent outline.

## Components

### Buttons

Prominent native buttons mark empty-state import and inspector export. Secondary actions use standard Mac buttons; toolbar actions pair concise names with SF Symbols. Hover, pressed, disabled, and keyboard behavior follow native controls. Editing actions disable without an image and while work is busy.

### Inputs / Fields

`PixelField` pairs a secondary label with an inset numeric value and trailing unit. Digits align consistently. Partial edits stay local until Return, focus loss, or a consuming action commits them. Values round and clamp to the field range; invalid text restores the current value. The explicit accent focus border remains visible.

### Inspector

Plain stacked sections use headings and dividers, with menus for presets and refinement. Position and scale expand through a native disclosure group. Export uses a native PNG/JPG segmented picker; JPG reveals a quality slider and background explanation.

The scrolling form and fixed Export controls share a content width: the 276-point inspector minus its two 18-point insets and the native regular scrollbar width. The form stays leading-aligned whether the native scrollbar overlays its viewport or consumes space. This preserves the right-side gutter without double-counting it when the form overflows, and keeps the controls aligned when an overlay scrollbar fades out.

### Sunburst layer selection

The AI inspector starts with Layers to edit: native checkboxes beside 28-point image thumbnails, layer names, and an eye-slash symbol for hidden layers. Rows follow the layer inspector’s front-to-back order, with the active layer checked initially. The preview displays only the chosen input. The helper states whether Apply edits one layer in place or combines several; the fixed Apply area repeats this scope. Other layers retain their pixels and placement. Choices lock while generating and reviewing; Change Layers discards the preview before reopening the picker. Empty selection disables generation and painting. The existing scrolling inspector, native controls, semantic colors, and fixed action area remain.

Verification: 46 regression checks completed with zero failures and one optional Core ML fixture skipped. Native checkbox, painting, preview, single-layer Apply, partial-merge Apply, and Undo checks passed at default/light and minimum/dark sizes. Evidence: `.impeccable/review/ai-layers-{desktop,compact}{,-selection,-result,-merge}.png`. All generated previews use a labeled mock service; no live request was sent. Release build and signature verification passed.

### Canvas

A ten-point checkerboard represents alpha. Dragging moves the selected image; corner dragging preserves aspect ratio. Center snapping displays pink guides, with Option disabling snapping. Arrow keys move one pixel, or ten with Shift. Dimension text sits above the canvas; zoom controls describe preview fit in the status bar.

### Layer crop and pixel selections

Each layer row has a `crop` SF Symbol button beside visibility. Crop Layer trims that layer’s source pixels while preserving its scale and position; Fit & Center uses the new dimensions. Crop Canvas remains in the toolbar and Image menu, explicitly naming its scope. Layer crop fields use source pixels; canvas crop fields use canvas pixels. Both retain the existing thirds grid, eight handles, fixed Apply/Cancel controls, and Undo. Layer crop previews fit the full layer even when it extends outside the canvas.

A compact icon toolbar sits 10 points inside the workspace’s upper-left corner, without consuming canvas height. A hand, dashed rectangle, and dashed circle offer Move, Rectangle, and Ellipse, with tooltips and accessibility labels. An accent background marks the active tool. Shift constrains square/circle drawing. The marquee uses a contrasting black/white dashed outline, distinct from the accent layer transform handles. The selection inspector names the affected layer and explains the shortcuts. Its fixed bottom area contains Copy Selection, Delete Selected Pixels, and Deselect & Move, keeping these available at minimum window size. Export remains in the toolbar and menus while selecting.

Delete clears only the selected layer’s pixels. Standard Copy follows text focus, copies a selection when drawing tools are active, and copies the composition in Move mode. Copy Image always retains its composition/export meaning. Selection PNGs preserve native resolution and transparent ellipse corners; a private clipboard placement record allows Paste to add a new layer at the existing scale and position. Empty selection Delete is a no-op. Escape or Command-D returns to Move, and Undo restores pixel edits.

Verification covers source-pixel crop and Fit & Center, scaled and partially overlapping selections, pixel orientation/alpha, clipboard placement, layer isolation, and Undo/Redo. The regression suite completed 42 checks with zero failures and one optional Core ML fixture skipped. Native light/default and dark/minimum checks cover crop handles, square/circle drawing, Delete, clipboard responder routing, Paste, and off-canvas layer cropping. The release build and signature verification passed. Evidence: `.impeccable/review/layer-crop-{desktop,compact}.png`, `selection-{desktop,compact}.png`, and `pixel-tools-{desktop,compact}.png`; native content captures omit the toolbar/titlebar and may omit compositor materials. The existing photographic light-table design is retained.

### Layer expansion

An outward-arrows SF Symbol on every layer row opens Expand Layer, also available in the Layer menu and row context menu. The native sheet offers Pixels / Percent, All sides / Individual sides, White / Color / Transparent fill, a native color picker for custom colors, and a live resulting-size readout. Percentages apply to each edge against the current width or height; the helper explicitly describes this. Zero, malformed, negative, or oversized amounts cannot be applied. Cancel and Expand Layer remain the sheet’s final actions. Existing source pixels, interior transparency, scale, and placement survive expansion; Fit & Center includes the new border. Applying records one Undo step.

Verification: 44 regression checks completed with zero failures and one optional Core ML fixture skipped. Native light/default and dark/minimum checks exercise the actual icon controls and layer-row expand button, all-side percentages, individual-side pixels, custom color, invalid sizes, Cancel, and Undo. Release build and signature verification passed. Evidence: `.impeccable/review/icon-tools-{desktop,compact}.png` and `expansion-{desktop,compact}.png`. Dialog captures use the actual sheet view in a direct native host with the same field edits, because macOS sheet caching omits compositor surfaces. No new raster assets or design tokens ship.

### Empty, busy, and error states

The empty state centers an SF Symbol, short instructions, and Open Image / From URL actions. Its full overlay accepts image drops. Busy work displays a progress indicator and message on regular material. Errors use a native alert with a concise title and the specific failure message.

### Toolbar and dialogs

The native toolbar places import actions at navigation placement, document identity in the principal area, and background removal/export at primary-action placement. File opening and export use native panels. The URL sheet has an initially focused address field, Cancel, and a default Open Image action enabled by a valid HTTP(S) address.

The two-line document title has 12-point horizontal and four-point vertical insets, with a bounded width and middle truncation for long filenames. On macOS 26 and newer its shared toolbar background is hidden, keeping passive document identity visually separate from toolbar buttons. Background removal uses the available `wand.and.stars` SF Symbol in both the toolbar and inspector.

## Do's and Don'ts

### Do:

- **Do** use semantic macOS colors and native control states.
- **Do** keep pixel units visible and numeric digits aligned.
- **Do** distinguish transparency, selection, and alignment with their established treatments.
- **Do** keep actionable fields and fixed export controls usable at the minimum window size.

### Don't:

- **Don't** hard-code the reviewed blue accent as the app's permanent palette.
- **Don't** replace native menus, dialogs, or SF Symbols with unrelated visual systems.
- **Don't** render the checkerboard, selection outline, or alignment guides into exported images.
- **Don't** turn helper labels into display typography.

Sources: `Sources/ImageEditor/EditorView.swift`, `CanvasView.swift`, `ImageEditorApp.swift`, and `EditorModel.swift`. Initial render evidence: `.impeccable/review/desktop-verified.png` and `compact-verified.png`. Toolbar spacing and symbol corrections are shown in `.impeccable/review/toolbar-empty-fixed.png`; final compact form/export alignment is shown in `.impeccable/review/inspector-compact-fixed.png`. Toolbar captures cache the app's own native window views, so compositor effects are not fully represented.
