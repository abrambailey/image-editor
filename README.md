# Image Editor for Mac

A small native app for preparing hearing-aid product images: remove the background, crop, size the canvas, set padding, arrange the product, and export.

An experimental open-source app, distributed as source under the [MIT license](LICENSE).
Build it locally using the instructions below. Contributions and bug reports are
welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) for scope and support expectations.

<img width="2464" height="1824" alt="image" src="https://github.com/user-attachments/assets/dd7d5805-543c-4e9e-921f-ec623ced57fd" />

## Run

Requires macOS 14 or newer and Apple's Command Line Tools (`xcode-select --install`). The first build downloads an 82 MB model; background removal then runs entirely offline. No Python environment or server is needed. Optional Sunburst cloud editing requires your own OpenAI API key and API billing.

```sh
./scripts/run.sh
```

This builds and opens `dist/Image Editor.app`. After building, open that app directly from Finder. You can drag it into Applications if you want to keep it there. The build targets the Mac it runs on and uses a local ad-hoc signature; it is not a notarized distribution build.

## Typical workflow

1. Open one or more files, drag images into the window, or copy an image in your browser and press **⌘V**. When a canvas already has layers, Open and Paste ask whether to **Add as Layer(s)** or **Open in New Tab / Open in Separate Tabs**. The latter keeps your current canvas open and creates separate tabs in the same window. **File → Open Image from URL** accepts direct image URLs. Finder's **Open With** also works.
2. Select a layer, then click **Remove Background**. BiRefNet Lite runs locally through Core ML and produces a transparent cutout, including multiple foreground subjects. The first removal loads the model; subsequent removals reuse it. The original remains available through **Restore Original** and Undo.
3. Enter canvas width and height, or use a preset. Changing canvas size preserves every layer's scale and its offset from the center.
4. Enter minimum padding in pixels and click **Fit & Center**. The selected layer keeps its aspect ratio; wider margins on two sides are expected when the image and canvas have different aspect ratios.
5. Click an image or its row in **Layers** to select it. Drag the selected image to move it, or drag any corner to resize proportionally. Center guides snap into place; hold **Option** to bypass snapping. With the canvas focused, use arrow keys for one-pixel moves or **Shift + arrow** for ten pixels. The X/Y fields position the image's top-left corner precisely.
6. To crop, click **Crop** in the toolbar (or press **⇧⌘X**), then drag out the area to keep. Move the selection by dragging inside it, or resize using its edges and corners. The inspector also accepts exact X/Y, width, and height in canvas pixels. Click **Apply Crop** or press **Return** with the canvas focused; **Cancel** or **Esc** leaves the image unchanged.
7. Choose **PNG** for transparency, or **JPG** and a quality percentage. By default, export uses only the visible image bounds, excluding surrounding canvas padding. Turn on **Include canvas padding** to keep the full canvas dimensions and margins. Click **Export** to choose the filename and location. Transparent pixels become white in JPG. Choosing a white or black canvas uses that color behind the image in either format.

To use the edited image without saving a file, click **Copy Image** in the toolbar or below Export, press **⌘C** with the canvas focused, or use **⇧⌘C** regardless of focus. When editing text, **⌘C** still copies the selected text. Paste into another app with **⌘V**. Copy always uses a full-quality PNG and follows **Include canvas padding**, just like file export. Your edits, scale, crop, and canvas background are retained. A transparent background stays transparent, even when JPG is selected for file export. Excluding canvas padding preserves white pixels within the source image and all nonzero alpha, including faint edges and shadows.

Cropping sets the canvas dimensions to the selected area, keeping all layers at their current scale and preserving their relative positions. Enable **Include canvas padding** to export that exact rectangle, including any empty space. Cropping is nondestructive: pixels outside the canvas are hidden, and Undo restores the previous canvas and placement in one step. Moving the image, expanding the canvas, or using Fit & Center afterward can reveal those pixels again. While cropping, arrow keys move the selection by one pixel (**Shift + arrow** for ten); **Reset Selection** selects the full canvas. Apply or cancel before making other edits or exporting.

