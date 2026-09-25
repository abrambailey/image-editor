import AppKit
import SwiftUI
import UniformTypeIdentifiers

// THESIS: A compact Mac workbench for arranging product image layers.
// OWN-WORLD: System typography, neutral canvas surround, native controls, blue selection.
// STORY: Bring in a product, isolate it, set its breathing room, export exact pixels.
// FIRST VIEWPORT: The canvas fills the left; a 276-point inspector follows the workflow.
// FORM: Native photographic light table, grounded direction 5, seed 3885b098. Code-led.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

struct EditorView: View {
    @ObservedObject var model: EditorModel
    var minimumHeight: CGFloat = 660
    private let inspectorWidth: CGFloat = 276
    private let inspectorInset: CGFloat = 18
    private let inspectorScrollerGutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.aiEdit {
                AIEditView(session: session, apply: model.applyAIEdit, close: model.cancelAIEdit)
            } else {
            HStack(spacing: 0) {
                ZStack {
                    CanvasView(model: model)
                    if !model.hasImage && !model.isBusy { emptyState }
                    if let message = model.busyMessage {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(message).font(.callout)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: inspectorWidth)
            }
            }
            Divider()
            HStack(spacing: 12) {
                Text(model.status)
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.status)
                Spacer(minLength: 8)
                if model.hasImage && model.aiEdit == nil {
                    Button(action: model.zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                    }.disabled(!model.canZoomOut).help("Zoom out (⌘−)").accessibilityLabel("Zoom out")
                        .keyboardShortcut("-", modifiers: .command)
                    Button("\(Int(model.zoom * 100))% fit") { model.zoom = 1 }
                        .monospacedDigit().help("Reset preview to fit the window")
                    Button(action: model.zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                    }.disabled(!model.canZoomIn).help("Zoom in (⌘+ or ⌘=)").accessibilityLabel("Zoom in")
                        .keyboardShortcut("+", modifiers: .command)
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .padding(.horizontal, 16).frame(height: 32)
            .background(.bar)
        }
        .environmentObject(model)
        .frame(minWidth: 860, minHeight: minimumHeight)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: model.openImage) { Label("Open", systemImage: "folder") }
                    .disabled(!model.canImport).help("Open one or more images (⌘O)")
                Button(action: model.paste) { Label("Paste", systemImage: "doc.on.clipboard") }
                    .disabled(!model.canImport).help("Paste an image or image URL (⌘V)")
            }
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                documentToolbarItem.sharedBackgroundVisibility(.hidden)
            } else {
                documentToolbarItem
            }
            #else
            documentToolbarItem
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.startCrop) { Label("Crop", systemImage: "crop") }
                    .disabled(!model.canEdit).help("Crop the image and canvas (⇧⌘X)")
                Button(action: model.startAIEdit) { Label("AI Edit", systemImage: "sparkles") }
                    .disabled(!model.canEdit).help("Edit with Sunburst using a text instruction (⇧⌘I)")
                Button(action: model.removeBackground) {
                    Label("Remove Background", systemImage: "wand.and.stars")
                }.disabled(!model.canEditLayer).help("Remove the selected layer’s background with on-device AI (⇧⌘B)")
                Button { model.exportImage(copy: true) } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }.disabled(!model.canEdit).help("Copy the image as PNG using the export settings (⇧⌘C)")
                Button { model.exportImage() } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }.disabled(!model.canEdit).help("Export PNG or JPG (⇧⌘E)")
            }
        }
        .sheet(item: $model.pendingImport) { pending in ImportChoiceSheet(model: model, pending: pending) }
        .sheet(isPresented: $model.showURLSheet) { URLSheet(model: model) }
        .alert("Couldn’t complete that", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK", role: .cancel) { model.errorMessage = nil } }
        message: { Text(model.errorMessage ?? "") }
    }

    private var documentToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(model.hasImage ? model.document.filename : "Image Editor")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(model.hasImage ? "\(Int(model.document.canvas.width)) × \(Int(model.document.canvas.height)) px" : "A little room for your product.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .help(model.hasImage ? model.document.filename : "Image Editor")
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
            VStack(spacing: 7) {
                Text("Make room for the product.").font(.system(size: 22, weight: .semibold))
                Text("Drop an image here, or copy one from the web\nand paste it with ⌘V.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(4)
            }
            HStack(spacing: 12) {
                Button("Open Image…", action: model.openImage).buttonStyle(.borderedProminent)
                Button("From URL…") { model.showURLSheet = true }
            }.controlSize(.large)
            Text("PNG, JPG, WebP, HEIC & TIFF").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(32)
        .allowsHitTesting(true)
        // Preserve the full empty canvas as a file-drop target, including this overlay.
        .onDrop(of: [.fileURL, .png, .tiff, .url], isTargeted: nil) { providers in
            importDroppedProviders(providers, model: model)
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let crop = model.cropRect {
                        cropInspector(crop)
                    } else {
                        layersInspector
                        Divider()
                        section("Canvas") {
                            HStack(spacing: 10) {
                                PixelField("Width", value: model.document.canvas.width, range: 1...8192) { model.setCanvas(width: $0) }
                                PixelField("Height", value: model.document.canvas.height, range: 1...8192) { model.setCanvas(height: $0) }
                            }
                            HStack {
                                Menu("Presets") {
                                    Button("Square · 1200 × 1200") { model.setCanvas(width: 1200, height: 1200) }
                                    Button("Square · 2000 × 2000") { model.setCanvas(width: 2000, height: 2000) }
                                    Button("Landscape · 1600 × 1200") { model.setCanvas(width: 1600, height: 1200) }
                                    Button("Portrait · 1200 × 1600") { model.setCanvas(width: 1200, height: 1600) }
                                    if let original = model.document.original {
                                        Button("Original · \(original.width) × \(original.height)") {
                                            model.setCanvas(width: Double(original.width), height: Double(original.height))
                                        }
                                    }
                                }
                                Button { model.setCanvas(width: model.document.canvas.height, height: model.document.canvas.width) } label: {
                                    Image(systemName: "arrow.left.arrow.right")
                                }.help("Swap width and height").accessibilityLabel("Swap canvas width and height")
                            }
                            Picker("Background", selection: Binding(get: { model.document.background }, set: model.setBackground)) {
                                ForEach(CanvasBackground.allCases) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().accessibilityLabel("Canvas background")
                        }
                        Divider()
                        section("Padding & placement") {
                            PixelField("Minimum padding", value: model.document.padding, range: 0...model.maximumPadding) { model.setPadding($0) }
                            Button(action: model.fitAndCenter) {
                                Label("Fit & Center", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .frame(maxWidth: .infinity)
                            }.disabled(!model.canEditLayer)
                            Button("Center Layer", action: model.center).disabled(!model.canEditLayer)
                            Text("Fits the selected layer inside this margin and centers it. Drag a corner to fine-tune.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        section("Selected layer") {
                            Button(action: model.removeBackground) {
                                Label(model.document.isCutout ? "Remove Background Again" : "Remove Background", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }.disabled(!model.canEditLayer)
                            Text("On-device AI. Your image stays on your Mac.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Menu("Refine Cutout") {
                                Button("Clean White Edges", action: model.cleanWhiteEdges)
                                Divider()
                                Button("Restore Original", action: model.restoreOriginal)
                            }.disabled(!model.canEditLayer)
                            DisclosureGroup("Position & scale") {
                                VStack(spacing: 10) {
                                    HStack(spacing: 10) {
                                        PixelField("X", value: model.document.frame.minX, range: -100_000...100_000) { model.setPosition(x: $0) }
                                        PixelField("Y", value: model.document.frame.minY, range: -100_000...100_000) { model.setPosition(y: $0) }
                                    }
                                    PixelField("Scale", value: model.scalePercent, range: 1...2000, unit: "%") { model.setScale($0) }
                                }.padding(.top, 8)
                            }.font(.system(size: 11)).disabled(!model.canEditLayer)
                        }
                    }
                }
                // Share an explicit form width with Export. Native scrollers may
                // overlay the view or consume width when it overflows; neither
                // should change the fields' width or their leading alignment.
                .frame(width: inspectorWidth - 2 * inspectorInset - inspectorScrollerGutter, alignment: .leading)
                .padding(inspectorInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if let crop = model.cropRect {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crop to \(Int(crop.width)) × \(Int(crop.height)) px")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Button(action: model.applyCrop) { Text("Apply Crop").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel", action: model.cancelCrop)
                        .frame(maxWidth: .infinity).keyboardShortcut(.cancelAction)
                }.padding(inspectorInset).padding(.trailing, inspectorScrollerGutter)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export").font(.system(size: 13, weight: .semibold))
                    Picker("Format", selection: $model.format) {
                        ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Toggle("Include canvas padding", isOn: $model.includeCanvasPadding)
                        .font(.system(size: 11))
                        .help("Keep the full canvas dimensions and padding when exporting or copying. Off exports only the visible image bounds.")
                    if model.format == .jpeg {
                        HStack {
                            Text("Quality")
                            Slider(value: $model.quality, in: 1...100, step: 1).accessibilityLabel("JPEG quality")
                            Text("\(Int(model.quality))%").monospacedDigit().frame(width: 35, alignment: .trailing)
                        }.font(.system(size: 11))
                        Text(model.document.background == .transparent ? "JPG uses a white background." : "JPG uses the canvas background.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(model.document.background == .transparent ? "Transparency preserved. Full quality." : "Full quality with the canvas background.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button { model.exportImage() } label: {
                        Text("Export \(model.format.rawValue)…").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canEdit)
                    Button { model.exportImage(copy: true) } label: {
                        Label("Copy Image", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }.controlSize(.large).disabled(!model.canEdit)
                        .help("Copy the image as PNG using the export settings (⇧⌘C)")
                }.padding(inspectorInset).padding(.trailing, inspectorScrollerGutter)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .disabled(model.isBusy)
    }

    private var layersInspector: some View {
        section("Layers") {
            HStack {
                Button(action: model.addImages) { Label("Add Images…", systemImage: "plus") }
                    .disabled(!model.canImport)
                Spacer()
                Text("\(model.document.layers.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            if model.hasImage {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.document.layers.reversed()) { layer in
                                LayerRow(model: model, layer: layer).id(layer.id)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(4, model.document.layers.count)) * 42)
                    .onChange(of: model.document.selectedLayerID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                HStack(spacing: 14) {
                    Button { model.moveLayer(by: 1) } label: { Image(systemName: "arrow.up") }
                        .disabled(!model.canMoveLayer(by: 1)).help("Bring layer forward").accessibilityLabel("Bring layer forward")
                    Button { model.moveLayer(by: -1) } label: { Image(systemName: "arrow.down") }
                        .disabled(!model.canMoveLayer(by: -1)).help("Send layer backward").accessibilityLabel("Send layer backward")
                    Divider().frame(height: 14)
                    Button(action: model.duplicateLayer) { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate selected layer").accessibilityLabel("Duplicate selected layer")
                    Spacer()
                    Button(action: model.deleteLayer) { Image(systemName: "trash") }
                        .help("Delete selected layer (Delete)").accessibilityLabel("Delete selected layer")
                }.buttonStyle(.borderless).disabled(!model.canEdit)
                Text(model.document.selectedLayer?.isVisible == false
                     ? "Selected layer is hidden. Show it to move or resize."
                     : "Top layer is in front. Select a row or click an image.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Add images to arrange them on one canvas.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cropInspector(_ crop: CGRect) -> some View {
        section("Crop") {
            Text("Drag to select an area. Drag inside the selection to move it, or use its edges and corners to resize.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                PixelField("Crop X", value: crop.minX, range: 0...(model.document.canvas.width - crop.width)) { model.setCrop(x: $0) }
                PixelField("Crop Y", value: crop.minY, range: 0...(model.document.canvas.height - crop.height)) { model.setCrop(y: $0) }
            }
            HStack(spacing: 10) {
                PixelField("Crop width", value: crop.width, range: 1...(model.document.canvas.width - crop.minX)) { model.setCrop(width: $0) }
                PixelField("Crop height", value: crop.height, range: 1...(model.document.canvas.height - crop.minY)) { model.setCrop(height: $0) }
            }
            Button("Reset Selection", action: model.resetCrop)
            Divider().padding(.vertical, 8)
            Text("The selected area becomes the canvas and export size. Image scale stays the same.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Arrow keys move the selection by 1 px; hold Shift for 10 px. Return applies. Esc cancels.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
    }
}

/// Keep incomplete number edits local; commit on Return or blur, not per keystroke.
struct PixelField: View {
    @EnvironmentObject private var model: EditorModel
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var unit = "px"
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: Double, range: ClosedRange<Double>, unit: String = "px", commit: @escaping (Double) -> Void) {
        self.title = title; self.value = value; self.range = range; self.unit = unit; self.commit = commit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField(title, text: $text)
                    .textFieldStyle(.plain).monospacedDigit()
                    .focused($focused).onSubmit(save)
                    .accessibilityLabel("\(title), \(unit)")
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: focused ? 2 : 0.5))
        }
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, new in if !focused { text = formatted(new) } }
        .onChange(of: focused) { _, new in if !new { save() } }
        .onReceive(NotificationCenter.default.publisher(for: .commitImageEditorFields)) { notification in
            guard notification.object as? EditorModel === model else { return }
            if focused { save(); focused = false }
        }
    }

    private func formatted(_ value: Double) -> String { String(format: "%.0f", value) }
    private func save() {
        guard text != formatted(value) else { return }
        guard let number = Double(text), number.isFinite else { text = formatted(value); return }
        let clamped = min(range.upperBound, max(range.lowerBound, number.rounded()))
        if clamped != value { commit(clamped) }
        text = formatted(clamped)
    }
}

struct URLSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var focused: Bool

    private var validURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open image from URL").font(.headline)
            Text("In your browser, right-click the image and choose Copy Image Address.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("https://example.com/image.png", text: $address)
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(open)
                .accessibilityLabel("Direct image URL")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open Image", action: open).keyboardShortcut(.defaultAction).disabled(validURL == nil)
            }
        }.padding(24).frame(width: 430).onAppear { focused = true }
    }
    private func open() {
        guard let url = validURL else { return }
        dismiss(); model.requestImport([.url(url)], isPaste: false)
    }
}

@MainActor
private func importDroppedProviders(_ providers: [NSItemProvider], model: EditorModel) -> Bool {
    let supported = providers.filter { provider in
        [UTType.fileURL, .png, .tiff, .url].contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }
    guard model.canImport, !supported.isEmpty else { return false }
    Task {
        do {
            var items: [ImageImport] = []
            for provider in supported {
                guard let type = [UTType.fileURL, .png, .tiff, .url].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? EditorError.message("Couldn’t read a dropped image. Try opening the file.")) }
                    }
                }
                if type == .fileURL || type == .url {
                    guard let url = URL(dataRepresentation: data, relativeTo: nil) else { throw EditorError.message("Couldn’t read the image address.") }
                    items.append(.url(url))
                } else { items.append(.data(data, name: "Dropped image")) }
            }
            model.importImages(items)
        } catch { model.errorMessage = error.localizedDescription }
    }
    return true
}

private struct LayerRow: View {
    @ObservedObject var model: EditorModel
    let layer: ImageLayer
    @State private var renaming = false
    @State private var name = ""
    private var selected: Bool { model.document.selectedLayerID == layer.id }

    var body: some View {
        HStack(spacing: 6) {
            Button { model.selectLayer(layer.id) } label: {
                HStack(spacing: 8) {
                    Image(decorative: layer.image, scale: 1)
                        .resizable().scaledToFit().frame(width: 30, height: 30)
                        .opacity(layer.isVisible ? 1 : 0.4)
                    Text(layer.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select layer \(layer.name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button { model.toggleLayerVisibility(layer.id) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash").frame(width: 24, height: 28)
            }.buttonStyle(.plain)
                .help(layer.isVisible ? "Hide layer" : "Show layer")
                .accessibilityLabel("\(layer.isVisible ? "Hide" : "Show") \(layer.name)")
        }
        .font(.system(size: 11)).padding(.horizontal, 6).frame(height: 40)
        .background(selected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .contextMenu {
            Button("Rename…") { name = layer.name; renaming = true }
            Button("Duplicate") { model.selectLayer(layer.id); model.duplicateLayer() }
            Button(layer.isVisible ? "Hide" : "Show") { model.toggleLayerVisibility(layer.id) }
            Divider()
            Button("Delete Layer") { model.selectLayer(layer.id); model.deleteLayer() }
        }
        .alert("Rename layer", isPresented: $renaming) {
            TextField("Layer name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { model.renameLayer(layer.id, to: name) }
        }
    }
}

struct ImportChoiceSheet: View {
    @ObservedObject var model: EditorModel
    let pending: PendingImageImport
    private var multiple: Bool { pending.items.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pending.isPaste ? "Paste \(multiple ? "images" : "image")" : "Open \(multiple ? "images" : "image")")
                .font(.headline)
            Text(model.hasImage
                 ? "Add to this canvas, or start a new image in a separate tab. Your current layers will stay open."
                 : "Arrange these images as layers on one canvas, or open each in its own tab.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { model.resolveImport(.layers) } label: {
                Label(multiple ? "Add as Layers" : "Add as Layer", systemImage: "square.3.layers.3d")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            Button { model.resolveImport(.newImages) } label: {
                Text(multiple ? "Open in Separate Tabs" : "Open in New Tab").frame(maxWidth: .infinity)
            }.controlSize(.large).disabled(model.openNewImages == nil)
            HStack { Spacer(); Button("Cancel") { model.pendingImport = nil }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 370)
    }
}
