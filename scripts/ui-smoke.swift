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
            capture("--capture")
            app.terminate(nil)
        }
        app.run()
    }
}
