import AppKit

@MainActor
final class SelectionTests {
    private let fixtures = AIEditTests()

    private func source() throws -> CGImage {
        let context = try ImageEngine.context(width: 40, height: 30)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 20, width: 15, height: 10)) // top-left blue
        return try unwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
        let data = try fixtures.pixels(image)
        let start = (y * image.width + x) * 4
        return Array(data[start..<start + 4])
    }

    private func model() async throws -> EditorModel {
        let model = EditorModel()
        model.setCanvas(width: 200, height: 150); model.setPadding(10)
        let data = try ImageEngine.encode(source(), format: .png, quality: 1)
        model.importImages([.data(data, name: "Back"), .data(data, name: "Front")])
        let deadline = Date().addingTimeInterval(10)
        while model.busyMessage != nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(model.errorMessage == nil && !model.isBusy)
        model.setScale(200); model.setPosition(x: -10, y: 15)
        return model
    }

    func testLayerCropAndFit() async throws {
        let model = try await model()
        let before = model.document, history = model.undoStack.count
        model.startLayerCrop()
        model.setCrop(x: 4, y: 3, width: 20, height: 10)
        expectEqual(model.cropRect, CGRect(x: -2, y: 21, width: 40, height: 20))
        expectEqual(model.cropPixelRect, CGRect(x: 4, y: 3, width: 20, height: 10))
        expectEqual(model.undoStack.count, history)
        model.cancelCrop()
        expectEqual(model.document.frame, before.frame)
        model.startLayerCrop(); model.setCrop(x: 4, y: 3, width: 20, height: 10); model.applyCrop()
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.document.layers[0].frame, before.layers[0].frame)
        expectEqual(model.document.frame, CGRect(x: -2, y: 21, width: 40, height: 20))
        let cropped = try unwrap(model.document.image)
        expectEqual(cropped.width, 20); expectEqual(cropped.height, 10)
        expectEqual(try pixel(cropped, 0, 0), try pixel(try unwrap(before.image), 4, 3))
        expectEqual(try pixel(cropped, 19, 9), try pixel(try unwrap(before.image), 23, 12))
        expectTrue(model.document.backgroundRemovalSource === cropped)
        model.fitAndCenter()
        expectEqual(model.document.frame, CGRect(x: 10, y: 30, width: 180, height: 90))
        expectEqual(model.document.image?.width, 20)
        model.undo(); model.undo()
        expectEqual(model.document.frame, before.frame)
        expectTrue(model.document.image === before.image)
        model.redo(); model.redo()
        model.startLayerCrop(); model.setCrop(x: 2, y: 1, width: 8, height: 6); model.applyCrop()
        expectEqual(model.document.image?.width, 8)
        expectEqual(try pixel(try unwrap(model.document.image), 0, 0), try pixel(cropped, 2, 1))
        model.restoreOriginal(); expectEqual(model.document.image?.width, 40)
        model.undo(); expectEqual(model.document.image?.width, 8)
        model.startLayerCrop(); model.setCrop(x: 100, y: -100, width: 999, height: 0)
        expectEqual(model.cropPixelRect, CGRect(x: 7, y: 0, width: 1, height: 1))
        model.cancelCrop()
        let id = try unwrap(model.document.selectedLayerID)
        model.toggleLayerVisibility(id); model.startLayerCrop(id)
        expectTrue(!model.isCropping)
    }

    func testSelectionPixels() throws {
        let image = try source()
        let layer = ImageLayer(image: image, original: image, sourceBounds: CGRect(x: 0, y: 0, width: 40, height: 30),
                               name: "Scaled", frame: CGRect(x: -10, y: 15, width: 80, height: 60))
        let rectangle = PixelSelection(rect: CGRect(x: 0, y: 19, width: 20, height: 12), shape: .rectangle)
        let copied = try ImageEngine.copySelection(rectangle, from: layer)
        expectEqual(copied.image.width, 10); expectEqual(copied.image.height, 6)
        expectEqual(copied.frame, rectangle.rect)
        for y in 0..<6 {
            for x in 0..<10 { expectEqual(try pixel(copied.image, x, y), try pixel(image, x + 5, y + 2)) }
        }
        let erased = try ImageEngine.deletingSelection(rectangle, from: layer)
        expectEqual(try pixel(erased, 5, 2)[3], 0)
        expectEqual(try pixel(erased, 14, 7)[3], 0)
        expectEqual(try pixel(erased, 4, 2), try pixel(image, 4, 2))
        expectEqual(try pixel(erased, 5, 22), try pixel(image, 5, 22)) // no vertical flip
        let ellipse = PixelSelection(rect: CGRect(x: 0, y: 19, width: 40, height: 32), shape: .ellipse)
        let circle = try ImageEngine.copySelection(ellipse, from: layer)
        expectEqual(circle.image.width, 20); expectEqual(circle.image.height, 16)
        expectEqual(try pixel(circle.image, 0, 0)[3], 0)
        expectEqual(try pixel(circle.image, 19, 15)[3], 0)
        expectEqual(try pixel(circle.image, 10, 8), try pixel(image, 15, 10))
        let hole = try ImageEngine.deletingSelection(ellipse, from: layer)
        expectEqual(try pixel(hole, 15, 10)[3], 0)
        expectEqual(try pixel(hole, 5, 2), try pixel(image, 5, 2))
        expectEqual(try pixel(hole, 5, 27), try pixel(image, 5, 27))
        // Clipping an ellipse at the layer edge must not re-center its shape.
        let partial = PixelSelection(rect: CGRect(x: -30, y: 15, width: 40, height: 40), shape: .ellipse)
        let half = try ImageEngine.copySelection(partial, from: layer)
        expectEqual(half.image.width, 10)
        expectGreater(try pixel(half.image, 0, 10)[3], 240)
        expectEqual(try pixel(half.image, 9, 0)[3], 0)
        let outside = PixelSelection(rect: CGRect(x: 150, y: 130, width: 10, height: 10), shape: .rectangle)
        expectThrows(try ImageEngine.copySelection(outside, from: layer))
        expectThrows(try ImageEngine.deletingSelection(outside, from: layer))
        let fractional = PixelSelection(rect: CGRect(x: 0.2, y: 19.2, width: 19.5, height: 11.5), shape: .rectangle)
        let fractionalCopy = try ImageEngine.copySelection(fractional, from: layer)
        expectEqual(fractionalCopy.frame, rectangle.rect)
    }

    func testSelectionHistoryAndScope() async throws {
        let model = try await model()
        let before = model.document, history = model.undoStack.count
        model.setSelectionTool(.rectangle)
        model.deleteFromCanvas() // No marquee must never delete the layer.
        expectEqual(model.document.layers.count, 2)
        model.updateSelection(CGRect(x: 0, y: 19, width: 20, height: 12))
        expectEqual(model.undoStack.count, history)
        model.deleteFromCanvas()
        expectEqual(model.undoStack.count, history + 1)
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.document.frame, before.frame)
        expectTrue(model.document.layers[0].image === before.layers[0].image)
        expectEqual(try pixel(try unwrap(model.document.image), 5, 2)[3], 0)
        expectTrue(model.document.backgroundRemovalSource === model.document.image)
        model.undo(); expectTrue(model.document.image === before.image)
        expectTrue(!model.isSelecting)
        model.redo(); expectEqual(try pixel(try unwrap(model.document.image), 5, 2)[3], 0)
        model.setSelectionTool(.ellipse); model.updateSelection(CGRect(x: 0, y: 15, width: 50, height: 50))
        model.selectLayer(before.layers[0].id)
        expectTrue(!model.isSelecting && model.pixelSelection == nil)
        model.setSelectionTool(.rectangle); model.updateSelection(CGRect(x: 0, y: 0, width: 200, height: 150))
        model.deleteSelection()
        expectThrows(try ImageEngine.contentBounds(of: unwrap(model.document.image)))
        expectEqual(model.document.layers.count, 2)
        model.undo(); expectTrue(model.document.image === before.layers[0].image)
    }

    func testSelectionClipboard() async throws {
        if CommandLine.arguments.contains("--headless") { throw TestSkipped("Clipboard service omitted by --headless.") }
        let model = try await model()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.setSelectionTool(.ellipse)
        model.updateSelection(CGRect(x: 0, y: 19, width: 40, height: 32))
        let history = model.undoStack.count
        model.copySelection(to: board)
        expectEqual(model.undoStack.count, history)
        let png = try ImageEngine.decode(unwrap(board.data(forType: .png)))
        expectEqual(png.width, 20); expectEqual(png.height, 16)
        expectEqual(try pixel(png, 0, 0)[3], 0)
        expectTrue(model.importPasteboard(board))
        expectTrue(model.pendingImport == nil)
        expectEqual(model.document.layers.count, 3)
        expectEqual(model.document.frame, CGRect(x: 0, y: 19, width: 40, height: 32))
        expectEqual(try pixel(try unwrap(model.document.image), 0, 0)[3], 0)
        expectEqual(model.document.image?.width, 20)
        model.undo(); expectEqual(model.document.layers.count, 2)
        model.redo(); expectEqual(model.document.layers.count, 3)
        let other = EditorModel()
        expectTrue(other.importPasteboard(board))
        expectEqual(other.document.image?.width, 20)
        expectTrue(other.document.layers.count == 1 && other.pendingImport == nil)
    }
}
