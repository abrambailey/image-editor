import AppKit
import SwiftUI

/// A visible UI fixture, not a model-quality demonstration. Never sends a request.
struct PreviewImageEditor: AIImageEditing {
    func edit(image: Data, mask: Data?, prompt: String, size: String, transparentBackground: Bool, apiKey: String) async throws -> Data {
        let source = try ImageEngine.decode(image)
        let context = try ImageEngine.context(width: source.width, height: source.height)
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(source, in: rect)
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 0.15))
        context.fill(rect)
        return try ImageEngine.encode(context.makeImage()!, format: .png, quality: 1)
    }
}

// Run a real native window without launch restoration; captures only this app's view.
@main
struct UISmoke {
    @MainActor static func main() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            fputs("FAIL native UI test timed out\n", stderr)
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = EditorModel()
        let compact = CommandLine.arguments.contains("--compact")
        let dark = CommandLine.arguments.contains("--dark")
        if dark { app.appearance = NSAppearance(named: .darkAqua) }
        if compact { model.format = .jpeg }
        let size = compact ? CGSize(width: 860, height: 660) : CGSize(width: 1120, height: 800)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Image Editor verification"
        let host = NSHostingView(rootView: EditorView(model: model).frame(width: size.width, height: size.height))
        window.contentView = host
        window.setContentSize(size)
        window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--image") {
            model.importURL(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(15)
            while model.isBusy && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if model.isBusy || model.errorMessage != nil {
                print("FAIL import: \(model.errorMessage ?? "timed out")"); exit(1)
            }
            if CommandLine.arguments.contains("--remove-background") {
                @MainActor func waitForCutout() async {
                    let deadline = Date().addingTimeInterval(60)
                    while model.isBusy && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
                    if model.isBusy || model.errorMessage != nil {
                        print("FAIL cutout: \(model.errorMessage ?? "timed out")"); exit(1)
                    }
                }
                let originalFrame = model.document.frame
                let originalBounds = model.document.sourceBounds
                model.removeBackground()
                await waitForCutout()
                let cutoutFrame = model.document.frame
                let cutoutBounds = model.document.sourceBounds
                let first = try! ImageEngine.encode(model.document.image!, format: .png, quality: 1)
                model.removeBackground()
                await waitForCutout()
                let second = try! ImageEngine.encode(model.document.image!, format: .png, quality: 1)
                guard first == second, model.document.frame == cutoutFrame,
                      model.document.sourceBounds == cutoutBounds else {
                    print("FAIL retry changed cutout pixels or placement"); exit(1)
                }
                model.undo()
                model.undo()
                guard !model.document.isCutout, model.document.frame == originalFrame,
                      model.document.sourceBounds == originalBounds else {
                    print("FAIL cutout undo did not restore original pixels and placement"); exit(1)
                }
                model.redo()
                model.redo()
                guard model.document.isCutout, model.document.frame == cutoutFrame,
                      model.document.sourceBounds == cutoutBounds else {
                    print("FAIL cutout redo did not restore source bounds"); exit(1)
                }
                model.fitAndCenter()
                print("PASS native cutout, repeat removal without degradation, undo/redo and placement")
            }
            @MainActor func fields(_ view: NSView) -> [NSTextField] {
                if let field = view as? NSTextField { return [field] }
                return view.subviews.flatMap(fields)
            }
            guard let widthField = fields(host).first(where: { $0.placeholderString == "Width" }) else {
                print("FAIL could not locate width field"); exit(1)
            }
            let initialWidth = model.document.canvas.width
            app.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            window.makeFirstResponder(widthField)
            try? await Task.sleep(nanoseconds: 150_000_000)
            widthField.stringValue = "640"
            widthField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: widthField))
            try? await Task.sleep(nanoseconds: 100_000_000)
            model.fitAndCenter()
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard model.document.canvas.width == 640 else {
                print("FAIL pending width was not committed before Fit & Center"); exit(1)
            }
            model.undo() // fit
            model.undo() // width
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard model.document.canvas.width == initialWidth,
                  Double(widthField.stringValue) == initialWidth else {
                print("FAIL numeric undo left stale visible text: \(widthField.stringValue)"); exit(1)
            }
            window.makeFirstResponder(nil)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard model.document.canvas.width == initialWidth else {
                print("FAIL blur reapplied an undone value"); exit(1)
            }
            print("PASS native numeric editing, action commit, undo and blur")
            @MainActor func capture(_ flag: String) {
                guard let index = CommandLine.arguments.firstIndex(of: flag) else { return }
                let path = CommandLine.arguments[index + 1]
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            if CommandLine.arguments.contains("--crop") {
                @MainActor func findCanvas(_ view: NSView) -> EditorCanvas? {
                    if let canvas = view as? EditorCanvas { return canvas }
                    return view.subviews.lazy.compactMap(findCanvas).first
                }
                guard model.hasImage, let canvas = findCanvas(host) else {
                    print("FAIL crop test needs an image and canvas"); exit(1)
                }
                @MainActor func check(_ condition: Bool, _ message: String) {
                    guard condition else { print("FAIL crop: \(message)"); exit(1) }
                }
                @MainActor func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                    let size = model.document.canvas
                    let scale = min((canvas.bounds.width - 96) / size.width, (canvas.bounds.height - 100) / size.height) * model.zoom
                    let point = CGPoint(x: (canvas.bounds.width - size.width * scale) / 2 + x * scale,
                                        y: (canvas.bounds.height - size.height * scale) / 2 + y * scale)
                    return NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                @MainActor func drag(_ x: CGFloat, _ y: CGFloat, _ endX: CGFloat, _ endY: CGFloat) {
                    canvas.mouseDown(with: mouse(.leftMouseDown, x, y))
                    canvas.mouseDragged(with: mouse(.leftMouseDragged, endX, endY))
                    canvas.mouseUp(with: mouse(.leftMouseUp, endX, endY))
                }
                @MainActor func key(_ code: UInt16, shift: Bool = false) {
                    canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                          characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
                }
                model.startCrop()
                try? await Task.sleep(nanoseconds: 150_000_000)
                let before = model.document
                let history = model.undoStack.count
                drag(100, 150, 900, 850)
                check(model.cropRect == CGRect(x: 100, y: 150, width: 800, height: 700), "drag selection")
                drag(900, 850, 960, 910)
                check(model.cropRect == CGRect(x: 100, y: 150, width: 860, height: 760), "corner resize")
                drag(960, 530, 1000, 530)
                check(model.cropRect == CGRect(x: 100, y: 150, width: 900, height: 760), "edge resize")
                drag(500, 500, 470, 460)
                check(model.cropRect == CGRect(x: 70, y: 110, width: 900, height: 760), "move selection")
                key(124); key(125, shift: true)
                check(model.cropRect == CGRect(x: 71, y: 120, width: 900, height: 760), "keyboard selection nudge")
                check(model.undoStack.count == history && model.document.frame == before.frame, "preview edited history or placement")
                key(53)
                check(!model.isCropping && model.undoStack.count == history, "Escape cancels")
                model.startCrop()
                model.zoom = 0.75
                drag(900, 850, 100, 150)
                check(model.cropRect == CGRect(x: 100, y: 150, width: 800, height: 700), "reverse drag at different zoom")
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let cropWidth = fields(host).first(where: { $0.placeholderString == "Crop width" }) else {
                    print("FAIL could not locate crop width field"); exit(1)
                }
                window.makeFirstResponder(cropWidth)
                cropWidth.stringValue = "640"
                cropWidth.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: cropWidth))
                try? await Task.sleep(nanoseconds: 100_000_000)
                model.applyCrop()
                check(model.document.canvas == CGSize(width: 640, height: 700), "Apply did not commit pending width")
                check(model.document.frame == before.frame.offsetBy(dx: -100, dy: -150), "crop placement")
                check(model.undoStack.count == history + 1, "crop should be one undo step")
                model.undo()
                check(model.document.canvas == before.canvas && model.document.frame == before.frame, "undo crop")
                model.redo()
                check(model.document.canvas == CGSize(width: 640, height: 700), "redo crop")
                model.undo()
                try? await Task.sleep(nanoseconds: 150_000_000)
                model.startCrop()
                try? await Task.sleep(nanoseconds: 150_000_000)
                drag(100, 150, 900, 850)
                key(36)
                check(!model.isCropping && model.document.canvas == CGSize(width: 800, height: 700), "Return applies: \(model.document.canvas), pending \(String(describing: model.cropRect))")
                model.undo()
                model.startCrop()
                model.updateCrop(CGRect(x: 160, y: 180, width: 880, height: 800))
                try? await Task.sleep(nanoseconds: 150_000_000)
                capture("--capture-crop")
                model.cancelCrop()
                try? await Task.sleep(nanoseconds: 150_000_000)
                print("PASS native crop selection, move, edge/corner resize, zoom, keyboard, pending fields and undo/redo")
            }
            if CommandLine.arguments.contains("--ai-edit") {
                model.beginAIEdit(client: PreviewImageEditor(), loadCredential: false)
                guard let session = model.aiEdit else { print("FAIL missing AI session"); exit(1) }
                session.prompt = "Make the casing brushed silver. Keep the lettering and the wire unchanged."
                session.brushEnabled = true
                try? await Task.sleep(nanoseconds: 180_000_000)
                @MainActor func findEditCanvas(_ view: NSView) -> AIEditCanvasView? {
                    if let canvas = view as? AIEditCanvasView { return canvas }
                    return view.subviews.lazy.compactMap(findEditCanvas).first
                }
                guard let canvas = findEditCanvas(host) else { print("FAIL missing AI canvas"); exit(1) }
                let r = canvas.imageRect
                @MainActor func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height), to: nil),
                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                canvas.mouseDown(with: mouse(.leftMouseDown, 0.45, 0.3))
                canvas.mouseDragged(with: mouse(.leftMouseDragged, 0.5, 0.65))
                canvas.mouseUp(with: mouse(.leftMouseUp, 0.5, 0.65))
                guard session.strokes.count == 1 else { print("FAIL AI selection painting"); exit(1) }
                try? await Task.sleep(nanoseconds: 180_000_000)
                capture("--capture-ai-selection")
                session.apiKey = "ui-fixture-not-a-real-key"
                session.connectionExpanded = false
                session.generate()
                let deadline = Date().addingTimeInterval(30)
                while (session.isWorking || session.isBlending) && Date() < deadline { try? await Task.sleep(nanoseconds: 30_000_000) }
                guard session.result != nil, session.blended != nil, session.error == nil else {
                    print("FAIL AI fixture result: \(session.error ?? "timeout")"); exit(1)
                }
                session.message = "UI test fixture · No request was sent to Sunburst."
                try? await Task.sleep(nanoseconds: 180_000_000)
                capture("--capture-ai-result")
                session.preview = .blended
                try? await Task.sleep(nanoseconds: 180_000_000)
                capture("--capture-ai-blend")
                model.applyAIEdit()
                guard model.aiEdit == nil else { print("FAIL applying AI edit"); exit(1) }
                model.undo()
                print("PASS native AI selection painting, preview, blend and apply (mock API)")
            }
            if CommandLine.arguments.contains("--layers") {
                func check(_ condition: Bool, _ message: String) {
                    guard condition else { print("FAIL layers: \(message)"); exit(1) }
                }
                @MainActor func findCanvas(_ view: NSView) -> EditorCanvas? {
                    if let canvas = view as? EditorCanvas { return canvas }
                    return view.subviews.lazy.compactMap(findCanvas).first
                }
                guard let original = model.document.original, let canvas = findCanvas(host) else {
                    print("FAIL layers need an image"); exit(1)
                }
                let data = try! ImageEngine.encode(original, format: .png, quality: 1)
                let firstID = model.document.layers[0].id
                model.importData(data, name: "Right hearing aid")
                let importDeadline = Date().addingTimeInterval(10)
                while model.isBusy && Date() < importDeadline { try? await Task.sleep(nanoseconds: 20_000_000) }
                check(model.document.layers.count == 2, "import retains the first layer")
                let secondID = model.document.layers[1].id
                let size = model.document.canvas
                let fit = ImageEngine.fittedFrame(imageSize: model.imageSize,
                                                  canvas: CGSize(width: size.width / 2, height: size.height), padding: 60)
                model.beginGesture(); model.updateFrame(fit.offsetBy(dx: size.width / 2, dy: 0)); model.endGesture()
                model.selectLayer(firstID); model.renameLayer(firstID, to: "Left hearing aid")
                model.beginGesture(); model.updateFrame(fit); model.endGesture()
                let firstFrame = model.document.frame
                @MainActor func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                    let scale = min((canvas.bounds.width - 96) / size.width, (canvas.bounds.height - 100) / size.height) * model.zoom
                    let location = CGPoint(x: (canvas.bounds.width - size.width * scale) / 2 + point.x * scale,
                                           y: (canvas.bounds.height - size.height * scale) / 2 + point.y * scale)
                    return NSEvent.mouseEvent(with: type, location: canvas.convert(location, to: nil), modifierFlags: [.option],
                                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                let secondFrame = model.document.layers[1].frame
                // Find a solid pixel so the test also works with real transparent product cutouts.
                let layer = model.document.layers[1]
                var hit: CGPoint?
                for y in stride(from: secondFrame.minY + 10, to: secondFrame.maxY, by: 10) {
                    for x in stride(from: secondFrame.minX + 10, to: secondFrame.maxX, by: 10) {
                        let point = CGPoint(x: x, y: y)
                        if ImageEngine.containsPixel(point, in: layer) { hit = point; break }
                    }
                    if hit != nil { break }
                }
                guard let hit else { print("FAIL no opaque layer pixel"); exit(1) }
                let end = CGPoint(x: hit.x + 20, y: hit.y + 30)
                canvas.mouseDown(with: mouse(.leftMouseDown, hit))
                canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
                canvas.mouseUp(with: mouse(.leftMouseUp, end))
                check(model.document.selectedLayerID == secondID, "canvas selects the clicked layer")
                check(abs(model.document.frame.minX - secondFrame.minX - 20) < 0.01, "drag moves selected layer")
                check(model.document.layers[0].frame == firstFrame, "drag leaves the other layer in place")
                model.undo(); check(model.document.frame == secondFrame, "one undo restores the drag")
                let corner = CGPoint(x: secondFrame.maxX, y: secondFrame.maxY)
                let resized = CGPoint(x: corner.x + 30, y: corner.y + 60)
                canvas.mouseDown(with: mouse(.leftMouseDown, corner))
                canvas.mouseDragged(with: mouse(.leftMouseDragged, resized))
                canvas.mouseUp(with: mouse(.leftMouseUp, resized))
                check(model.document.frame.width > secondFrame.width, "corner resizes selected layer")
                check(abs(model.document.frame.width / model.document.frame.height - secondFrame.width / secondFrame.height) < 0.0001, "resize preserves aspect ratio")
                model.undo()
                let pasted = NSPasteboard.withUniqueName()
                pasted.setData(data, forType: .png)
                var opened = 0
                model.openNewImages = { opened += $0.count }
                check(model.importPasteboard(pasted), "clipboard is accepted")
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let index = CommandLine.arguments.firstIndex(of: "--capture-paste"), let pending = model.pendingImport {
                    // SheetHostingView caches as transparent on macOS 26. Render the
                    // same sheet content in a direct host, as for the editor captures.
                    let sheetHost = NSHostingView(rootView: ImportChoiceSheet(model: model, pending: pending)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    let sheetSize = sheetHost.fittingSize
                    let captureWindow = NSWindow(contentRect: CGRect(origin: .zero, size: sheetSize),
                                                 styleMask: [.borderless], backing: .buffered, defer: false)
                    captureWindow.isReleasedWhenClosed = false
                    captureWindow.contentView = sheetHost
                    captureWindow.orderFront(nil)
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if let bitmap = sheetHost.bitmapImageRepForCachingDisplay(in: sheetHost.bounds) {
                        sheetHost.cacheDisplay(in: sheetHost.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    }
                    captureWindow.close()
                }
                model.resolveImport(.newImages)
                check(opened == 1 && model.document.layers.count == 2, "new image preserves current layers")
                pasted.releaseGlobally()
                try? await Task.sleep(nanoseconds: 200_000_000)
                check(window.sheets.isEmpty, "paste sheet dismisses")
                window.makeFirstResponder(canvas)
                print("PASS native layer selection, drag, proportional resize, undo and paste choice sheet")
            }
            if CommandLine.arguments.contains("--pixel-tools") {
                @MainActor func check(_ value: Bool, _ message: String) {
                    guard value else { print("FAIL pixel tools: \(message)"); exit(1) }
                }
                @MainActor func findCanvas(_ view: NSView) -> EditorCanvas? {
                    if let canvas = view as? EditorCanvas { return canvas }
                    return view.subviews.lazy.compactMap(findCanvas).first
                }
                guard let canvas = findCanvas(host), model.hasImage else { exit(1) }
                @MainActor func mouse(_ type: NSEvent.EventType, _ point: CGPoint, shift: Bool = false) -> NSEvent {
                    let bounds = CGRect(origin: .zero, size: model.document.canvas)
                    let preview = model.isCropping && model.cropTarget == .layer ? bounds.union(model.cropBounds) : bounds
                    let scale = min((canvas.bounds.width - 96) / preview.width, (canvas.bounds.height - 100) / preview.height) * model.zoom
                    let location = CGPoint(x: (canvas.bounds.width - preview.width * scale) / 2 + (point.x - preview.minX) * scale,
                                           y: (canvas.bounds.height - preview.height * scale) / 2 + (point.y - preview.minY) * scale)
                    return NSEvent.mouseEvent(with: type, location: canvas.convert(location, to: nil), modifierFlags: shift ? [.shift] : [],
                                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                @MainActor func drag(_ start: CGPoint, _ end: CGPoint, shift: Bool = false) {
                    canvas.mouseDown(with: mouse(.leftMouseDown, start, shift: shift))
                    canvas.mouseDragged(with: mouse(.leftMouseDragged, end, shift: shift))
                    canvas.mouseUp(with: mouse(.leftMouseUp, end, shift: shift))
                }
                @MainActor func key(_ code: UInt16) {
                    canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                          windowNumber: window.windowNumber, context: nil, characters: "",
                                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
                }
                model.fitAndCenter()
                let before = model.document
                model.startLayerCrop()
                try? await Task.sleep(nanoseconds: 150_000_000)
                let frame = before.frame
                drag(CGPoint(x: frame.minX + frame.width * 0.2, y: frame.minY + frame.height * 0.15),
                     CGPoint(x: frame.minX + frame.width * 0.8, y: frame.minY + frame.height * 0.85))
                check(model.cropPixelRect!.width < CGFloat(before.image!.width), "layer crop drawn at source scale")
                try? await Task.sleep(nanoseconds: 150_000_000)
                capture("--capture-layer-crop")
                let expected = model.cropPixelRect!
                key(36)
                check(model.document.image!.width == Int(expected.width), "Return trims layer pixels")
                check(model.document.canvas == before.canvas, "layer crop preserves canvas")
                model.fitAndCenter()
                check(abs(model.document.frame.width / model.document.frame.height - expected.width / expected.height) < 0.001,
                      "Fit & Center uses cropped aspect ratio")
                model.undo(); model.undo()
                check(model.document.image === before.image, "Undo restores layer pixels")
                model.setSelectionTool(.rectangle)
                let visible = frame.intersection(CGRect(origin: .zero, size: before.canvas))
                let start = CGPoint(x: visible.midX - 80, y: visible.midY - 60)
                drag(start, CGPoint(x: start.x + 160, y: start.y + 120))
                check(model.pixelSelection?.shape == .rectangle, "rectangle tool")
                check(abs(model.pixelSelection!.rect.width - 160) < 0.001, "rectangle width")
                let oldPixels = try! ImageEngine.encode(model.document.image!, format: .png, quality: 1)
                key(51)
                check(model.document.layers.count == before.layers.count, "Delete retains layer")
                check(try! ImageEngine.encode(model.document.image!, format: .png, quality: 1) != oldPixels, "Delete erases selected pixels")
                model.undo()
                check(model.document.image === before.image, "Undo restores deleted pixels")
                model.setSelectionTool(.ellipse)
                drag(CGPoint(x: visible.midX + 100, y: visible.midY + 80),
                     CGPoint(x: visible.midX - 100, y: visible.midY - 60), shift: true)
                check(abs(model.pixelSelection!.rect.width - model.pixelSelection!.rect.height) < 0.001, "Shift reverse drag draws a circle")
                try? await Task.sleep(nanoseconds: 150_000_000)
                capture("--capture-selection")
                // Preserve the user's clipboard while exercising the real responder chain.
                let previousClipboard = NSPasteboard.general.pasteboardItems?.map { source -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for type in source.types { if let data = source.data(forType: type) { item.setData(data, forType: type) } }
                    return item
                } ?? []
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil); window.makeMain()
                try? await Task.sleep(nanoseconds: 200_000_000)
                check(window.makeFirstResponder(canvas), "canvas accepts keyboard focus")
                check(NSApp.sendAction(#selector(EditorCanvas.copy(_:)), to: nil, from: nil), "Copy routes to canvas (key window: \(window.isKeyWindow))")
                check(NSApp.sendAction(#selector(EditorCanvas.paste(_:)), to: nil, from: nil), "Paste routes to canvas")
                check(model.pendingImport == nil && model.document.layers.count == before.layers.count + 1, "selection pastes directly as a new layer")
                NSPasteboard.general.clearContents()
                if !previousClipboard.isEmpty { NSPasteboard.general.writeObjects(previousClipboard) }
                model.undo()
                model.setSelectionTool(.rectangle)
                key(51)
                check(model.document.layers.count == before.layers.count, "empty selection Delete is safe")
                key(53)
                check(!model.isSelecting, "Escape returns to Move")
                // Cropping a layer outside the canvas remains reachable at fit zoom.
                model.setPosition(x: -frame.width / 2, y: -frame.height / 4)
                model.startLayerCrop()
                let offscreen = model.document.frame
                drag(CGPoint(x: offscreen.minX + offscreen.width * 0.1, y: offscreen.minY + offscreen.height * 0.1),
                     CGPoint(x: offscreen.midX, y: offscreen.midY))
                check(model.cropRect!.minX < 0, "crop can keep pixels outside canvas")
                key(53); model.undo()
                try? await Task.sleep(nanoseconds: 150_000_000)
                print("PASS native layer crop, crop then fit, rectangle/circle, Delete, clipboard responder routing, paste, Undo and off-canvas crop")
            }
            if CommandLine.arguments.contains("--layer-expansion") {
                @MainActor func check(_ value: Bool, _ message: String) {
                    guard value else { print("FAIL layer expansion UI: \(message)"); exit(1) }
                }
                @MainActor func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }
                @MainActor func click(_ point: CGPoint, in view: NSView) {
                    guard let window = view.window else { exit(1) }
                    window.makeKeyAndOrderFront(nil)
                    let location = view.convert(point, to: nil)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                        NSApp.postEvent(event, atStart: false)
                    }
                }
                @MainActor func press(_ label: String, in view: NSView) {
                    if let native = controls(view, NSButton.self).first(where: { $0.title == label }) {
                        native.performClick(nil)
                        return
                    }
                    if label == "Expand Layer" || label == "Cancel", let sheet = view.window {
                        let code: UInt16 = label == "Expand Layer" ? 36 : 53
                        let chars = label == "Expand Layer" ? "\r" : "\u{1b}"
                        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: sheet.windowNumber, context: nil, characters: chars,
                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                        _ = sheet.performKeyEquivalent(with: event)
                        return
                    }
                    if label.hasPrefix("Expand layer ") {
                        // First row's expand icon, beside crop and visibility.
                        let point = CGPoint(x: view.bounds.width - 83, y: view.isFlipped ? 94 : view.bounds.height - 94)
                        click(point, in: view)
                        return
                    }
                    let buttons = controls(view, NSView.self).filter { String(describing: type(of: $0)) == "SwiftUIAppKitButton" }
                    let button: NSView?
                    switch label {
                    case "Move layer": button = buttons.first
                    case "Rectangle selection": button = buttons.dropFirst().first
                    case "Ellipse selection": button = buttons.dropFirst(2).first
                    case "Expand Layer": button = buttons.last
                    case "Cancel": button = buttons.dropLast().last
                    default: button = nil
                    }
                    guard let button else { print("FAIL missing native button: \(label)"); exit(1) }
                    click(CGPoint(x: button.bounds.midX, y: button.bounds.midY), in: button)
                }
                @MainActor func controls<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
                    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { controls($0, type) }
                }
                @MainActor func choose(_ label: String, in view: NSView) {
                    for control in controls(view, NSSegmentedControl.self) {
                        if let segment = (0..<control.segmentCount).first(where: { control.label(forSegment: $0) == label }) {
                            control.selectedSegment = segment
                            check(control.sendAction(control.action, to: control.target), "choose \(label)")
                            return
                        }
                    }
                    print("FAIL missing segment: \(label)"); exit(1)
                }
                @MainActor func edit(_ label: String, _ value: String, in view: NSView) async {
                    guard let field = fields(view).first(where: { $0.placeholderString == label }) else {
                        print("FAIL missing expansion field: \(label)"); exit(1)
                    }
                    view.window?.makeFirstResponder(field)
                    field.stringValue = value
                    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                    await settle()
                }
                model.fitAndCenter()
                let before = model.document, history = model.undoStack.count
                press("Rectangle selection", in: host)
                await settle()
                check(model.selectionTool == .rectangle, "rectangle icon selects tool")
                press("Ellipse selection", in: host)
                await settle()
                check(model.selectionTool == .ellipse, "ellipse icon selects tool")
                press("Move layer", in: host)
                await settle()
                check(!model.isSelecting, "hand icon returns to Move")
                let layer = model.document.selectedLayer!
                press("Expand layer \(layer.name)", in: host)
                await settle()
                guard let sheet = window.attachedSheet, let content = sheet.contentView else {
                    print("FAIL expansion sheet missing"); exit(1)
                }
                check(model.layerExpansion?.id == layer.id, "row expand button targets its layer")
                await edit("Each side", "12.5", in: content)
                choose("Percent", in: content)
                await settle()
                press("Expand Layer", in: content)
                await settle()
                let insetX = Int((CGFloat(layer.image.width) * 0.125).rounded())
                let insetY = Int((CGFloat(layer.image.height) * 0.125).rounded())
                check(model.document.image!.width == layer.image.width + insetX * 2, "all sides percentage width")
                check(model.document.image!.height == layer.image.height + insetY * 2, "all sides percentage height")
                check(model.document.canvas == before.canvas, "expansion leaves canvas unchanged")
                check(model.undoStack.count == history + 1, "expansion is one Undo step")
                model.undo()
                check(model.document.image === before.image && model.document.frame == before.frame, "Undo restores expansion")
                await settle()
                press("Expand layer \(layer.name)", in: host)
                await settle()
                guard let content = window.attachedSheet?.contentView else { exit(1) }
                choose("Individual sides", in: content)
                await settle()
                for (label, value) in [("Top", "10"), ("Bottom", "30"), ("Left", "40"), ("Right", "20")] {
                    await edit(label, value, in: content)
                }
                choose("Color", in: content)
                await settle()
                guard let colorWell = controls(content, NSColorWell.self).first else {
                    print("FAIL custom color well missing"); exit(1)
                }
                colorWell.color = NSColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1)
                check(colorWell.sendAction(colorWell.action, to: colorWell.target), "custom color action")
                await settle()
                if let index = CommandLine.arguments.firstIndex(of: "--capture-expansion"), let target = model.layerExpansion {
                    // AppKit's sheet bitmap omits compositor surfaces. Capture the
                    // same view in a direct host, with the same native field edits.
                    let preview = NSHostingView(rootView: LayerExpansionSheet(model: model, target: target)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    let previewWindow = NSWindow(contentRect: CGRect(origin: .zero, size: preview.fittingSize),
                                                 styleMask: [.borderless], backing: .buffered, defer: false)
                    previewWindow.isReleasedWhenClosed = false
                    previewWindow.contentView = preview
                    previewWindow.orderFront(nil)
                    await settle()
                    choose("Individual sides", in: preview)
                    await settle()
                    for (label, value) in [("Top", "10"), ("Bottom", "30"), ("Left", "40"), ("Right", "20")] {
                        await edit(label, value, in: preview)
                    }
                    choose("Color", in: preview)
                    await settle()
                    if let previewWell = controls(preview, NSColorWell.self).first {
                        previewWell.color = colorWell.color
                        _ = previewWell.sendAction(previewWell.action, to: previewWell.target)
                    }
                    previewWindow.setContentSize(preview.fittingSize)
                    await settle()
                    if let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) {
                        preview.cacheDisplay(in: preview.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    }
                    previewWindow.close()
                    content.window?.makeKeyAndOrderFront(nil)
                }
                press("Expand Layer", in: content)
                await settle()
                check(model.document.image!.width == layer.image.width + 60, "individual pixel width")
                check(model.document.image!.height == layer.image.height + 40, "individual pixel height")
                check(abs(model.document.frame.minX - (before.frame.minX - 40 * before.frame.width / CGFloat(layer.image.width))) < 0.001,
                      "existing pixels keep placement")
                let context = try! ImageEngine.context(width: model.document.image!.width, height: model.document.image!.height)
                context.draw(model.document.image!, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
                let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
                check(abs(Int(bytes[0]) - 51) <= 1 && abs(Int(bytes[1]) - 128) <= 1 && abs(Int(bytes[2]) - 204) <= 1,
                      "custom border color reaches pixels")
                model.undo()
                await settle()
                press("Expand layer \(layer.name)", in: host)
                await settle()
                guard let cancelContent = window.attachedSheet?.contentView else { exit(1) }
                await edit("Each side", "9000", in: cancelContent)
                press("Expand Layer", in: cancelContent)
                await settle()
                check(model.layerExpansion != nil && model.document.image === before.image, "oversize expansion cannot be applied")
                press("Cancel", in: cancelContent)
                await settle()
                check(model.layerExpansion == nil && model.document.image === before.image, "Cancel keeps image")
                print("PASS native icon tools, expansion sheet, percentages, individual pixels, custom color, validation, Cancel and Undo")
            }
            capture("--capture")
            app.terminate(nil)
        }
        app.run()
    }
}
