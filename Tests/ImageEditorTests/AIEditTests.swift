import AppKit

actor FixtureImageEditor: AIImageEditing {
    var shouldFail = false
    var delay: UInt64 = 0
    var maskReceived = false
    var transparentBackgroundReceived = false
    var transparentResult = false
    func configure(fail: Bool = false, delay: UInt64 = 0, transparentResult: Bool = false) {
        shouldFail = fail; self.delay = delay; self.transparentResult = transparentResult
    }
    func edit(image: Data, mask: Data?, prompt: String, size: String, transparentBackground: Bool, apiKey: String) async throws -> Data {
        maskReceived = mask != nil
        transparentBackgroundReceived = transparentBackground
        // Intentionally finish after cancellation, to verify stale-result rejection.
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        if shouldFail { throw EditorError.message("Fixture request failed") }
        let source = try ImageEngine.decode(image)
        let context = try ImageEngine.context(width: source.width, height: source.height)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let w = CGFloat(source.width), h = CGFloat(source.height)
        if transparentResult {
            context.fill(CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.3, height: h * 0.8))
            context.setBlendMode(.copy)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.5))
            context.fill(CGRect(x: w * 0.2, y: h * 0.3, width: w * 0.1, height: h * 0.4))
        } else {
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        return try ImageEngine.encode(unwrap(context.makeImage()), format: .png, quality: 1)
    }
}

