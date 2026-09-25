import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let commitImageEditorFields = Notification.Name("commitImageEditorFields")
}

struct ImageLayer: Identifiable {
    var id = UUID()
    var image: CGImage
    var original: CGImage
    var backgroundRemovalSource: CGImage?
    var sourceBounds: CGRect
    var name: String
    var frame: CGRect
    var isCutout = false
    var isVisible = true

    mutating func replaceImage(_ replacement: CGImage, sourceBounds newBounds: CGRect) {
        let scaleX = frame.width / sourceBounds.width
        let scaleY = frame.height / sourceBounds.height
        frame = CGRect(x: frame.minX + (newBounds.minX - sourceBounds.minX) * scaleX,
                       y: frame.minY + (newBounds.minY - sourceBounds.minY) * scaleY,
                       width: newBounds.width * scaleX, height: newBounds.height * scaleY)
        image = replacement
        sourceBounds = newBounds
    }
}

struct EditorSnapshot {
    // Stored in Undo snapshots so returning to a successful export is clean again.
    var revision = UUID()
    /// Back to front; the inspector presents the reverse order.
    var layers: [ImageLayer] = []
    var selectedLayerID: UUID?
    var filename = "Untitled"
    var hasCustomFilename = false
    var canvas = CGSize(width: 1200, height: 1200)
    var background = CanvasBackground.transparent
    var padding: CGFloat = 100

    func exportFilename(format: ExportFormat) -> String {
        var name = filename.components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
            .joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if ["png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased()) {
            name = (name as NSString).deletingPathExtension
        }
        if name.isEmpty || name == "." || name == ".." { name = "Untitled" }
        return name + "." + format.fileExtension
    }

    var selectedIndex: Int? { layers.firstIndex { $0.id == selectedLayerID } }
    var selectedLayer: ImageLayer? { selectedIndex.map { layers[$0] } }
    var image: CGImage? { selectedLayer?.image }
    var original: CGImage? { selectedLayer?.original }
    var backgroundRemovalSource: CGImage? { selectedLayer?.backgroundRemovalSource }
    var sourceBounds: CGRect { selectedLayer?.sourceBounds ?? .zero }
    var isCutout: Bool { selectedLayer?.isCutout ?? false }
    var frame: CGRect {
        get { selectedLayer?.frame ?? .zero }
        set { if let index = selectedIndex { layers[index].frame = newValue } }
    }
    mutating func replaceImage(_ image: CGImage, sourceBounds: CGRect) {
        if let index = selectedIndex { layers[index].replaceImage(image, sourceBounds: sourceBounds) }
    }
}

enum ImageImport {
    case data(Data, name: String)
    case url(URL)

    var name: String {
        switch self {
        case .data(_, let name): return name
        case .url(let url):
            let name = url.deletingPathExtension().lastPathComponent
            return name.isEmpty ? "Web image" : name
        }
    }

    func read() async throws -> Data {
        switch self {
        case .data(let data, _): return data
        case .url(let url):
            if !url.isFileURL { return try await ImageEngine.download(url) }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ImageEngine.maxDownloadBytes else {
                throw EditorError.message("This image is larger than 50 MB. Open a smaller copy.")
            }
            return try Data(contentsOf: url)
        }
    }
}

struct PendingImageImport: Identifiable {
    let id = UUID()
    let items: [ImageImport]
    let isPaste: Bool
}

enum ImportDestination { case layers, newImages }

struct ExportState: Equatable {
    let revision: UUID
    let format: ExportFormat
    let quality: Double
    let includeCanvasPadding: Bool
}

struct ImageExport {
    let document: EditorSnapshot
    let state: ExportState

    func encoded() throws -> Data {
        let image = try ImageEngine.renderExport(layers: document.layers, canvas: document.canvas,
                                                background: document.background, format: state.format,
                                                includeCanvasPadding: state.includeCanvasPadding)
        return try ImageEngine.encode(image, format: state.format, quality: state.quality / 100)
    }
}