The **Layers** panel lists the frontmost layer first. **Add Images…** (or **⌥⌘O**) adds all selected files to the current canvas in one Undo step; dropping multiple files does the same. New layers start centered and fitted to the canvas, so overlapping images can be selected in the panel. Use the up/down arrows to change stacking order, the eye to show or hide a layer, and the duplicate or trash buttons to manage the selected layer. Right-click a row to rename it. **Delete** with the canvas focused deletes the selected layer; **⌘Z** restores it. Hidden layers stay editable through the panel but do not appear in exports. Show a hidden layer before moving or resizing it.

Each image tab has independent layers, canvas settings, and Undo history. **⌘N** or the + beside the tabs creates an empty tab. Double-click a tab to rename it inline (or use **Tab → Rename Tab**). **Return** commits, **Escape** cancels, and the name becomes the suggested filename for PNG/JPG export. Renaming supports Undo. **⌘W** closes a tab; **⇧⌘T** reopens the most recently closed tab, retaining its edits. The last five closed tabs stay in memory until the app quits. Use the tab menu at the right of the strip to reach tabs beyond the visible area. Paste into an empty canvas starts its first layer directly. Paste into an existing canvas always asks where to put the image; **Cancel** leaves the canvas unchanged. Copy and Export combine all visible layers. Background removal, edge cleanup, Restore Original, and position/scale controls affect only the selected layer; crop and canvas resizing affect every layer.

The checkerboard is a preview of transparency and never appears in exports. Preview zoom does not affect exported dimensions. Import trims transparent borders, so fitting and centering use the visible subject. Removal preserves the current placement; click Fit & Center to apply padding to the new cutout. Repeating removal starts from the preserved original or the last accepted AI image, avoiding cumulative edge damage and replacing any optional white-edge cleanup.

If a white halo remains, choose **Refine Cutout → Clean White Edges**. This removes near-white regions connected to the outside or transparency, while preserving enclosed white details. It can also remove very light product edges, so inspect the result and use Undo when needed. Exact X/Y and scale controls are inside **Position & scale**.

## Keeping your work

A dot beside a tab name means its current state has not been exported to a file.
Closing that tab offers **Export…**, **Cancel**, and **Don’t Export**. Quitting or
closing the window checks every unexported tab in turn. Canceling a save panel or
a later confirmation keeps the remaining work open. Failed exports never close
a tab. Finish or cancel an active crop, AI dialog, or import before quitting.

Only a successful file export clears the dot. Copying to the clipboard does not,
because clipboard contents can be replaced. Editing after export marks the tab
again; Undo back to the exported state clears it. Changing the export format,
JPG quality, or canvas-padding option also requires a new export.

