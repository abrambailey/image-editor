# Using Image Editor

[Back to the overview](../README.md)

Open an image for a quick crop, combine several layers, remove a background, or try an AI edit. This guide covers the controls and how they affect your image.

## Open images

Open one or more files, drag images into the window, or copy an image in your browser and press **⌘V**. When a canvas already has layers, Open and Paste ask whether to **Add as Layer(s)** or **Open in New Tab / Open in Separate Tabs**. The latter keeps your current canvas open and creates separate tabs in the same window. **File → Open Image from URL** accepts direct image URLs. Finder's **Open With** also works.

Direct image downloads depend on the source website allowing them. When a site blocks downloads or supplies a webpage instead, copy the actual image or save it locally first.

## Layers and tabs

The **Layers** panel lists the frontmost layer first. **Add Images…** (or **⌥⌘O**) adds all selected files to the current canvas in one Undo step; dropping multiple files does the same. New layers start centered and fitted to the canvas, so overlapping images can be selected in the panel. Use the up/down arrows to change stacking order, the crop icon to trim that layer’s pixels, the outward arrows to expand its edges, the eye to show or hide a layer, and the duplicate or trash buttons to manage the selected layer. Right-click a row to rename it. **Delete** with the canvas focused deletes selected pixels when a selection tool is active, or the selected layer in Move mode; **⌘Z** restores it. Hidden layers stay editable through the panel but do not appear in exports. Show a hidden layer before moving or resizing it.

Each image tab has independent layers, canvas settings, and Undo history. **⌘N** or the + beside the tabs creates an empty tab. Double-click a tab to rename it inline (or use **Tab → Rename Tab**). **Return** commits, **Escape** cancels, and the name becomes the suggested filename for PNG/JPG export. Renaming supports Undo. **⌘W** closes a tab; **⇧⌘T** reopens the most recently closed tab, retaining its edits. The last five closed tabs stay in memory until the app quits. Use the tab menu at the right of the strip to reach tabs beyond the visible area. Paste into an empty canvas starts its first layer directly. Pasting an external image into an existing canvas asks where to put it; **Cancel** leaves the canvas unchanged. Copy Image and Export combine all visible layers. Copy Selection copies pixels only from the selected layer; pasting that selection adds a new layer directly. Background removal, edge cleanup, Restore Original, and position/scale controls affect only the selected layer; Crop Canvas and canvas resizing affect every layer. Crop Layer trims only the selected layer.

## Canvas size and image placement

Enter canvas width and height, or use a preset. Changing canvas size preserves every layer's scale and its offset from the center.

Enter minimum padding in pixels and click **Fit & Center**. The selected layer keeps its aspect ratio; wider margins on two sides are expected when the image and canvas have different aspect ratios.

Click an image or its row in **Layers** to select it. Drag the selected image to move it, or drag any corner to resize proportionally. Center guides snap into place; hold **Option** to bypass snapping. With the canvas focused, use arrow keys for one-pixel moves or **Shift + arrow** for ten pixels. The X/Y fields position the image's top-left corner precisely.

## Crop a layer or the canvas

Click the **crop icon on a layer row**, or choose **Layer → Crop Layer**, to trim that layer’s actual pixels. Drag out the area to keep, move it by dragging inside, or resize using its edges and corners. The inspector accepts exact X/Y, width, and height in the layer’s source pixels. **Apply Crop** or **Return** applies it; **Cancel** or **Esc** leaves it unchanged.

The cropped layer keeps its scale and placement. The canvas and other layers stay unchanged. **Fit & Center** now fits the cropped image, so the removed edges stay removed. Undo restores the prior image and placement; **Restore Original** explicitly restores the imported image. You can also crop portions of a layer that extend beyond the canvas.

