import AppKit

@MainActor
final class LayerExpansionTests {
    private let fixtures = AIEditTests()
    private func source() throws -> CGImage {
        let context = try ImageEngine.context(width: 12, height: 8)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 6, width: 3, height: 2))
        context.clear(CGRect(x: 4, y: 3, width: 2, height: 2))
        return try unwrap(context.makeImage())
    }
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
        let bytes = try fixtures.pixels(image)
        let index = (y * image.width + x) * 4
        return Array(bytes[index..<index + 4])
    }

    func testExpansionPixelsAndLimits() throws {
        let image = try source()
        let edges = LayerExpansion(top: 2, right: 3, bottom: 4, left: 5)
        let result = try ImageEngine.expanded(image, by: edges, fill: CGColor(gray: 1, alpha: 1))
        expectEqual(result.width, 20); expectEqual(result.height, 14)
        for y in 0..<8 {
            for x in 0..<12 { expectEqual(try pixel(result, x + 5, y + 2), try pixel(image, x, y)) }
        }
        for (x, y) in [(0, 0), (19, 13), (5, 1), (4, 2), (17, 2), (5, 10)] {
            expectEqual(try pixel(result, x, y), [255, 255, 255, 255])
        }
        // Border fill must never fill an existing transparent hole.
        expectEqual(try pixel(result, 9, 5)[3], 0)
        let percent = LayerExpansion(unit: .percent, top: 25, right: 25, bottom: 25, left: 25)
        let insets = try percent.pixelInsets(for: CGSize(width: 12, height: 8))
        expectEqual(insets, LayerExpansion.Insets(top: 2, right: 3, bottom: 2, left: 3))
        let colored = try ImageEngine.expanded(image, by: percent, fill: CGColor(colorSpace: ImageEngine.colorSpace, components: [0, 1, 0, 1]))
        expectEqual(colored.width, 18); expectEqual(colored.height, 12)
        expectEqual(try pixel(colored, 0, 0), [0, 255, 0, 255])
        let clear = try ImageEngine.expanded(image, by: edges, fill: nil)
        expectEqual(try pixel(clear, 0, 0)[3], 0)
        expectEqual(try pixel(clear, 5, 2), try pixel(image, 0, 0))
        let partial = try ImageEngine.expanded(image, by: edges, fill: CGColor(red: 0, green: 1, blue: 0, alpha: 0.5))
        expectTrue((127...128).contains(Int(try pixel(partial, 0, 0)[3])))
        expectTrue(try ImageEngine.expanded(image, by: LayerExpansion(), fill: nil) === image)
        let size = CGSize(width: 12, height: 8)
        expectThrows(try LayerExpansion(top: -1).pixelInsets(for: size))
        expectThrows(try LayerExpansion(left: .nan).pixelInsets(for: size))
        expectThrows(try LayerExpansion(right: .infinity).pixelInsets(for: size))
        expectThrows(try LayerExpansion(left: 8192).pixelInsets(for: size))
        expectThrows(try LayerExpansion(unit: .percent, top: .greatestFiniteMagnitude).pixelInsets(for: size))
        expectEqual(try LayerExpansion(left: 8180).pixelInsets(for: size).expandedSize(size).width, 8192)
        expectEqual(try LayerExpansion(unit: .percent, left: 12.5).pixelInsets(for: size).left, 2)
    }

    func testExpansionWorkflow() async throws {
        let model = EditorModel()
        model.setCanvas(width: 120, height: 100); model.setPadding(5)
        let data = try ImageEngine.encode(source(), format: .png, quality: 1)
        model.importImages([.data(data, name: "Back"), .data(data, name: "Front")])
        let deadline = Date().addingTimeInterval(10)
        while model.busyMessage != nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(!model.isBusy && model.errorMessage == nil)
        let backID = model.document.layers[0].id
        model.selectLayer(backID); model.setScale(200); model.setPosition(x: 10, y: 20)
        let before = model.document, count = model.undoStack.count
        model.selectLayer(model.document.layers[1].id)
        model.startLayerExpansion(backID)
        expectEqual(model.document.selectedLayerID, backID)
        expectEqual(model.layerExpansion?.id, backID)
        expectTrue(model.isBusy && !model.canEdit && !model.canImport)
        model.cancelLayerExpansion()
        expectEqual(model.undoStack.count, count)
        expectTrue(model.document.image === before.image)
        model.startLayerExpansion()
        expectThrows(try model.applyLayerExpansion(LayerExpansion(top: 9000), fill: nil))
        expectTrue(model.layerExpansion != nil)
        expectEqual(model.undoStack.count, count)
        let edges = LayerExpansion(top: 2, right: 3, bottom: 4, left: 5)
        try model.applyLayerExpansion(edges, fill: CGColor(gray: 1, alpha: 1))
        expectTrue(!model.isBusy && model.layerExpansion == nil)
        expectEqual(model.document.frame, CGRect(x: 0, y: 16, width: 40, height: 28))
        expectEqual(model.document.canvas, before.canvas)
        expectTrue(model.document.layers[1].image === before.layers[1].image)
        expectEqual(model.document.layers[1].frame, before.layers[1].frame)
        expectTrue(model.document.original === before.original)
        expectTrue(model.document.backgroundRemovalSource === model.document.image)
        expectEqual(model.undoStack.count, count + 1)
        model.fitAndCenter()
        expectEqual(model.document.frame, CGRect(x: 5, y: 11.5, width: 110, height: 77))
        model.undo(); model.undo()
        expectTrue(model.document.image === before.image)
        expectEqual(model.document.frame, before.frame)
        model.redo(); expectEqual(model.document.image?.width, 20)
        model.startLayerExpansion()
        let noOpCount = model.undoStack.count
        try model.applyLayerExpansion(LayerExpansion(), fill: nil)
        expectEqual(model.undoStack.count, noOpCount)
        model.startLayerCrop(); model.setCrop(x: 5, y: 2, width: 12, height: 8); model.applyCrop()
        expectEqual(try fixtures.pixels(unwrap(model.document.image)), try fixtures.pixels(unwrap(before.image)))
        model.undo(); model.restoreOriginal()
        expectEqual(model.document.image?.width, 12)
        model.undo(); expectEqual(model.document.image?.width, 20)
        model.toggleLayerVisibility(backID); model.startLayerExpansion(backID)
        expectTrue(model.layerExpansion == nil)
    }
}