@MainActor
final class EditorModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var document = EditorSnapshot()
    @Published private(set) var busyMessage: String?
    @Published var errorMessage: String?
    @Published var status = "Open, drop, or paste an image to get started."
    @Published var format = ExportFormat.png
    @Published var quality = 90.0
    @Published var includeCanvasPadding = false
    @Published var showURLSheet = false
    @Published var zoom: CGFloat = 1
    /// Pending crop in canvas pixels, measured from the top-left. Preview only.
    @Published private(set) var cropRect: CGRect?
    @Published var pendingImport: PendingImageImport?
    var openNewImages: (([ImageImport]) -> Void)?
    // Tests can choose a temporary destination without automating macOS's remote
    // Save-panel service. The normal app always presents its native panel.
    var chooseExportDestination: ((ImageExport, @escaping (URL?) -> Void) -> Void)?
    @Published private(set) var aiEdit: AIEditSession?
    @Published private(set) var undoStack: [EditorSnapshot] = []
    @Published private(set) var redoStack: [EditorSnapshot] = []
    @Published private var exportedState: ExportState?
    private var lastExportURL: URL?
    private var gestureStart: EditorSnapshot?

    var hasImage: Bool { !document.layers.isEmpty }
    var isBusy: Bool { busyMessage != nil || aiEdit != nil || pendingImport != nil }
    var isCropping: Bool { cropRect != nil }
    var canEdit: Bool { hasImage && !isBusy && !isCropping }
    var canEditLayer: Bool { canEdit && document.selectedLayer?.isVisible == true }
    var canImport: Bool { !isBusy && !isCropping }
    var hasUnexportedChanges: Bool {
        // Deleting the last layer still protects the image retained in Undo.
        let hasWork = hasImage || undoStack.contains { !$0.layers.isEmpty }
        return hasWork && exportState != exportedState
    }
    private var exportState: ExportState {
        ExportState(revision: document.revision, format: format,
                    quality: format == .jpeg ? quality : 100, includeCanvasPadding: includeCanvasPadding)
    }
    var pendingExport: ImageExport { ImageExport(document: document, state: exportState) }
    var canZoomIn: Bool { hasImage && aiEdit == nil && zoom < 4 }
    var canZoomOut: Bool { hasImage && aiEdit == nil && zoom > 0.25 }

    func zoomIn() {
        guard canZoomIn else { return }
        zoom = min(4, zoom + 0.25)
    }

    func zoomOut() {
        guard canZoomOut else { return }
        zoom = max(0.25, zoom - 0.25)
    }

    var imageSize: CGSize {
        guard let image = document.image else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }
    var scalePercent: Double {
        guard imageSize.width > 0 else { return 100 }
        return Double(document.frame.width) / Double(imageSize.width) * 100
    }
    var maximumPadding: Double {
        max(0, floor((Double(min(document.canvas.width, document.canvas.height)) - 1) / 2))
    }

    private func checkpoint() {
        undoStack.append(document)
        document.revision = UUID()
        if undoStack.count > 25 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func finishEditingFields() {
        // Commit synchronously before taking the snapshot used by a toolbar action.
        // Mac buttons need not move keyboard focus away from a number field.
        NotificationCenter.default.post(name: .commitImageEditorFields, object: self)
        if NSApp?.keyWindow?.firstResponder is NSTextView {
            NSApp?.keyWindow?.makeFirstResponder(nil)
        }
    }

    func prepareForTabSwitch() {
        finishEditingFields()
        endGesture()
    }

    func renameDocument(_ value: String) {
        let name = value.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !name.isEmpty, name != document.filename else { return }
        checkpoint()
        document.filename = name
        document.hasCustomFilename = true
    }

    var suggestedExportFilename: String { document.exportFilename(format: format) }

    func undo() {
        finishEditingFields()
        if isCropping && !isBusy { cancelCrop(); return }
        guard !isBusy, let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        status = "Undid the last edit."
    }

    func redo() {
        finishEditingFields()
        guard !isBusy, !isCropping, let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        status = "Redid the last edit."
    }

    func setCanvas(width: Double? = nil, height: Double? = nil) {
        guard !isBusy, !isCropping else { return }
        let newSize = CGSize(width: min(8192, max(1, (width ?? document.canvas.width).rounded())),
                             height: min(8192, max(1, (height ?? document.canvas.height).rounded())))
        guard newSize != document.canvas else { return }
        checkpoint()
        // Expanding/shrinking the canvas keeps the image relative to its center.
        for index in document.layers.indices {
            document.layers[index].frame.origin.x += (newSize.width - document.canvas.width) / 2
            document.layers[index].frame.origin.y += (newSize.height - document.canvas.height) / 2
        }
        document.canvas = newSize
        document.padding = min(document.padding, maximumPadding)
        status = "Canvas resized. Layers keep their size and offset from center."
    }

    func setBackground(_ background: CanvasBackground) {
        guard !isBusy, !isCropping, background != document.background else { return }
        checkpoint(); document.background = background
    }

    func setPadding(_ value: Double) {
        let padding = min(maximumPadding, max(0, value.rounded()))
        guard !isBusy, !isCropping, padding != document.padding else { return }
        checkpoint(); document.padding = padding
    }

    func startCrop() {
        finishEditingFields()
        guard canEdit else { return }
        endGesture()
        cropRect = CGRect(origin: .zero, size: document.canvas)
        zoom = 1
        status = "Drag to select an area. Return applies the crop; Esc cancels."
    }

    func updateCrop(_ rect: CGRect) {
        guard isCropping, !isBusy,
              [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy({ $0.isFinite }) else { return }
        let width = min(document.canvas.width, max(1, rect.width.rounded()))
        let height = min(document.canvas.height, max(1, rect.height.rounded()))
        cropRect = CGRect(x: min(document.canvas.width - width, max(0, rect.minX.rounded())),
                          y: min(document.canvas.height - height, max(0, rect.minY.rounded())),
                          width: width, height: height)
    }

    func setCrop(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        guard var rect = cropRect else { return }
        if let x { rect.origin.x = x }
        if let y { rect.origin.y = y }
        if let width { rect.size.width = min(width, document.canvas.width - rect.minX) }
        if let height { rect.size.height = min(height, document.canvas.height - rect.minY) }
        updateCrop(rect)
    }

    func resetCrop() {
        finishEditingFields()
        updateCrop(CGRect(origin: .zero, size: document.canvas))
    }

    func cancelCrop() {
        guard isCropping, !isBusy else { return }
        finishEditingFields()
        cropRect = nil
        status = "Crop canceled."
    }

    func applyCrop() {
        finishEditingFields()
        guard !isBusy, let rect = cropRect else { return }
        cropRect = nil
        guard rect != CGRect(origin: .zero, size: document.canvas) else {
            status = "Full canvas kept."
            return
        }
        checkpoint()
        // Clip with the canvas, keeping the source pixels and scale intact. Unlike
        // setCanvas, cropping translates from the selection's top-left, not center.
        for index in document.layers.indices {
            document.layers[index].frame = document.layers[index].frame.offsetBy(dx: -rect.minX, dy: -rect.minY)
        }
        document.canvas = rect.size
        document.padding = min(document.padding, maximumPadding)
        status = "Cropped to \(Int(rect.width)) × \(Int(rect.height)) px · ⌘Z undoes the crop."
    }

    func fitAndCenter() {
        finishEditingFields()
        guard canEditLayer else { return }
        checkpoint()
        document.frame = ImageEngine.fittedFrame(imageSize: imageSize, canvas: document.canvas, padding: document.padding)
        status = "Centered with at least \(Int(document.padding)) px of padding on every side."
    }

    func center() {
        finishEditingFields()
        guard canEditLayer else { return }
        checkpoint()
        document.frame.origin = CGPoint(x: (document.canvas.width - document.frame.width) / 2,
                                        y: (document.canvas.height - document.frame.height) / 2)
        status = "Image centered."
    }

    func setScale(_ percent: Double) {
        guard canEditLayer else { return }
        checkpoint()
        let factor = max(1, min(2000, percent)) / 100
        let size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        let center = CGPoint(x: document.frame.midX, y: document.frame.midY)
        document.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                width: size.width, height: size.height)
    }

    func setPosition(x: Double? = nil, y: Double? = nil) {
        guard canEditLayer else { return }
        checkpoint()
        if let x { document.frame.origin.x = x }
        if let y { document.frame.origin.y = y }
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        guard canEditLayer else { return }
        checkpoint()
        document.frame.origin.x += dx; document.frame.origin.y += dy
    }

    func beginGesture() {
        finishEditingFields()
        guard canEditLayer else { return }
        gestureStart = document
    }

    func updateFrame(_ frame: CGRect) {
        guard canEditLayer, frame.width >= 1, frame.height >= 1 else { return }
        document.frame = frame
    }

    func endGesture() {
        if let start = gestureStart, start.frame != document.frame {
            undoStack.append(start)
            document.revision = UUID()
            if undoStack.count > 25 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        gestureStart = nil
    }

    func restoreOriginal() {
        finishEditingFields()
        guard canEditLayer, let original = document.original else { return }
        checkpoint()
        guard let index = document.selectedIndex else { return }
        document.layers[index].image = original
        document.layers[index].backgroundRemovalSource = nil
        document.layers[index].sourceBounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        document.layers[index].isCutout = false
        document.frame = ImageEngine.fittedFrame(imageSize: imageSize, canvas: document.canvas, padding: document.padding)
        status = "Original image restored and centered."
    }

    func startAIEdit() {
        beginAIEdit(client: SunburstClient(), loadCredential: true)
    }

    func beginAIEdit(client: any AIImageEditing, loadCredential: Bool) {
        finishEditingFields()
        guard canEdit else { return }
        endGesture()
        do {
            let canvas = try ImageEngine.render(layers: document.layers, canvas: document.canvas,
                                                background: document.background, format: .png)
            aiEdit = AIEditSession(original: canvas, client: client, loadCredential: loadCredential)
            status = "Sunburst cloud editing · Review the result before applying."
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelAIEdit() {
        aiEdit?.close()
        aiEdit = nil
        status = "AI edit canceled. Your image is unchanged."
    }

    func applyAIEdit() {
        guard let session = aiEdit, let image = session.applicableImage else { return }
        checkpoint()
        let original = document.layers.count == 1 ? document.original ?? session.original : session.original
        let layer = ImageLayer(image: image, original: original,
                               backgroundRemovalSource: image,
                               sourceBounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                               name: "Sunburst result", frame: CGRect(origin: .zero, size: document.canvas))
        document.layers = [layer]
        document.selectedLayerID = layer.id
        session.close()
        aiEdit = nil
        status = "Sunburst edit applied · ⌘Z restores the previous layers and placement."
    }

    func openImage() { chooseImages(asLayers: false) }
    func addImages() { chooseImages(asLayers: true) }

    private func chooseImages(asLayers: Bool) {
        finishEditingFields()
        guard canImport else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = asLayers ? "Choose images to add as layers" : "Choose one or more images"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let items = panel.urls.map(ImageImport.url)
            Task { @MainActor in
                if asLayers { self?.importImages(items) }
                else { self?.requestImport(items, isPaste: false) }
            }
        }
    }

    func importURL(_ url: URL) { importImages([.url(url)]) }
    func importData(_ data: Data, name: String = "Pasted image") { importImages([.data(data, name: name)]) }

    func requestImport(_ items: [ImageImport], isPaste: Bool) {
        finishEditingFields()
        guard canImport, !items.isEmpty else { return }
        if hasImage || items.count > 1 {
            pendingImport = PendingImageImport(items: items, isPaste: isPaste)
        } else { importImages(items) }
    }

    func resolveImport(_ destination: ImportDestination) {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        switch destination {
        case .layers: importImages(pending.items)
        case .newImages: openNewImages?(pending.items)
        }
    }

    /// Decode the full batch before changing the document: one Undo step, no partial import.
    func importImages(_ items: [ImageImport]) {
        finishEditingFields()
        guard canImport, !items.isEmpty else { return }
        endGesture()
        busyMessage = items.count == 1 ? "Opening image…" : "Opening \(items.count) images…"
        let canvas = document.canvas, padding = document.padding
        Task {
            do {
                var layers: [ImageLayer] = []
                for item in items {
                    let bytes = try await item.read()
                    let layer = try await Task.detached(priority: .userInitiated) {
                        let original = try ImageEngine.decode(bytes)
                        let trimmed = try ImageEngine.trimmed(original)
                        let size = CGSize(width: trimmed.image.width, height: trimmed.image.height)
                        return ImageLayer(image: trimmed.image, original: original, sourceBounds: trimmed.bounds,
                                          name: item.name,
                                          frame: ImageEngine.fittedFrame(imageSize: size, canvas: canvas, padding: padding))
                    }.value
                    layers.append(layer)
                }
                checkpoint()
                if document.layers.isEmpty {
                    if !document.hasCustomFilename { document.filename = layers[0].name }
                    zoom = 1
                }
                document.layers.append(contentsOf: layers)
                document.selectedLayerID = layers.last?.id
                status = layers.count == 1 ? "Layer added · Drag to move; drag a corner to resize."
                    : "\(layers.count) layers added · Select a layer to move or resize it."
            } catch { errorMessage = error.localizedDescription }
            busyMessage = nil
        }
    }

    func selectLayer(_ id: UUID) {
        finishEditingFields()
        guard canEdit, document.layers.contains(where: { $0.id == id }) else { return }
        endGesture()
        document.selectedLayerID = id
    }

    func renameLayer(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !name.isEmpty, let index = document.layers.firstIndex(where: { $0.id == id }),
              document.layers[index].name != name else { return }
        checkpoint()
        document.layers[index].name = name
    }

    func toggleLayerVisibility(_ id: UUID) {
        finishEditingFields()
        guard canEdit, let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        document.layers[index].isVisible.toggle()
    }

    func duplicateLayer() {
        finishEditingFields()
        guard canEdit, let index = document.selectedIndex else { return }
        checkpoint()
        var layer = document.layers[index]
        layer.id = UUID(); layer.name += " copy"
        layer.frame = layer.frame.offsetBy(dx: 20, dy: 20)
        document.layers.insert(layer, at: index + 1)
        document.selectedLayerID = layer.id
        status = "Layer duplicated."
    }

    func deleteLayer() {
        finishEditingFields()
        guard canEdit, let index = document.selectedIndex else { return }
        checkpoint()
        document.layers.remove(at: index)
        document.selectedLayerID = document.layers.isEmpty ? nil : document.layers[min(index, document.layers.count - 1)].id
        status = "Layer deleted · ⌘Z restores it."
    }

    func canMoveLayer(by offset: Int) -> Bool {
        guard canEdit, let index = document.selectedIndex else { return false }
        return document.layers.indices.contains(index + offset)
    }

    func moveLayer(by offset: Int) {
        finishEditingFields()
        guard canMoveLayer(by: offset), let index = document.selectedIndex else { return }
        checkpoint()
        document.layers.swapAt(index, index + offset)
    }

    func removeBackground() {
        finishEditingFields()
        guard canEditLayer, let image = document.backgroundRemovalSource ?? document.original else { return }
        busyMessage = "Removing background on your Mac…"
        let started = Date()
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImageEngine.trimmed(ImageEngine.removeBackground(from: image))
                }.value
                checkpoint()
                // Retry from the original, so another click never compounds lost edges.
                document.replaceImage(result.image, sourceBounds: result.bounds)
                if let index = document.selectedIndex { document.layers[index].isCutout = true }
                status = String(format: "Background removed in %.1f s · Use Fit & center to apply padding.", Date().timeIntervalSince(started))
            } catch {
                errorMessage = "Background removal failed. \(error.localizedDescription) Your image is unchanged."
            }
            busyMessage = nil
        }
    }

    func cleanWhiteEdges() {
        finishEditingFields()
        guard canEditLayer, let image = document.image else { return }
        busyMessage = "Cleaning white edges…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImageEngine.trimmed(ImageEngine.cleanWhiteEdges(image))
                }.value
                checkpoint()
                let sourceBounds = result.bounds.offsetBy(dx: document.sourceBounds.minX, dy: document.sourceBounds.minY)
                document.replaceImage(result.image, sourceBounds: sourceBounds)
                if let index = document.selectedIndex { document.layers[index].isCutout = true }
                status = "White edges cleaned. Inspect light product details; ⌘Z restores the previous image."
            } catch { errorMessage = error.localizedDescription }
            busyMessage = nil
        }
    }

    func paste() {
        guard canImport else { return }
        if !importPasteboard(NSPasteboard.general) {
            errorMessage = "There’s no image on the clipboard. Copy an image in your browser, or copy its direct image address."
        }
    }

    @discardableResult
    func importPasteboard(_ pasteboard: NSPasteboard, isDrop: Bool = false) -> Bool {
        guard canImport else { return false }
        var items: [ImageImport] = []
        // Finder file collections must not collapse to their preview bitmap or first URL.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty, urls.allSatisfy(\.isFileURL) {
            items = urls.map(ImageImport.url)
        } else {
            // Browsers often attach a webpage URL: prefer their actual image pixels.
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = pasteboard.data(forType: type) { items = [.data(data, name: "Pasted image")]; break }
            }
            if items.isEmpty,
               let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                items = urls.map(ImageImport.url)
            }
            if items.isEmpty,
               let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                items = [.url(url)]
            }
            if items.isEmpty, let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
                items = [.data(data, name: "Pasted image")]
            }
        }
        guard !items.isEmpty else { return false }
        if isDrop { importImages(items) } else { requestImport(items, isPaste: true) }
        return true
    }

    /// Only a completed file write acknowledges the exact snapshot exported.
    /// Later edits, failed writes, canceled panels, and clipboard copies stay unexported.
    func writeExport(_ export: ImageExport, to url: URL) async throws {
        let count = try await Task.detached(priority: .userInitiated) {
            let data = try export.encoded()
            try data.write(to: url, options: .atomic)
            return data.count
        }.value
        exportedState = export.state
        lastExportURL = url
        status = "Saved \(url.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file))"
    }

    func copyExport(_ export: ImageExport, to pasteboard: NSPasteboard) async throws {
        let clipboardExport = ImageExport(document: export.document,
            state: ExportState(revision: export.state.revision, format: .png,
                               quality: 100, includeCanvasPadding: export.state.includeCanvasPadding))
        let data = try await Task.detached(priority: .userInitiated) { try clipboardExport.encoded() }.value
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw EditorError.message("Couldn’t copy the image to the clipboard. Try Copy Image again.")
        }
        status = "Image copied. Paste it with ⌘V."
    }

    func exportImage(copy: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        finishEditingFields()
        guard canEdit else { completion(false); return }
        let export = pendingExport
        if copy {
            busyMessage = "Copying image…"
            Task {
                do {
                    try await copyExport(export, to: .general)
                    busyMessage = nil
                    completion(true)
                } catch {
                    busyMessage = nil
                    errorMessage = error.localizedDescription
                    completion(false)
                }
            }
            return
        }
        busyMessage = "Choosing an export location…"
        let recordRecentDocument = chooseExportDestination == nil
        let save: (URL?) -> Void = { [weak self] destination in
            guard let self else { completion(false); return }
            guard let url = destination else {
                self.busyMessage = nil
                completion(false)
                return
            }
            self.busyMessage = "Saving image…"
            Task { @MainActor in
                do {
                    try await self.writeExport(export, to: url)
                    self.busyMessage = nil
                    if recordRecentDocument { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
                    completion(true)
                } catch {
                    self.busyMessage = nil
                    self.errorMessage = "Couldn’t save the image. \(error.localizedDescription)"
                    completion(false)
                }
            }
        }
        if let chooseExportDestination {
            chooseExportDestination(export, save)
        } else {
            let panel = NSSavePanel()
            panel.directoryURL = lastExportURL?.deletingLastPathComponent()
            panel.allowedContentTypes = [export.state.format.contentType]
            panel.nameFieldStringValue = export.document.exportFilename(format: export.state.format)
            panel.canCreateDirectories = true
            panel.title = "Export \(export.state.format.rawValue)"
            panel.begin { response in save(response == .OK ? panel.url : nil) }
        }
    }
}