final class AIEditTests {
    func solid(width: Int = 100, height: Int = 80, color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)) throws -> CGImage {
        let context = try ImageEngine.context(width: width, height: height)
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try unwrap(context.makeImage())
    }
    func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try ImageEngine.context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try unwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
    }
    func testGeometryAndMask() throws {
        for (w, h) in [(1, 1), (8192, 1), (1, 8192), (1200, 675), (8192, 8192), (700, 2100)] {
            let g = AIEditGeometry(width: w, height: h)
            expectEqual(Int(g.requestSize.width) % 16, 0)
            expectEqual(Int(g.requestSize.height) % 16, 0)
            expectGreaterOrEqual(g.requestSize.width * g.requestSize.height, 655360)
            expectLessOrEqual(max(g.requestSize.width / g.requestSize.height, g.requestSize.height / g.requestSize.width), 3)
            expectLessOrEqual(max(g.requestSize.width, g.requestSize.height), 3840)
            expectTrue(CGRect(origin: .zero, size: g.requestSize).contains(g.imageRect))
        }
        let source = try solid()
        let strokes = [EditStroke(points: [CGPoint(x: 0.2, y: 0.2)], diameter: 0.2)]
        let input = try AIEditImaging.prepare(source, strokes: strokes)
        expectTrue(!input.transparentBackground) // RGBA does not necessarily contain transparency.
        let mask = try ImageEngine.decode(unwrap(input.mask))
        let image = try ImageEngine.decode(input.image)
        expectEqual(mask.width, image.width); expectEqual(mask.height, image.height)
        let data = try pixels(mask), rect = input.geometry.imageRect
        func alpha(_ x: CGFloat, _ y: CGFloat) -> UInt8 {
            let ix = Int(rect.minX + x * rect.width), iy = Int(rect.minY + y * rect.height)
            return data[(iy * mask.width + ix) * 4 + 3]
        }
        expectEqual(alpha(0.2, 0.2), 0) // transparent means editable
        expectEqual(alpha(0.2, 0.8), 255) // top-left coordinates, not vertically flipped
        expectEqual(alpha(0.8, 0.2), 255)
        expectTrue(try AIEditImaging.prepare(source, strokes: []).mask == nil)
        let restored = try AIEditImaging.restoreSize(image, geometry: input.geometry)
        expectEqual(restored.width, source.width); expectEqual(restored.height, source.height)
        expectThrows(try AIEditImaging.restoreSize(source, geometry: input.geometry))
        let translucent = try solid(color: CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        expectTrue(try AIEditImaging.prepare(translucent, strokes: []).transparentBackground)
        let padded = try AIEditImaging.prepare(solid(width: 1000, height: 100), strokes: [])
        expectTrue(!padded.transparentBackground) // Padding must not turn a photograph into a cutout.
        expectTrue(try AIEditImaging.hasTransparency(ImageEngine.decode(padded.image)))
    }

    func testBlendPreservesOutsidePixels() throws {
        let original = try solid()
        let edited = try solid(color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let strokes = [EditStroke(points: [CGPoint(x: 0.3, y: 0.3)], diameter: 0.5)]
        let selection = try pixels(AIEditImaging.selection(size: CGSize(width: 100, height: 80), strokes: strokes))
        let before = try pixels(original)
        for feather: CGFloat in [0, 6] {
            let after = try pixels(AIEditImaging.blend(original: original, edited: edited, strokes: strokes, feather: feather))
            for i in stride(from: 0, to: before.count, by: 4) where selection[i + 3] == 0 {
                expectEqual(Array(after[i..<i+4]), Array(before[i..<i+4]))
            }
            expectGreater(after[(24 * 100 + 30) * 4 + 2], 240)
            if feather > 0 {
                expectTrue(stride(from: 0, to: after.count, by: 4).contains { after[$0] > 0 && after[$0 + 2] > 0 })
            }
        }
    }

    func testRequestAndFailureHandling() throws {
        let input = try AIEditImaging.prepare(solid(), strokes: [])
        let request = try SunburstClient.request(image: input.image, mask: nil, prompt: "Silver casing", size: input.geometry.sizeParameter, transparentBackground: false, apiKey: "test-credential")
        let body = String(decoding: try unwrap(request.httpBody), as: UTF8.self)
        expectEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        expectTrue(body.contains("gpt-image-2.5-sunburst"))
        expectTrue(body.contains("Silver casing"))
        expectTrue(!body.contains("test-credential"))
        expectTrue(!body.contains("input_fidelity"))
        expectTrue(!body.contains("name=\"mask\""))
        expectTrue(body.contains("name=\"background\"\r\n\r\nauto\r\n"))
        let withMask = try SunburstClient.request(image: input.image, mask: input.image, prompt: "Edit", size: input.geometry.sizeParameter, transparentBackground: false, apiKey: "test")
        expectTrue(String(decoding: try unwrap(withMask.httpBody), as: UTF8.self).contains("name=\"mask\""))
        let cutout = try SunburstClient.request(image: input.image, mask: nil, prompt: "Remove right object", size: input.geometry.sizeParameter, transparentBackground: true, apiKey: "test")
        let cutoutBody = String(decoding: try unwrap(cutout.httpBody), as: UTF8.self)
        expectTrue(cutoutBody.contains("name=\"background\"\r\n\r\ntransparent\r\n"))
        expectTrue(cutoutBody.contains("name=\"output_format\"\r\n\r\npng\r\n"))
        expectTrue(cutoutBody.contains("output alpha channel"))
        expectThrows(try SunburstClient.request(image: input.image, mask: nil, prompt: "Edit", size: "1024x1024", transparentBackground: false, apiKey: "bad\r\nheader"))
        expectThrows(try SunburstClient.decodeResponse(Data("{}".utf8), status: 401)) { expectTrue($0.localizedDescription.contains("API key")) }
        expectThrows(try SunburstClient.decodeResponse(Data("{}".utf8), status: 429)) { expectTrue($0.localizedDescription.contains("limit")) }
        expectThrows(try SunburstClient.decodeResponse(Data("{}".utf8), status: 200))
        let response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": input.image.base64EncodedString()]]])
        expectEqual(try SunburstClient.decodeResponse(response, status: 200), input.image)
    }

    @MainActor func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(!condition())
    }

    @MainActor func testSessionAndApply() async throws {
        let service = FixtureImageEditor()
        let model = EditorModel()
        model.importData(try ImageEngine.encode(solid(), format: .png, quality: 1))
        try await wait { model.isBusy }
        model.setCanvas(width: 320, height: 240)
        let before = model.document, history = model.undoStack.count
        model.beginAIEdit(client: service, loadCredential: false)
        let session = try unwrap(model.aiEdit)
        expectTrue(model.isBusy && !model.canEdit)
        model.setCanvas(width: 999)
        expectEqual(model.document.canvas, before.canvas)
        session.apiKey = "fixture"; session.prompt = "Make the casing blue"
        session.addStroke(EditStroke(points: [CGPoint(x: 0.3, y: 0.3)], diameter: 0.3))
        session.generate()
        try await wait { session.isWorking || session.isBlending }
        expectTrue(await service.maskReceived)
        expectTrue(session.result != nil && session.blended != nil)
        expectEqual(session.preview, .generated)
        expectEqual(model.undoStack.count, history)
        expectTrue(model.document.image === before.image)
        session.preview = .original
        model.applyAIEdit()
        expectTrue(model.aiEdit != nil)
        session.preview = .blended
        let accepted = session.applicableImage
        model.applyAIEdit()
        expectTrue(model.aiEdit == nil)
        expectTrue(model.document.image === accepted)
        expectTrue(model.document.original === before.original)
        expectTrue(model.document.backgroundRemovalSource === accepted)
        expectEqual(model.document.frame, CGRect(origin: .zero, size: before.canvas))
        expectEqual(model.undoStack.count, history + 1)
        model.undo()
        expectTrue(model.document.image === before.image)
        expectEqual(model.document.frame, before.frame)
        model.redo()
        expectTrue(model.document.image === accepted)
        model.restoreOriginal()
        expectTrue(model.document.image === before.original)
        expectTrue(model.document.backgroundRemovalSource == nil)

        let cancelSession = AIEditSession(original: try solid(), client: service, loadCredential: false)
        cancelSession.apiKey = "fixture"; cancelSession.prompt = "Edit"
        await service.configure(delay: 500_000_000)
        cancelSession.generate()
        try await Task.sleep(nanoseconds: 100_000_000)
        cancelSession.cancelRequest()
        try await Task.sleep(nanoseconds: 600_000_000)
        expectTrue(cancelSession.result == nil && !cancelSession.isWorking && cancelSession.error == nil)
        await service.configure(fail: true)
        cancelSession.generate()
        try await wait { cancelSession.isWorking }
        expectTrue(cancelSession.result == nil && cancelSession.error != nil)
        model.beginAIEdit(client: service, loadCredential: false)
        let prior = model.document.image, priorHistory = model.undoStack.count
        model.cancelAIEdit()
        expectTrue(model.document.image === prior)
        expectEqual(model.undoStack.count, priorHistory)
    }

    @MainActor func testTransparencyThroughApplyAndExport() async throws {
        let service = FixtureImageEditor()
        await service.configure(transparentResult: true)
        let model = EditorModel()
        model.importData(try ImageEngine.encode(solid(), format: .png, quality: 1))
        try await wait { model.isBusy }
        model.beginAIEdit(client: service, loadCredential: false)
        let session = try unwrap(model.aiEdit)
        session.apiKey = "fixture"; session.prompt = "Remove the right object"
        func alpha(_ image: CGImage, x: Double, y: Double) throws -> UInt8 {
            let data = try pixels(image)
            return data[(Int(Double(image.height) * y) * image.width + Int(Double(image.width) * x)) * 4 + 3]
        }
        expectEqual(try alpha(session.original, x: 0.75, y: 0.5), 255)
        session.generate()
        try await wait { session.isWorking }
        expectTrue(await service.transparentBackgroundReceived)
        let result = try unwrap(session.result)
        expectEqual(try alpha(result, x: 0.05, y: 0.05), 0)
        // Newly removed regions use generated alpha; copying the old alpha would restore the object.
        expectEqual(try alpha(result, x: 0.75, y: 0.5), 0)
        expectEqual(try alpha(result, x: 0.15, y: 0.5), 255)
        expectGreater(try alpha(result, x: 0.25, y: 0.5), 120)
        expectLess(try alpha(result, x: 0.25, y: 0.5), 136)
        model.applyAIEdit()
        let applied = try unwrap(model.document.image)
        let rendered = try ImageEngine.render(image: applied, frame: model.document.frame,
                                              canvas: model.document.canvas, background: model.document.background, format: .png)
        let exported = try ImageEngine.decode(ImageEngine.encode(rendered, format: .png, quality: 1))
        expectEqual(try alpha(exported, x: 0.75, y: 0.5), 0)
        expectEqual(try alpha(exported, x: 0.15, y: 0.5), 255)
        expectGreater(try alpha(exported, x: 0.25, y: 0.5), 120)
        expectLess(try alpha(exported, x: 0.25, y: 0.5), 136)
        model.undo(); model.redo()
        expectEqual(try alpha(unwrap(model.document.image), x: 0.75, y: 0.5), 0)
    }
}