**Crop Canvas** in the toolbar (**⇧⌘X**) keeps the previous canvas-cropping behavior: it changes the canvas boundary and shifts every layer, preserving their pixels and scale. Its dimensions are in canvas pixels. Moving a layer, expanding the canvas, or using Fit & Center afterward can reveal pixels outside that boundary. Enable **Include canvas padding** to export the exact canvas rectangle, including empty space.

For either crop, arrow keys move the selection by one pixel (**Shift + arrow** for ten); **Reset Selection** selects the full layer or canvas. Apply or cancel before making other edits or exporting.

## Expand a layer

Click the **outward arrows** on a layer row, or choose **Layer → Expand Layer**. Choose **Pixels** or **Percent**, then enter one amount for **All sides** or separate **Top, Bottom, Left, and Right** amounts. The dialog shows the resulting pixel dimensions before you apply.

Percentages apply to each side of the current layer: left and right use its width, while top and bottom use its height. For example, 10% on all sides adds 100 pixels per horizontal side and 50 per vertical side to a 1,000 × 500 layer, producing 1,200 × 600 pixels. Amounts round to whole source pixels.

Choose **White**, **Color** (using the color picker), or **Transparent** for the added area. Existing pixels and transparency stay intact. The layer grows outward while the image stays in place; canvas size and other layers stay unchanged. **Fit & Center** includes the new border. **Cancel** makes no pixel changes, and **Undo** restores an applied expansion. The resulting layer must fit within 8,192 × 8,192 pixels.

## Select, delete, copy, and paste pixels

Select a layer, then choose the **dashed rectangle** or **dashed circle** in the upper-left corner of the workspace (also in the **Select** menu). Drag to draw a selection; hold **Shift** for a square or circle. Drag again to replace it. Arrow keys move the selection by one canvas pixel, or ten with Shift.

- **Delete** with the canvas focused, or **Delete Selected Pixels** in the inspector, makes that area transparent on the selected layer. Other layers stay intact. Undo restores the pixels.
- **⌘C** with the canvas focused, or **Copy Selection**, copies the selected layer’s pixels as a full-quality PNG at source resolution. Ellipse corners stay transparent.
- **⌘V** pastes a copied selection directly as a new layer, retaining its size and position on an existing canvas. You can also paste the PNG into another app.
- **Esc**, **⌘D**, or **Deselect & Move** clears the selection and returns to moving layers. The **hand** icon also switches to Move.

Selection tools only affect the selected layer. With no area drawn, Delete does nothing. **Copy Image** (**⇧⌘C**) still copies the entire visible composition using your export settings.

## Remove backgrounds

Select a layer, then click **Remove Background**. BiRefNet Lite runs locally through Core ML and produces a transparent cutout, including multiple foreground subjects. The first removal loads the model; subsequent removals reuse it. The original remains available through **Restore Original** and Undo.

The checkerboard is a preview of transparency and never appears in exports. Preview zoom does not affect exported dimensions. Import trims transparent borders, so fitting and centering use the visible subject. Removal preserves the current placement; click Fit & Center to apply padding to the new cutout. Repeating removal starts from the preserved original, last accepted AI image, or most recent layer crop/pixel deletion, avoiding cumulative edge damage and replacing any optional white-edge cleanup.

If a white halo remains, choose **Refine Cutout → Clean White Edges**. This removes near-white regions connected to the outside or transparency, while preserving enclosed white details. It can also remove very light image edges, so inspect the result and use Undo when needed. Exact X/Y and scale controls are inside **Position & scale**.

Background removal can miss fine or translucent details. Its cutout mask cannot be painted manually; the brush in AI Edit guides generated edits only.

## Export and copy

Choose **PNG** for transparency, or **JPG** and a quality percentage. By default, export uses only the visible image bounds, excluding surrounding canvas padding. Turn on **Include canvas padding** to keep the full canvas dimensions and margins. Click **Export** to choose the filename and location. Transparent pixels become white in JPG. Choosing a white or black canvas uses that color behind the image in either format.

PNG is lossless; JPG quality changes compression, not image dimensions. Both formats export in sRGB.

