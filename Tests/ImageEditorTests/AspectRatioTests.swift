import AppKit

@MainActor
final class AspectRatioTests {
    private func model() async throws -> EditorModel {
        let model = EditorModel()
        model.setCanvas(width: 200, height: 150); model.setPadding(10)
        let context = try ImageEngine.context(width: 80, height: 60)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 40, width: 20, height: 20))
        let data = try ImageEngine.encode(unwrap(context.makeImage()), format: .png, quality: 1)
        model.importImages([.data(data, name: "Back"), .data(data, name: "Front")])
        let deadline = Date().addingTimeInterval(5)
        while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(model.errorMessage == nil && model.hasImage && !model.isBusy)
        return model
    }

    private func expectRatio(_ size: CGSize, _ ratio: AspectRatio) {
        // The secondary dimension is rounded to the nearest source/output pixel.
        expectTrue(abs(size.height - size.width / ratio.value) <= max(1, 1 / ratio.value))
    }

    func testPresetsAndCanvas() async throws {
        expectEqual(AspectRatio(1080, 1920), AspectRatio(9, 16))
        expectEqual(AspectRatio(1080, 1359), AspectRatio(120, 151))
        expectEqual(AspectRatioPreset.social.map(\.name), ["Instagram", "Facebook", "X", "LinkedIn", "TikTok"])
        let model = try await model()
        let before = model.document, history = model.undoStack.count
        let story = AspectRatio(9, 16)
        model.setCanvasAspectRatio(story)
        expectEqual(model.document.canvasAspectRatio, story)
        expectRatio(model.document.canvas, story)
        expectEqual(model.undoStack.count, history + 1)
        // Presets use the existing area, rather than adopting the chart's pixels.
        expectTrue(model.document.canvas.width < 200 && model.document.canvas.height < 300)
        for (old, new) in zip(before.layers, model.document.layers) {
            expectEqual(old.frame.size, new.frame.size)
            expectEqual(old.frame.midX - before.canvas.width / 2, new.frame.midX - model.document.canvas.width / 2)
            expectEqual(old.frame.midY - before.canvas.height / 2, new.frame.midY - model.document.canvas.height / 2)
            expectTrue(old.image === new.image)
        }
        model.setCanvas(width: 450)
        expectEqual(model.document.canvas, CGSize(width: 450, height: 800))
        expectEqual(model.document.canvasAspectRatio, story)
        model.setCanvas(height: 1600)
        expectEqual(model.document.canvas, CGSize(width: 900, height: 1600))
        model.swapCanvasDimensions()
        expectEqual(model.document.canvas, CGSize(width: 1600, height: 900))
        expectEqual(model.document.canvasAspectRatio, story.swapped)
        model.undo(); model.undo(); model.undo(); model.undo()
        expectEqual(model.document.canvas, before.canvas)
        expectTrue(model.document.canvasAspectRatio == nil)
        model.redo(); expectEqual(model.document.canvasAspectRatio, story)
        model.setCanvas(width: 90_000)
        expectGreaterOrEqual(CGFloat(8192), model.document.canvas.height)
        expectRatio(model.document.canvas, story)
        model.setCanvasAspectRatio(nil)
        model.setCanvas(width: 321)
        expectEqual(model.document.canvas.width, 321)
    }

    func testCropConstraintsAndScope() async throws {
        let model = try await model()
        model.setScale(200); model.setPosition(x: -30, y: 20)
        let before = model.document, history = model.undoStack.count
        let square = AspectRatio(1, 1)
        model.startLayerCrop(); model.setCropAspectRatio(square)
        expectEqual(model.cropPixelRect?.size, CGSize(width: 60, height: 60))
        model.setCrop(width: 24)
        expectEqual(model.cropPixelRect?.size, CGSize(width: 24, height: 24))
        model.setCrop(height: 16)
        expectEqual(model.cropPixelRect?.size, CGSize(width: 16, height: 16))
        model.updateCrop(try unwrap(model.cropRect).offsetBy(dx: 9999, dy: -9999), preservingSize: true)
        expectEqual(model.cropPixelRect, CGRect(x: 64, y: 0, width: 16, height: 16))
        model.resetCrop()
        expectEqual(model.cropPixelRect?.size, CGSize(width: 60, height: 60))
        model.setCropAspectRatio(AspectRatio(4, 5)); model.swapCropAspectRatio()
        expectEqual(model.cropAspectRatio, AspectRatio(5, 4))
        expectRatio(try unwrap(model.cropPixelRect).size, AspectRatio(5, 4))
        model.setCropAspectRatio(square)
        model.setCrop(width: 30)
        let expected = try unwrap(model.cropPixelRect)
        expectEqual(model.undoStack.count, history)
        model.applyCrop()
        expectEqual(model.document.image?.width, 30)
        expectEqual(model.document.image?.height, 30)
        expectEqual(model.document.canvas, before.canvas)
        expectTrue(model.document.layers[0].image === before.layers[0].image)
        expectEqual(model.document.frame, ImageEngine.canvasRect(expected, in: try unwrap(before.selectedLayer)))
        model.undo(); expectTrue(model.document.image === before.image)
        model.startCrop(); model.setCropAspectRatio(AspectRatio(16, 9))
        model.updateCrop(CGRect(x: 20, y: 30, width: 100, height: 100), anchor: .zero)
        expectRatio(try unwrap(model.cropRect).size, AspectRatio(16, 9))
        let size = try unwrap(model.cropRect).size
        model.setCrop(x: 9999, y: 9999)
        expectEqual(model.cropRect?.size, size)
        model.setCropAspectRatio(nil); model.setCrop(width: 19, height: 11)
        expectEqual(model.cropRect?.size, CGSize(width: 19, height: 11))
        model.cancelCrop()
        expectEqual(model.document.canvas, before.canvas)
    }

    func testExportDimensionsAndPixels() async throws {
        let model = try await model()
        model.setCanvas(width: 200, height: 100)
        model.setScale(100); model.setPosition(x: 20, y: 10)
        let before = model.document, history = model.undoStack.count
        model.setExportResizing(true)
        model.setExportDimension(400, axis: .width)
        expectEqual(model.exportOutputSize, CGSize(width: 400, height: 200))
        expectTrue(model.exportIncludesCanvasPadding && !model.includeCanvasPadding)
        model.setExportDimension(75, axis: .height)
        expectEqual(model.exportOutputSize, CGSize(width: 150, height: 75))
        model.setExportDimension(400, axis: .width)
        let snapshot = model.pendingExport
        let image = try ImageEngine.decode(snapshot.encoded())
        expectEqual(image.width, 400); expectEqual(image.height, 200)
        let pixels = try AIEditTests().pixels(image)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(y * image.width + x) * 4..<(y * image.width + x) * 4 + 4]) }
        expectEqual(pixel(0, 0)[3], 0) // Padding remains, preserving artboard proportions.
        expectGreater(pixel(45, 25)[2], 240) // Top-left blue remains at its scaled placement.
        expectGreater(pixel(100, 100)[0], 240)
        model.format = .jpeg
        let jpeg = try ImageEngine.decode(model.pendingExport.encoded())
        expectEqual(jpeg.width, 400); expectEqual(jpeg.height, 200)
        let matte = try AIEditTests().pixels(jpeg)
        expectGreater(matte[0], 245); expectEqual(matte[3], 255)
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.document.frame, before.frame)
        expectEqual(model.undoStack.count, history)
        // Settings/geometry changes after a pending export cannot change that export.
        model.setExportDimension(100, axis: .width)
        expectEqual(try ImageEngine.decode(snapshot.encoded()).width, 400)
        model.setCanvas(width: 100, height: 200)
        expectEqual(model.exportOutputSize, CGSize(width: 100, height: 200))
        model.setExportDimension(90_000, axis: .width)
        expectEqual(model.exportOutputSize, CGSize(width: 4096, height: 8192))
        model.undo()
        expectEqual(model.exportOutputSize, CGSize(width: 4096, height: 2048))
        model.setExportResizing(false)
        expectTrue(model.exportOutputSize == nil && !model.exportIncludesCanvasPadding)
    }

    func testResizedExportSavedStateAndClipboard() async throws {
        let model = try await model()
        model.setExportResizing(true); model.setExportDimension(100, axis: .width)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ratio-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try await model.writeExport(model.pendingExport, to: url)
        expectTrue(!model.hasUnexportedChanges)
        model.setExportDimension(200, axis: .width); expectTrue(model.hasUnexportedChanges)
        model.setExportDimension(100, axis: .width); expectTrue(!model.hasUnexportedChanges)
        model.setExportResizing(false); expectTrue(model.hasUnexportedChanges)
        model.setExportResizing(true); model.setExportDimension(100, axis: .width)
        if CommandLine.arguments.contains("--headless") { return }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.format = .jpeg
        try await model.copyExport(model.pendingExport, to: board)
        let copied = try ImageEngine.decode(unwrap(board.data(forType: .png)))
        expectEqual(copied.width, 100); expectEqual(copied.height, 75)
    }
}
