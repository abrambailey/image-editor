# Image Editor

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS desktop application.

## Stack

SwiftUI and AppKit, packaged as a local .app; BiRefNet Lite through Core ML for on-device foreground segmentation. The bundled 1024-pixel model replaces Apple's instance segmentation after the user's Allure fixture exposed lost wires and overly soft product edges.

## Users

The user prepares hearing-aid product images collected from the web on their Mac.

## Product Purpose

Quickly isolate a product, arrange it on a precisely sized canvas with appropriate padding, and export an image ready for publication.

## Capabilities and Constraints

- Open, paste, or drop images; accept direct web image URLs.
- Crop to a rectangular selection with exact pixel dimensions, preserving source pixels and supporting Undo.
- Change canvas width and height independently.
- Remove backgrounds using AI and retain genuine alpha transparency.
- Drag and resize the subject, center it, and fit it within specified padding.
- Export transparent PNG or JPEG with an adjustable quality setting.
- Export visible image bounds by default; optionally include canvas padding to retain the full canvas dimensions.
- Copy the edited image as a full-quality PNG using the same export bounds to paste into another app without saving a file.
- Optional Sunburst cloud editing from a natural-language instruction and optional painted selection, with original/result comparison, optional feathered local blending, and Undo.
- Multiple image layers per canvas, independent image tabs in one window, and paste/open destination choices. Select, reorder, rename, show/hide, duplicate, and delete layers with Undo. macOS 14+. Local editing needs no cloud account; Sunburst requires an OpenAI API key and separate API billing.
- Double-click a tab to rename it; its name is suggested for PNG/JPEG export. Tabs keep separate Undo histories, and the last five closed tabs can be reopened during the session.
- Editable layers are retained only in the current session; there is no saved layered-project format. PNG/JPEG exports and PNG clipboard copies flatten visible layers. Sunburst edits the whole canvas and flattens on Apply; Undo restores the prior layer stack.
- A dot marks work not exported to a file. Closing a changed tab, closing the window, or quitting offers Export, Cancel, and Don’t Export. Only successful file writes acknowledge the exported state; canceled or failed saves and clipboard copies do not. Explicitly discarded tabs may leave the five-tab recovery cache.

## Product Principles

- Preserve product details and original pixels wherever possible.
- Keep the import, cutout, fit, export workflow short.
- Make dimensions, transparency, and export behavior explicit.
- Support familiar Mac keyboard, clipboard, and file interactions.