To use the edited image without saving a file, click **Copy Image** in the toolbar or below Export, press **⌘C** with the canvas focused in Move mode, or use **⇧⌘C** regardless of focus. When editing text, **⌘C** still copies the selected text. Paste into another app with **⌘V**. Copy always uses a full-quality PNG and follows **Include canvas padding**, just like file export. Your edits, scale, crop, and canvas background are retained. A transparent background stays transparent, even when JPG is selected for file export. Excluding canvas padding preserves white pixels within the source image and all nonzero alpha, including faint edges and shadows.

## Keeping your work

Each tab retains up to 25 edits in its Undo history while the app runs.

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

## AI editing with Sunburst

Open an image, then choose **AI Edit** in the toolbar or **Image → Edit with Sunburst…**. Describe the change in natural language. You can optionally enable **Paint a selection**, brush over the area to change, and undo strokes or clear the selection. Without a selection, the model locates the change from your instruction.

Expand **Connection** and enter an OpenAI API key. **Save in Keychain** stores it in this Mac’s Keychain; otherwise the key stays in memory for this editing session. **Forget** removes the saved key. The app also accepts `OPENAI_API_KEY` inherited at launch, although Finder-launched apps do not normally inherit shell environment variables. Keys are never written to the project or preferences.

**Generate Edit** sends the visible canvas, instruction, and optional mask directly to OpenAI’s `/v1/images/edits` API using `gpt-image-2.5-sunburst` at high quality. This incurs API charges separate from a ChatGPT subscription. The app makes one request per click, with no automatic retries. **Stop Waiting** cancels the local request; OpenAI may still complete and bill a request already received. Model access depends on the OpenAI project, billing, and any required organization verification.

Review **Original** and **Sunburst** before applying. Sunburst shows the full generated result by default, including any changes outside the requested area. When a selection was painted, **Blended** offers an optional version that uses the generated pixels only inside that selection. **Blend edge softness** feathers inward, preserving pixels outside the selection exactly in the working canvas. Inspect for seams, clipped changes, and mismatched lighting; blending cannot repair altered geometry. A broader selection may be needed for shadows or reflections. There is no automatic segmentation in this prototype.

Inputs with transparent pixels explicitly request `background=transparent` and PNG output, with instructions to preserve transparency when objects are removed. Other inputs keep automatic background selection; temporary aspect-ratio padding does not trigger transparent output. The returned alpha channel is retained through preview, application, and PNG export. The original alpha is not copied over the generated result, since removed or changed objects need a new silhouette.

**Generate Again** starts from the same original canvas. **Change Selection** discards the preview so you can revise the painted area. **Use Sunburst Result** or **Use Blended Result** applies the selected preview as one Undo step. Applying flattens the visible canvas into one image at the existing canvas dimensions; Undo restores every previous layer, its visibility, placement, and crop. Background removal subsequently starts from the accepted AI image. For a single-layer input, **Restore Original** still restores the originally imported image. For a multiple-layer input, it restores the composite canvas sent to Sunburst; use Undo immediately after Apply to recover the separate layers.

Generation uses dimensions divisible by 16, at most 2,048 pixels per edge; the result is aligned back to the canvas dimensions. Very wide or tall images are padded to the API’s supported aspect ratio and unpadded afterward. A full result may lose fine detail on larger canvases; blending preserves original detail outside the selection. The mask is guidance for Sunburst, not a guarantee of pixel preservation. See [OpenAI’s image-editing documentation](https://developers.openai.com/api/docs/guides/image-generation#edit-an-image-using-a-mask).

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
| Crop canvas | ⇧⌘X |
| Crop layer | Crop icon on its row, or Layer → Crop Layer |
| Square / circle selection | Hold Shift while drawing |
| Copy selected pixels | ⌘C (canvas focused with selection) |
| Deselect and return to Move | ⌘D or Esc (canvas focused) |
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