Exports save a flattened PNG or JPG, not editable layers or Undo history. There
is still no autosave or recovery after a crash or forced quit. The last five
closed tabs can be reopened while the app runs; choosing **Don’t Export** allows
that tab to be discarded when it leaves this list or the app quits.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New image tab | ⌘N |
| Rename image tab | Double-click tab or ⇧⌘R |
| Close / reopen tab | ⌘W / ⇧⌘T |
| Next / previous tab | ⇧⌘] / ⇧⌘[ |
| Open one or more images | ⌘O |
| Add images as layers | ⌥⌘O |
| Duplicate selected layer | ⌘J |
| Bring layer forward / send backward | ⌘] / ⌘[ |
| Delete selected layer | Delete (canvas focused) |
| Open image URL | ⇧⌘O |
| Paste | ⌘V |
| Paste image regardless of focus | ⇧⌘V |
| Start cropping | ⇧⌘X |
| Edit with Sunburst | ⇧⌘I |
| Apply / cancel crop | Return / Esc (canvas focused) |
| Remove background | ⇧⌘B |
| Fit & center | ⇧⌘F |
| Center selected layer | ⌘K |
| Export | ⇧⌘E or ⌘S |
| Copy image as PNG | ⌘C (canvas focused) or ⇧⌘C |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Zoom in / out | ⌘+ (or ⌘=) / ⌘− |
| Fit preview to window | ⌘0 |

## Edit with Sunburst

Open an image, then choose **AI Edit** in the toolbar or **Image → Edit with Sunburst…**. Describe the change in natural language. You can optionally enable **Paint a selection**, brush over the area to change, and undo strokes or clear the selection. Without a selection, the model locates the change from your instruction.

Expand **Connection** and enter an OpenAI API key. **Save in Keychain** stores it in this Mac’s Keychain; otherwise the key stays in memory for this editing session. **Forget** removes the saved key. The app also accepts `OPENAI_API_KEY` inherited at launch, although Finder-launched apps do not normally inherit shell environment variables. Keys are never written to the project or preferences.

**Generate Edit** sends the visible canvas, instruction, and optional mask directly to OpenAI’s `/v1/images/edits` API using `gpt-image-2.5-sunburst` at high quality. This incurs API charges separate from a ChatGPT subscription. The app makes one request per click, with no automatic retries. **Stop Waiting** cancels the local request; OpenAI may still complete and bill a request already received. Model access depends on the OpenAI project, billing, and any required organization verification.

Review **Original** and **Sunburst** before applying. Sunburst shows the full generated result by default, including any changes outside the requested area. When a selection was painted, **Blended** offers an optional version that uses the generated pixels only inside that selection. **Blend edge softness** feathers inward, preserving pixels outside the selection exactly in the working canvas. Inspect for seams, clipped changes, and mismatched lighting; blending cannot repair altered geometry. A broader selection may be needed for shadows or reflections. There is no automatic segmentation in this prototype.

Inputs with transparent pixels explicitly request `background=transparent` and PNG output, with instructions to preserve transparency when objects are removed. Other inputs keep automatic background selection; temporary aspect-ratio padding does not trigger transparent output. The returned alpha channel is retained through preview, application, and PNG export. The original alpha is not copied over the generated result, since removed or changed objects need a new silhouette.

**Generate Again** starts from the same original canvas. **Change Selection** discards the preview so you can revise the painted area. **Use Sunburst Result** or **Use Blended Result** applies the selected preview as one Undo step. Applying flattens the visible canvas into one image at the existing canvas dimensions; Undo restores every previous layer, its visibility, placement, and crop. Background removal subsequently starts from the accepted AI image. For a single-layer input, **Restore Original** still restores the originally imported image. For a multiple-layer input, it restores the composite canvas sent to Sunburst; use Undo immediately after Apply to recover the separate layers.

Generation uses dimensions divisible by 16, at most 2,048 pixels per edge; the result is aligned back to the canvas dimensions. Very wide or tall images are padded to the API’s supported aspect ratio and unpadded afterward. A full result may lose fine detail on larger canvases; blending preserves original detail outside the selection. The mask is guidance for Sunburst, not a guarantee of pixel preservation. See [OpenAI’s image-editing documentation](https://developers.openai.com/api/docs/guides/image-generation#edit-an-image-using-a-mask).

## Limits

- Multiple image layers and separate image tabs are supported. Up to 25 edits per tab are retained in memory. PNG/JPG exports combine visible layers; there is no editable project-file format or automatic recovery after quitting. Export finished work before closing.
- Canvas dimensions are 1–8,192 pixels. Imports over 8,192 pixels on their longest side are downsampled; files and downloads over 50 MB are rejected. Animated images import their first frame.
- Background removal is foreground segmentation, not a generative LLM edit. It preserves source image detail but can miss thin wires, translucent parts, or subjects that blend into the background. Inspect the cutout at higher zoom and use Undo or Restore Original if needed. Its cutout mask cannot be painted manually; the brush in AI Edit guides Sunburst edits only.
- Direct image downloads depend on the source website allowing them. When a site blocks downloads or supplies a webpage instead, copy the actual image or save it locally first.
- PNG is lossless; JPG quality changes compression, not the canvas dimensions. Exports use sRGB.

## Development and verification

The GitHub Actions workflow compiles the source and runs
`./scripts/test.sh --headless`. That mode explicitly skips clipboard checks;
run the full suite on a logged-in Mac for clipboard and native-window coverage.
CI uses no API credentials and does not publish a downloadable app.

AI tests use a mock service: they verify request construction, API error handling, mask orientation, image sizing, preservation outside the selection, preview isolation, application, Undo/Redo, failure, and cancellation. They do not establish Sunburst output quality or live account access. Use `--ai-edit` with the native UI smoke test and `--capture-ai-selection`, `--capture-ai-result`, or `--capture-ai-blend` to capture its clearly labeled mock previews without API charges.

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/window-test.sh
```

Tests cover transparency, placement, alpha trimming, padding, output dimensions, JPEG flattening and quality, EXIF orientation, mask alignment and source-pixel preservation, replacement cutout placement, validation, undo/redo, crop preview isolation, exact cropped PNG/JPG output, repeated crops, and crop bounds. Build the app first, then run the actual model against a local product image:

```sh
CUTOUT_TEST_IMAGE=/absolute/path/product.jpg \
CUTOUT_TEST_OUTPUT=/tmp/product-cutout.png \
./scripts/test.sh
```

The optional model test is skipped when no fixture is supplied. For the user's original 1200 × 675 Allure JPEG, also set `CUTOUT_TEST_ALLURE=1` to check the receiver wire, hook opening, body edge widths, shadows, and opaque source pixels. The private fixture is not shipped. Core ML compilation and loading may be blocked by restrictive execution sandboxes.

Layer regression tests cover batch import and failure rollback, independent transforms, reordering, visibility, duplication/deletion, crop, compositing, transparent hit testing, paste choices, multiple Finder files, and AI flattening/Undo. Clipboard tests need access to the macOS pasteboard service. `window-test.sh` opens an isolated native window to verify multiple tabs, independent history, menu and clipboard routing, pending field commits, real double-click renaming, Return/Escape, the native Save panel’s suggested filename, and closing/reopening tabs. It requires a logged-in Mac desktop.

The native UI smoke test opens its own window, exercises numeric editing and undo, and optionally captures the content. It needs a logged-in Mac desktop, but no Accessibility or screen-recording permission:

```sh
./scripts/ui-test.sh --image /absolute/path/product.png --compact --dark --capture /tmp/editor.png
```

Omit `--compact --dark` to check the standard light window. Add `--layers` to verify canvas layer selection, dragging, proportional resizing, Undo, and the paste choice. `--capture-paste /tmp/paste.png` captures the same paste sheet content in a direct native host because macOS sheet caching can produce a transparent bitmap. Add `--remove-background` to exercise removal, repeat-removal pixel equality, placement, and cutout undo/redo. Add `--crop` to verify selection, movement, edge/corner resizing, zoom, keyboard controls, pending crop dimensions, and undo/redo. Use `--capture-crop /tmp/editor-crop.png` to capture the selection before canceling it; `--capture` still records the normal editor. The capture excludes the system titlebar.

SwiftUI owns the window and inspector, AppKit draws and manipulates the canvas, and Core Graphics / ImageIO handle pixel-accurate exports. Background removal uses [BiRefNet Lite](https://github.com/ZhengPeng7/BiRefNet) with a [validated Core ML conversion](https://github.com/miracle2k/birefnet-lite-coreml). The 1024 × 1024 mask is resized to source resolution and multiplied into the original premultiplied RGBA pixels; source RGB is never generated or resized by the removal operation. No blanket feathering or erosion is added. This replaces Apple's lower-resolution instance mask, which lost wires and softened product contours on the Allure fixture.

`scripts/prepare-model.sh` pins the model revision and verifies its SHA-256 archive checksum before compiling it. The build bundles the compiled model and MIT attribution files from `Resources/ThirdParty/BiRefNetLite`. Inference uses CPU-only mode, as validated by this conversion's author. On the development Mac, the Allure fixture took approximately 1.1 seconds for inference after loading; first-use model loading adds several seconds. These are local measurements, not guarantees for other Macs. Set `IMAGE_EDITOR_MODEL_PATH` to a compiled `.mlmodelc` directory for command-line tests or direct `swift run`; the packaged app resolves its bundled model automatically.

The app icon is original geometry drawn by `scripts/make-icon.swift`. Test-only screenshots and externally sourced images live in the ignored `.impeccable/review/` directory and are not included in the app.

## License and security

The application is [MIT licensed](LICENSE), copyright 2026 Abram Bailey. BiRefNet
and its Core ML conversion retain their own MIT notices in
[`Resources/ThirdParty/BiRefNetLite`](Resources/ThirdParty/BiRefNetLite/NOTICE).
See [SECURITY.md](SECURITY.md) for data handling and vulnerability reporting.
