# Development and verification

[Back to the overview](../README.md) · [Contributing](../CONTRIBUTING.md)

Run the commands below from the repository root.

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

Tests cover transparency, placement, alpha trimming, padding, output dimensions, JPEG flattening and quality, EXIF orientation, mask alignment and source-pixel preservation, replacement cutout placement, validation, undo/redo, crop preview isolation, exact cropped PNG/JPG output, repeated crops, and crop bounds. Build the app first, then run the actual model against a local image:

```sh
CUTOUT_TEST_IMAGE=/absolute/path/photo.jpg \
CUTOUT_TEST_OUTPUT=/tmp/photo-cutout.png \
./scripts/test.sh
```

The optional model test is skipped when no fixture is supplied. `CUTOUT_TEST_ALLURE=1` enables additional assertions for the maintainer’s private regression fixture, which is not shipped. Leave it unset when testing your own images. Core ML compilation and loading may be blocked by restrictive execution sandboxes.

Layer regression tests cover batch import and failure rollback, independent transforms, reordering, visibility, duplication/deletion, crop, compositing, transparent hit testing, paste choices, multiple Finder files, and AI flattening/Undo. Clipboard tests need access to the macOS pasteboard service. `window-test.sh` opens an isolated native window to verify multiple tabs, independent history, menu and clipboard routing, pending field commits, real double-click renaming, Return/Escape, the native Save panel’s suggested filename, and closing/reopening tabs. It requires a logged-in Mac desktop.

The native UI smoke test opens its own window, exercises numeric editing and undo, and optionally captures the content. It needs a logged-in Mac desktop, but no Accessibility or screen-recording permission:

```sh
./scripts/ui-test.sh --image /absolute/path/photo.png --compact --dark --capture /tmp/editor.png
```

Omit `--compact --dark` to check the standard light window. Add `--layers` to verify canvas layer selection, dragging, proportional resizing, Undo, and the paste choice. `--capture-paste /tmp/paste.png` captures the same paste sheet content in a direct native host because macOS sheet caching can produce a transparent bitmap. Add `--remove-background` to exercise removal, repeat-removal pixel equality, placement, and cutout undo/redo. Add `--crop` to verify selection, movement, edge/corner resizing, zoom, keyboard controls, pending crop dimensions, and undo/redo. Use `--capture-crop /tmp/editor-crop.png` to capture the selection before canceling it; `--capture` still records the normal editor. The capture excludes the system titlebar.

SwiftUI owns the window and inspector, AppKit draws and manipulates the canvas, and Core Graphics / ImageIO handle pixel-accurate exports. Background removal uses [BiRefNet Lite](https://github.com/ZhengPeng7/BiRefNet) with a [validated Core ML conversion](https://github.com/miracle2k/birefnet-lite-coreml). The 1024 × 1024 mask is resized to source resolution and multiplied into the original premultiplied RGBA pixels; source RGB is never generated or resized by the removal operation. No blanket feathering or erosion is added.

`scripts/prepare-model.sh` pins the model revision and verifies its SHA-256 archive checksum before compiling it. The build bundles the compiled model and MIT attribution files from `Resources/ThirdParty/BiRefNetLite`. Inference uses CPU-only mode, as validated by this conversion's author. On the development Mac, a 1200 × 675 test image took approximately 1.1 seconds for inference after loading; first-use model loading adds several seconds. These are local measurements, not guarantees for other Macs. Set `IMAGE_EDITOR_MODEL_PATH` to a compiled `.mlmodelc` directory for command-line tests or direct `swift run`; the packaged app resolves its bundled model automatically.

The app icon is original geometry drawn by `scripts/make-icon.swift`. Test-only screenshots and externally sourced images live in the ignored `.impeccable/review/` directory and are not included in the app.
