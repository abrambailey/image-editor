# Image Editor for Mac

A lightweight, native image editor for macOS with layers, local background removal, and optional AI editing. Crop and resize photos, arrange screenshots or graphics on a canvas, and export or copy the result into another app.

Free and open source under the [MIT license](LICENSE). Currently available to build from source.

<img width="2464" height="1824" alt="image" src="https://github.com/user-attachments/assets/dd7d5805-543c-4e9e-921f-ec623ced57fd" />

## Features

- **Crop, resize, and arrange.** Set exact canvas dimensions, scale and position images, snap to center guides, and add padding around your composition.
- **Work with layers and tabs.** Combine images, reorder or hide layers, and keep several edits open with separate Undo histories.
- **Remove backgrounds locally.** Create transparent cutouts on your Mac, clean up white edges, and restore the original image when needed. Background removal runs offline after the first build downloads its model.
- **Edit with AI.** Describe a change in words, optionally paint the area to edit, and compare the result with the original before applying it. Blend a selected area back into your image for more control.
- **Export or copy.** Save transparent PNGs or adjustable-quality JPGs, or copy the edited image straight into another app. Export the visible image bounds or include the full canvas.
- **Use familiar Mac controls.** Open files, drag and drop, paste from the clipboard, or load an image from a URL. Undo and Redo are available throughout, and close/quit prompts help protect unexported work.

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

- [User guide](docs/USAGE.md): layers, cropping, background removal, export settings, AI editing, and keyboard shortcuts.
- [Development and testing](docs/DEVELOPMENT.md): build checks, regression tests, and implementation details.
- [Contributing](CONTRIBUTING.md): bug reports, pull requests, and support expectations.
- [Security](SECURITY.md): data handling and private vulnerability reporting.

The application is [MIT licensed](LICENSE), copyright 2026 Abram Bailey. BiRefNet and its Core ML conversion retain their own [MIT notices](Resources/ThirdParty/BiRefNetLite/NOTICE).
