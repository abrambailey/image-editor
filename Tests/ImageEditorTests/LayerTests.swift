import AppKit

@MainActor
final class LayerTests {
    private let fixtures = AIEditTests()
    private func wait(_ model: EditorModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.busyMessage != nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(model.busyMessage == nil)
        expectTrue(model.errorMessage == nil)
    }
    private func data(_ color: CGColor) throws -> Data {
        try ImageEngine.encode(fixtures.solid(width: 20, height: 10, color: color), format: .png, quality: 1)
    }
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
        let bytes = try fixtures.pixels(image)
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }

    func testLayerWorkflow() async throws {
        let red = try data(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let blue = try data(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let model = EditorModel()
        model.setCanvas(width: 100, height: 80); model.setPadding(0)
        let beforeImport = model.undoStack.count
        model.importImages([.data(red, name: "Red"), .data(blue, name: "Blue")])
        try await wait(model)
        expectEqual(model.document.layers.count, 2)
        expectEqual(model.undoStack.count, beforeImport + 1)
        let ids = model.document.layers.map(\.id)
        expectEqual(model.document.selectedLayerID, ids[1])
        model.setScale(100); model.setPosition(x: 15, y: 20)
        model.selectLayer(ids[0]); model.setScale(100); model.setPosition(x: 5, y: 10)
        let frames = model.document.layers.map(\.frame)
        let histories = model.undoStack.count
        model.selectLayer(ids[1]); expectEqual(model.undoStack.count, histories)
        model.beginGesture()
        model.updateFrame(model.document.frame.offsetBy(dx: 5, dy: 7))
        model.endGesture()
        expectEqual(model.undoStack.count, histories + 1)
        expectEqual(model.document.layers[0].frame, frames[0])
        model.undo(); expectEqual(model.document.layers.map(\.frame), frames)
        model.redo(); expectEqual(model.document.frame, frames[1].offsetBy(dx: 5, dy: 7))
        model.undo()
        model.renameLayer(ids[1], to: "Front image")
        model.moveLayer(by: -1)
        expectEqual(model.document.layers.map(\.id), ids.reversed())
        model.undo(); expectEqual(model.document.layers.map(\.id), ids)
        model.duplicateLayer()
        expectEqual(model.document.layers.count, 3)
        expectTrue(model.document.selectedLayerID != ids[1])
        expectEqual(model.document.selectedLayer?.name, "Front image copy")
        model.deleteLayer(); expectEqual(model.document.layers.count, 2)
        model.undo(); expectEqual(model.document.layers.count, 3)
        model.undo(); expectEqual(model.document.layers.count, 2)
        model.toggleLayerVisibility(ids[1]); expectTrue(!model.canEditLayer)
        let hiddenFrame = model.document.frame
        model.nudge(dx: 4, dy: 2); expectEqual(model.document.frame, hiddenFrame)
        model.undo(); expectTrue(model.canEditLayer)

        let beforeCanvas = model.document.layers.map(\.frame)
        model.setCanvas(width: 120, height: 100)
        expectEqual(model.document.layers.map(\.frame), beforeCanvas.map { $0.offsetBy(dx: 10, dy: 10) })
        model.startCrop(); model.setCrop(x: 5, y: 7, width: 50, height: 50)
        let beforeCrop = model.document.layers.map(\.frame)
        model.applyCrop()
        expectEqual(model.document.layers.map(\.frame), beforeCrop.map { $0.offsetBy(dx: -5, dy: -7) })
        model.undo(); expectEqual(model.document.layers.map(\.frame), beforeCrop)
        model.deleteLayer(); model.deleteLayer()
        expectTrue(!model.hasImage); expectTrue(model.document.selectedLayerID == nil)
        model.undo(); expectTrue(model.hasImage)

        // A failed member aborts the entire batch without losing existing edits.
        let beforeFailure = model.document.layers.map(\.id), history = model.undoStack.count
        model.importImages([.data(red, name: "Valid"), .data(Data([1, 2, 3]), name: "Broken")])
        let deadline = Date().addingTimeInterval(5)
        while model.busyMessage != nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(model.errorMessage != nil)
        expectEqual(model.document.layers.map(\.id), beforeFailure)
        expectEqual(model.undoStack.count, history)
    }

    func testCompositeRendering() throws {
        let red = try fixtures.solid(width: 20, height: 10)
        let blue = try fixtures.solid(width: 20, height: 10, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let source = CGRect(x: 0, y: 0, width: 20, height: 10)
        let back = ImageLayer(image: red, original: red, sourceBounds: source, name: "Back", frame: source.offsetBy(dx: 5, dy: 5))
        var front = ImageLayer(image: blue, original: blue, sourceBounds: source, name: "Front", frame: source.offsetBy(dx: 15, dy: 10))
        let canvas = CGSize(width: 50, height: 40)
        let rendered = try ImageEngine.render(layers: [back, front], canvas: canvas, background: .transparent, format: .png)
        expectEqual(try pixel(rendered, 20, 12), try pixel(blue, 0, 0))
        expectEqual(try pixel(rendered, 10, 7), try pixel(red, 0, 0))
        expectEqual(try pixel(rendered, 0, 0)[3], 0)
        let trim = try ImageEngine.renderExport(layers: [back, front], canvas: canvas, background: .transparent, format: .png, includeCanvasPadding: false)
        expectEqual(trim.width, 30); expectEqual(trim.height, 15)
        expectEqual(try pixel(trim, 15, 7), try pixel(blue, 0, 0))
        let jpeg = try ImageEngine.renderExport(layers: [back, front], canvas: canvas, background: .transparent, format: .jpeg, includeCanvasPadding: false)
        expectEqual(jpeg.width, 30); expectEqual(try pixel(jpeg, 29, 0), [255, 255, 255, 255])
        front.isVisible = false
        let hidden = try ImageEngine.renderExport(layers: [back, front], canvas: canvas, background: .transparent, format: .png, includeCanvasPadding: false)
        expectEqual(hidden.width, 20); expectEqual(hidden.height, 10)
        expectTrue(!ImageEngine.containsPixel(CGPoint(x: 20, y: 12), in: front))
        front.isVisible = true
        expectTrue(ImageEngine.containsPixel(CGPoint(x: 20, y: 12), in: front))
        let context = try ImageEngine.context(width: 20, height: 10)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        front.image = try unwrap(context.makeImage())
        expectTrue(ImageEngine.containsPixel(CGPoint(x: 16, y: 11), in: front))
        expectTrue(!ImageEngine.containsPixel(CGPoint(x: 30, y: 11), in: front))
        expectTrue(!ImageEngine.containsPixel(CGPoint(x: 16, y: 18), in: front))
    }

    func testPasteChoicesAndSeparateDocuments() async throws {
        if CommandLine.arguments.contains("--headless") {
            throw TestSkipped("Clipboard service omitted by --headless; run locally for paste coverage.")
        }
        let source = try data(CGColor(gray: 0, alpha: 1))
        let model = EditorModel()
        model.importData(source); try await wait(model)
        let first = model.document.layers[0].id, history = model.undoStack.count
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(source, forType: .png)
        expectTrue(model.importPasteboard(board))
        expectTrue(model.pendingImport != nil)
        expectEqual(model.document.layers.count, 1); expectEqual(model.undoStack.count, history)
        model.pendingImport = nil
        expectEqual(model.document.layers[0].id, first)
        expectTrue(model.importPasteboard(board))
        board.clearContents() // Pending content is independent of later clipboard changes.
        model.resolveImport(.layers); try await wait(model)
        expectEqual(model.document.layers.count, 2)
        model.undo(); expectEqual(model.document.layers.map(\.id), [first])
        model.redo(); expectEqual(model.document.layers.count, 2)
        var documents: [EditorModel] = []
        model.openNewImages = { items in
            for item in items {
                let new = EditorModel(); new.importImages([item]); documents.append(new)
            }
        }
        let existing = model.document.layers.map(\.id)
        model.requestImport([.data(source, name: "One"), .data(source, name: "Two")], isPaste: false)
        model.resolveImport(.newImages)
        expectEqual(documents.count, 2)
        for document in documents { try await wait(document) }
        expectEqual(documents.map { $0.document.filename }, ["One", "Two"])
        documents[0].setPosition(x: 20)
        expectEqual(documents[1].document.frame.minX, 100)
        expectEqual(model.document.layers.map(\.id), existing)
        model.startCrop()
        expectTrue(!model.importPasteboard(board))
        model.importData(source); expectEqual(model.document.layers.map(\.id), existing)
        model.cancelCrop()
        // Finder paste and drop both retain the entire file collection.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("one.png"), directory.appendingPathComponent("two.png")]
        for url in urls { try source.write(to: url) }
        board.writeObjects(urls as [NSURL])
        expectTrue(model.importPasteboard(board)); expectEqual(model.pendingImport?.items.count, 2)
        model.resolveImport(.layers); try await wait(model)
        expectEqual(model.document.layers.count, existing.count + 2)
        model.undo()
        expectTrue(model.importPasteboard(board, isDrop: true)); try await wait(model)
        expectTrue(model.pendingImport == nil)
        expectEqual(model.document.layers.count, existing.count + 2)
    }

    func testAICompositeAndUndo() async throws {
        let model = EditorModel()
        model.setCanvas(width: 100, height: 80); model.setPadding(0)
        model.importImages([.data(try data(CGColor(gray: 0, alpha: 1)), name: "Back"),
                            .data(try data(CGColor(gray: 1, alpha: 1)), name: "Front")])
        try await wait(model)
        model.setScale(100); model.setPosition(x: 10, y: 5)
        let snapshot = model.document
        let expected = try ImageEngine.render(layers: snapshot.layers, canvas: snapshot.canvas, background: snapshot.background, format: .png)
        model.beginAIEdit(client: FixtureImageEditor(), loadCredential: false)
        let session = try unwrap(model.aiEdit)
        expectEqual(try fixtures.pixels(session.original), try fixtures.pixels(expected))
        session.prompt = "Fixture"; session.apiKey = "test"; session.generate()
        let deadline = Date().addingTimeInterval(10)
        while session.isWorking && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(session.applicableImage != nil)
        model.applyAIEdit(); expectEqual(model.document.layers.count, 1)
        model.undo()
        expectEqual(model.document.layers.map(\.id), snapshot.layers.map(\.id))
        expectEqual(model.document.layers.map(\.frame), snapshot.layers.map(\.frame))
        model.redo(); expectEqual(model.document.layers.count, 1)
    }
}
