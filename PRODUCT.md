# Image Editor

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS desktop application.

## Stack

SwiftUI and AppKit, packaged as a local .app; BiRefNet Lite through Core ML for on-device background removal, with optional cloud image editing through OpenAI.

## Users

Mac users making everyday edits to photos, screenshots, and graphics, combining images, or using AI to change an image.

## Product Purpose

Make quick image edits in a lightweight native app: crop and resize, arrange layers, remove backgrounds, optionally edit with AI, and export or copy the result into another app.

## Capabilities and Constraints

- Open, paste, or drop images; accept direct web image URLs.
- Crop individual layers to a rectangle with exact source-pixel dimensions; Fit & Center uses the cropped layer. Crop Canvas separately changes the canvas boundary, keeping layer pixels intact. Both support Undo.
- Draw rectangular or elliptical pixel selections on the selected layer; Shift constrains squares/circles. Delete clears selected pixels, Copy Selection writes transparent PNG, and Paste adds the selection as a new layer at its existing scale and position.
- Expand individual layers with pixel or percentage amounts, linked across all sides or set separately. Fill only the new area with white, a custom color, or transparency; preserve original pixel placement and support Undo.
- Change canvas width and height independently.
- Remove backgrounds using AI and retain genuine alpha transparency.
- Drag and resize the subject, center it, and fit it within specified padding.
- Export transparent PNG or JPEG with an adjustable quality setting.
- Export visible image bounds by default; optionally include canvas padding to retain the full canvas dimensions.
- Copy the edited image as a full-quality PNG using the same export bounds to paste into another app without saving a file.
- Optional Sunburst cloud editing from a natural-language instruction and optional painted selection, with original/result comparison, optional feathered local blending, and Undo.
- Multiple image layers per canvas, independent image tabs in one window, and paste/open destination choices. Select, reorder, rename, show/hide, duplicate, and delete layers with Undo. macOS 14+. Local editing needs no cloud account; Sunburst requires an OpenAI API key and separate API billing.
- Double-click a tab to rename it; its name is suggested for PNG/JPEG export. Tabs keep separate Undo histories, and the last five closed tabs can be reopened during the session.
- Editable layers are retained only in the current session; there is no saved layered-project format. PNG/JPEG exports and PNG clipboard copies flatten visible layers. Sunburst defaults to the active layer and allows selecting more: Apply edits one layer in place or combines only the selected layers. Undo restores the prior layer stack.
- A dot marks work not exported to a file. Closing a changed tab, closing the window, or quitting offers Export, Cancel, and Don’t Export. Only successful file writes acknowledge the exported state; canceled or failed saves and clipboard copies do not. Explicitly discarded tabs may leave the five-tab recovery cache.

## Product Principles

- Preserve image details and original pixels wherever possible.
- Make common edits easy to reach without requiring a fixed sequence of steps.
- Keep cloud AI optional and let users compare results before applying them.
- Make dimensions, transparency, and export behavior explicit.
- Support familiar Mac keyboard, clipboard, and file interactions.
