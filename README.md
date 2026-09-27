# Image Editor for Mac

A lightweight, native image editor for macOS with layers, local background removal, and optional AI editing. Crop and resize photos, arrange screenshots or graphics on a canvas, and export or copy the result into another app.

Free and open source under the [MIT license](LICENSE). Currently available to build from source.

<img width="2578" height="2182" alt="image" src="https://github.com/user-attachments/assets/7530be65-0b07-4f69-b6b7-09f6d523e54d" />

## Features

- **Crop, resize, and arrange.** Crop individual layers, set exact canvas dimensions, fit and center cropped images, and add padding around your composition. Canvas cropping remains a separate action.
- **Expand a layer.** Add a border in pixels or percentages, with one amount for all sides or separate amounts for each edge. Choose white, a custom color, or transparency.
- **Select pixels.** Draw rectangles or ellipses (Shift for squares or circles), delete selected pixels, or copy and paste the selection as a new layer.
- **Work with layers and tabs.** Combine images, reorder or hide layers, and keep several edits open with separate Undo histories.
- **Remove backgrounds locally.** Create transparent cutouts on your Mac, clean up white edges, and restore the original image when needed. Background removal runs offline after the first build downloads its model.
- **Edit with AI.** Describe a change in words, optionally paint the area to edit, and compare the result with the original before applying it. Blend a selected area back into your image for more control.
- **Export or copy.** Save transparent PNGs or adjustable-quality JPGs, or copy the edited image straight into another app. Export the visible image bounds or include the full canvas.
- **Use familiar Mac controls.** Open files, drag and drop, paste from the clipboard, or load an image from a URL. Undo and Redo are available throughout, and close/quit prompts help protect unexported work.

## Layer tools

Each layer row has a **crop icon** that trims that layer's actual pixels. **Fit & Center** then uses the cropped dimensions. **Crop Canvas** in the toolbar changes the canvas boundary while retaining the layers' pixels.

The **outward arrows** beside Crop open **Expand Layer**. Set pixels or percentages for all sides or individual edges, choose a fill, and review the resulting dimensions before applying. Percentages apply per side against the current width or height. Expansion keeps the existing image in place; Fit & Center includes the new border. Both layer cropping and expansion support Undo.

The corner toolbar has a **hand** for moving layers, a **dashed rectangle**, and a **dashed circle** for pixel selections. Hold **Shift** while drawing for a square or circle. With the canvas focused, **Delete** clears the selected layer's pixels, **⌘C** copies the selection, and **⌘V** pastes it as a new layer. **Esc** or **⌘D** returns to Move. **Copy Image** still copies the whole visible composition.

See the [user guide](docs/USAGE.md#crop-a-layer-or-the-canvas) for exact crop dimensions, expansion options, and selection behavior.

## Build and run

Requires **macOS 14 or newer** and Apple's Command Line Tools. Install the tools with `xcode-select --install` if needed, then:

```sh
git clone https://github.com/abrambailey/image-editor.git
cd image-editor
./scripts/run.sh
```

The first build downloads an 82 MB background-removal model. No Python environment, server, or API key is needed to build the app or use its local editing tools.

The script builds and opens `dist/Image Editor.app`. After that, open the app from Finder or move it to Applications. It is built for your Mac with a local ad-hoc signature; downloadable notarized builds are not currently provided.

## Optional AI editing

Choose **AI Edit**, describe the change, and optionally paint a selection. Review the generated result before applying it, or use Undo afterward. The app calls this feature **Sunburst**.

AI editing sends the visible canvas, your instruction, and any selection mask directly to OpenAI. It requires your own OpenAI API key and incurs API charges separate from a ChatGPT subscription. You can keep the key in memory or explicitly save it in your Mac's Keychain. Normal editing and local background removal need no cloud account.

See the [AI editing guide](docs/USAGE.md#ai-editing-with-sunburst) for selection blending, transparency, and cancellation behavior.

## Saving your work

Export saves a flattened PNG or JPG. A dot on a tab marks changes that have not been exported, and closing or quitting offers a chance to export them. Copying an image to the clipboard does not count as saving it.

This is an experimental app: editable layers and Undo history stay in memory, with no project-file format or autosave. Export work you want to keep. See [Keeping your work](docs/USAGE.md#keeping-your-work) for the close and recovery behavior.

## Limits

- Canvas dimensions are 1–8,192 pixels. Larger imports are downsampled; files and downloads over 50 MB are rejected. Animated images import their first frame.
- Background removal can miss fine or translucent details. AI edits can change areas outside a painted selection. Review the result before applying or exporting it.
- Applying an AI result combines the canvas into one layer. Undo restores the previous layers.

## Guides and contributing

- [User guide](docs/USAGE.md): layers, cropping, expansion, pixel selections, background removal, export settings, AI editing, and keyboard shortcuts.
- [Development and testing](docs/DEVELOPMENT.md): build checks, regression tests, and implementation details.
- [Contributing](CONTRIBUTING.md): bug reports, pull requests, and support expectations.
- [Security](SECURITY.md): data handling and private vulnerability reporting.

The application is [MIT licensed](LICENSE), copyright 2026 Abram Bailey. BiRefNet and its Core ML conversion retain their own [MIT notices](Resources/ThirdParty/BiRefNetLite/NOTICE).
