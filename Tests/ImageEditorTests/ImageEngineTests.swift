import AppKit
import ImageIO

final class ImageEngineTests {
    private func image(width: Int = 20, height: Int = 12, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try ImageEngine.context(width: width, height: height)
        draw(context)
        return try unwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try ImageEngine.context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try unwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }

    func testFitPreservesAspectRatioAndMinimumPadding() {
        let frame = ImageEngine.fittedFrame(imageSize: CGSize(width: 400, height: 800),
                                            canvas: CGSize(width: 1200, height: 1000), padding: 100)
        expectEqual(frame, CGRect(x: 400, y: 100, width: 400, height: 800))
    }

    func testExcessivePaddingStillProducesPositiveImageSize() {
        let frame = ImageEngine.fittedFrame(imageSize: CGSize(width: 400, height: 800),
                                            canvas: CGSize(width: 2, height: 2), padding: 100)
        expectGreater(frame.width, 0)
        expectGreaterOrEqual(frame.minX, 0)
        expectLessOrEqual(frame.maxY, 2)
    }

    func testTrimPreservesAsymmetricContentAndItsPixelPosition() throws {
        let original = try image { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 3, y: 2, width: 6, height: 4))
        }
        let result = try ImageEngine.trimmed(original)
        expectEqual(result.bounds, CGRect(x: 3, y: 6, width: 6, height: 4))
        expectEqual(result.image.width, 6)
        expectEqual(result.image.height, 4)
        let color = try pixel(result.image, x: 0, y: 0)
        expectEqual(color[0], 255); expectLess(color[1], 50)
        expectEqual(color[2], 0); expectEqual(color[3], 255)
    }

    func testFullyTransparentImageProducesHelpfulError() throws {
        let original = try image { _ in }
        expectThrows(try ImageEngine.trimmed(original)) { error in
            expectTrue(error.localizedDescription.contains("completely transparent"))
        }
    }

    func testPNGExportRetainsAlphaAndUsesTopLeftCoordinates() throws {
        let original = try image(width: 2, height: 2) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let rendered = try ImageEngine.render(image: original, frame: CGRect(x: 3, y: 1, width: 2, height: 2),
                                              canvas: CGSize(width: 10, height: 8), background: .transparent, format: .png)
        let encoded = try ImageEngine.encode(rendered, format: .png, quality: 1)
        let decoded = try ImageEngine.decode(encoded)
        expectEqual(decoded.width, 10); expectEqual(decoded.height, 8)
        expectEqual(try pixel(decoded, x: 0, y: 0)[3], 0)
        let color = try pixel(decoded, x: 3, y: 1)
        expectEqual(color[0], 255); expectLess(color[1], 50)
        expectEqual(color[2], 0); expectEqual(color[3], 255)
        expectEqual(try pixel(decoded, x: 3, y: 5)[3], 0)
        let source = try unwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
        let properties = try unwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        expectEqual(properties[kCGImagePropertyHasAlpha] as? Bool, true)
    }

    func testJPEGFlattensTransparentPixelsOntoWhite() throws {
        let original = try image { _ in }
        let rendered = try ImageEngine.render(image: original, frame: CGRect(x: 0, y: 0, width: 20, height: 12),
                                              canvas: CGSize(width: 20, height: 12), background: .transparent, format: .jpeg)
        let decoded = try ImageEngine.decode(ImageEngine.encode(rendered, format: .jpeg, quality: 0.9))
        let corner = try pixel(decoded, x: 0, y: 0)
        expectGreaterOrEqual(corner[0], 250)
        expectGreaterOrEqual(corner[1], 250)
        expectGreaterOrEqual(corner[2], 250)
        expectEqual(corner[3], 255)
    }

    func testBlackCanvasIsIncludedInPNGAndJPEG() throws {
        let original = try image { _ in }
        for format in ExportFormat.allCases {
            let rendered = try ImageEngine.render(image: original, frame: .zero, canvas: CGSize(width: 20, height: 12),
                                                  background: .black, format: format)
            expectEqual(try pixel(rendered, x: 0, y: 0), [0, 0, 0, 255])
        }
    }

    func testImageOnlyExportRemovesCanvasPaddingButKeepsWhiteImagePixels() throws {
        let original = try image(width: 4, height: 3) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 1, y: 1, width: 2, height: 1))
        }
        let reference = try ImageEngine.decode(ImageEngine.encode(original, format: .png, quality: 1))
        for background in CanvasBackground.allCases {
            for format in ExportFormat.allCases {
                let output = try ImageEngine.renderExport(image: original,
                    frame: CGRect(x: 8, y: 9, width: 4, height: 3), canvas: CGSize(width: 30, height: 25),
                    background: background, format: format, includeCanvasPadding: false)
                let decoded = try ImageEngine.decode(ImageEngine.encode(output, format: format, quality: 1))
                expectEqual(decoded.width, 4); expectEqual(decoded.height, 3)
                if format == .png {
                    expectEqual(try pixel(decoded, x: 0, y: 0), [255, 255, 255, 255])
                    expectEqual(try pixel(decoded, x: 1, y: 1), try pixel(reference, x: 1, y: 1))
                }
                let full = try ImageEngine.renderExport(image: original,
                    frame: CGRect(x: 8, y: 9, width: 4, height: 3), canvas: CGSize(width: 30, height: 25),
                    background: background, format: format, includeCanvasPadding: true)
                expectEqual(full.width, 30); expectEqual(full.height, 25)
            }
        }
    }

    func testImageOnlyExportRetainsFaintAlphaAndMattesAfterTrimming() throws {
        let original = try image(width: 8, height: 6) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 2, y: 2, width: 4, height: 2))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1.0 / 255))
            context.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
        }
        for format in ExportFormat.allCases {
            let output = try ImageEngine.renderExport(image: original,
                frame: CGRect(x: 10, y: 12, width: 8, height: 6), canvas: CGSize(width: 30, height: 30),
                background: .transparent, format: format, includeCanvasPadding: false)
            expectEqual(output.width, 5); expectEqual(output.height, 3)
            let alphas = try (0..<output.height).flatMap { y in
                try (0..<output.width).map { x in try pixel(output, x: x, y: y)[3] }
            }
            if format == .png {
                expectEqual(alphas.filter { $0 == 1 }.count, 1)
                expectEqual(alphas.filter { $0 == 255 }.count, 8)
                expectEqual(alphas.filter { $0 == 0 }.count, 6)
            } else {
                expectTrue(alphas.allSatisfy { $0 == 255 })
            }
        }
    }

    func testImageOnlyExportKeepsCroppedPixelsAndFractionalPlacement() throws {
        let original = try image(width: 6, height: 4) { context in
            for y in 0..<4 {
                for x in 0..<6 {
                    context.setFillColor(CGColor(red: CGFloat(x) / 6, green: CGFloat(y) / 4, blue: 0.5, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let frame = CGRect(x: -1.25, y: 1.5, width: 12, height: 8)
        let canvas = CGSize(width: 9, height: 7)
        let full = try ImageEngine.render(image: original, frame: frame, canvas: canvas, background: .transparent, format: .png)
        let bounds = try ImageEngine.contentBounds(of: full, minimumAlpha: 0)
        let expected = try unwrap(full.cropping(to: bounds))
        let output = try ImageEngine.renderExport(image: original, frame: frame, canvas: canvas,
            background: .transparent, format: .png, includeCanvasPadding: false)
        expectEqual(output.width, expected.width); expectEqual(output.height, expected.height)
        for y in 0..<output.height {
            for x in 0..<output.width {
                expectEqual(try pixel(output, x: x, y: y), try pixel(expected, x: x, y: y))
            }
        }
    }

    func testImageOnlyExportRejectsInvisibleContent() throws {
        let original = try image { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        }
        expectThrows(try ImageEngine.renderExport(image: original,
            frame: CGRect(x: 100, y: 100, width: 20, height: 12), canvas: CGSize(width: 30, height: 30),
            background: .white, format: .jpeg, includeCanvasPadding: false)) { error in
                expectTrue(error.localizedDescription.contains("outside the canvas"))
            }
        let transparent = try image { _ in }
        expectThrows(try ImageEngine.renderExport(image: transparent,
            frame: CGRect(x: 0, y: 0, width: 20, height: 12), canvas: CGSize(width: 30, height: 30),
            background: .white, format: .jpeg, includeCanvasPadding: false))
    }

    func testQualitySettingChangesJPEGEncoding() throws {
        let original = try image(width: 128, height: 128) { context in
            for y in 0..<128 {
                for x in 0..<128 {
                    context.setFillColor(CGColor(red: Double((x * 17 + y * 3) % 255) / 255,
                                                 green: Double((x * 11 + y * 29) % 255) / 255,
                                                 blue: Double((x * 7 + y * 13) % 255) / 255, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let low = try ImageEngine.encode(original, format: .jpeg, quality: 0.1)
        let high = try ImageEngine.encode(original, format: .jpeg, quality: 0.95)
        expectGreater(high.count, low.count * 2)
    }

    func testWhiteCleanupPreservesEnclosedWhiteDetails() throws {
        let original = try image(width: 32, height: 32) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 12, y: 12, width: 8, height: 8))
        }
        let cleaned = try ImageEngine.cleanWhiteEdges(original)
        expectEqual(try pixel(cleaned, x: 0, y: 0)[3], 0)
        expectEqual(try pixel(cleaned, x: 8, y: 8), [0, 0, 0, 255])
        expectEqual(try pixel(cleaned, x: 16, y: 16), [255, 255, 255, 255])
    }

    func testEXIFOrientationIsAppliedWhenImporting() throws {
        let original = try image(width: 20, height: 12) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        }
        let data = NSMutableData()
        let destination = try unwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
        expectTrue(CGImageDestinationFinalize(destination))
        let decoded = try ImageEngine.decode(data as Data)
        expectEqual(decoded.width, 12); expectEqual(decoded.height, 20)
    }

    func testInvalidImageAndOutOfRangeCanvasAreRejected() {
        expectThrows(try ImageEngine.decode(Data("not an image".utf8)))
        expectThrows(try ImageEngine.context(width: 0, height: 100))
        expectThrows(try ImageEngine.context(width: 8193, height: 100))
    }

    func testMaskKeepsSourceDetailAndExistingTransparency() throws {
        let original = try image(width: 4, height: 2) { context in
            context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.4, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
            context.clear(CGRect(x: 3, y: 0, width: 1, height: 2))
        }
        let unchanged = try ForegroundExtractor.apply(mask: [1], width: 1, height: 1, to: original)
        expectEqual(try pixel(unchanged, x: 0, y: 0), try pixel(original, x: 0, y: 0))
        let masked = try ForegroundExtractor.apply(mask: [0.5], width: 1, height: 1, to: original)
        let before = try pixel(original, x: 0, y: 0), after = try pixel(masked, x: 0, y: 0)
        for channel in 0..<4 { expectLessOrEqual(abs(Int(after[channel]) * 2 - Int(before[channel])), 1) }
        expectEqual(try pixel(masked, x: 3, y: 0), [0, 0, 0, 0])
    }

    func testMaskAlignmentOnNonSquareSource() throws {
        let original = try image(width: 6, height: 4) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 4))
        }
        // Top-left mask quadrant only. Detects vertical flips, transposition,
        // incorrect row strides, and half-pixel offsets during mask resizing.
        let cutout = try ForegroundExtractor.apply(mask: [1, 0, 0, 0], width: 2, height: 2, to: original)
        expectEqual(try pixel(cutout, x: 0, y: 0)[3], 255)
        expectEqual(try pixel(cutout, x: 5, y: 0)[3], 0)
        expectEqual(try pixel(cutout, x: 0, y: 3)[3], 0)
        expectEqual(try pixel(cutout, x: 2, y: 1)[3], 128)
        expectThrows(try ForegroundExtractor.apply(mask: [.nan], width: 1, height: 1, to: original))
        expectThrows(try ForegroundExtractor.apply(mask: [1], width: 2, height: 2, to: original))
    }

    func testModelOnRealProductWhenFixtureIsSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["CUTOUT_TEST_IMAGE"] else {
            throw TestSkipped("Set CUTOUT_TEST_IMAGE to run the on-device model against a real product image.")
        }
        let decoded = try ImageEngine.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let size = CGSize(width: decoded.width, height: decoded.height)
        // Force an opaque white input even if the fixture already contains alpha.
        let original = try ImageEngine.render(image: decoded, frame: CGRect(origin: .zero, size: size),
                                              canvas: size, background: .white, format: .png)
        let cutout = try ImageEngine.removeBackground(from: original)
        expectEqual(cutout.width, original.width); expectEqual(cutout.height, original.height)
        let bounds = try ImageEngine.contentBounds(of: cutout)
        expectLess(bounds.width * bounds.height, CGFloat(original.width * original.height))
        expectEqual(try pixel(cutout, x: 0, y: 0)[3], 0)
        if let output = ProcessInfo.processInfo.environment["CUTOUT_TEST_OUTPUT"] {
            try ImageEngine.encode(cutout, format: .png, quality: 1).write(to: URL(fileURLWithPath: output))
        }
        if ProcessInfo.processInfo.environment["CUTOUT_TEST_ALLURE"] == "1" {
            // Explicitly opt into coordinates from the user's 1200 × 675 original.
            expectEqual(size, CGSize(width: 1200, height: 675))
            guard original.width == 1200, original.height == 675 else { return }
            expectGreater(try pixel(cutout, x: 236, y: 200)[3], 220) // thin receiver wire
            expectEqual(try pixel(cutout, x: 615, y: 150)[3], 0) // hole inside clear hook
            expectGreater(try pixel(cutout, x: 648, y: 110)[3], 240) // hook retained
            expectEqual(try pixel(cutout, x: 660, y: 615)[3], 0) // ground shadow gone
            for y in [250, 300, 350] {
                let alphas = try (468..<488).map { try pixel(cutout, x: $0, y: y)[3] }
                expectLessOrEqual(alphas.filter { $0 > 25 && $0 < 230 }.count, 3)
            }
            for (x, y) in [(520, 300), (675, 400), (340, 300), (195, 425), (980, 250)] {
                expectEqual(try pixel(cutout, x: x, y: y), try pixel(original, x: x, y: y))
            }
        }
    }
}

final class EditorModelTests {
    func testReplacingCutoutPreservesSourcePlacement() throws {
        let context = try ImageEngine.context(width: 60, height: 40)
        let original = try unwrap(context.makeImage())
        var snapshot = EditorSnapshot()
        let layer = ImageLayer(image: original, original: original,
                               sourceBounds: CGRect(x: 0, y: 0, width: 60, height: 40), name: "Fixture",
                               frame: CGRect(x: 31, y: 52, width: 120, height: 80))
        snapshot.layers = [layer]
        snapshot.selectedLayerID = layer.id
        let firstBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        snapshot.replaceImage(try unwrap(original.cropping(to: firstBounds)), sourceBounds: firstBounds)
        expectEqual(snapshot.frame, CGRect(x: 51, y: 82, width: 60, height: 40))
        // A retry recovers details outside the first crop, keeping source scale/position.
        let betterBounds = CGRect(x: 5, y: 8, width: 45, height: 27)
        let better = try unwrap(original.cropping(to: betterBounds))
        snapshot.replaceImage(better, sourceBounds: betterBounds)
        expectEqual(snapshot.frame, CGRect(x: 41, y: 68, width: 90, height: 54))
        let frame = snapshot.frame
        snapshot.replaceImage(better, sourceBounds: betterBounds)
        expectEqual(snapshot.frame, frame)
    }

    @MainActor func testImportAndEditingWorkflow() async throws {
        let context = try ImageEngine.context(width: 20, height: 12)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 4, y: 2, width: 12, height: 8))
        let image = try unwrap(context.makeImage())
        let model = EditorModel()
        model.setCanvas(width: 200, height: 200)
        model.setPadding(10)
        model.importData(try ImageEngine.encode(image, format: .png, quality: 1))
        let deadline = Date().addingTimeInterval(10)
        while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(!model.isBusy)
        expectEqual(model.errorMessage, nil)
        expectEqual(model.imageSize, CGSize(width: 12, height: 8))
        expectEqual(model.document.sourceBounds, CGRect(x: 4, y: 2, width: 12, height: 8))
        let fitted = model.document.frame
        expectEqual(fitted.width, 180)
        expectEqual(fitted.midX, 100); expectEqual(fitted.midY, 100)
        model.beginGesture()
        model.updateFrame(fitted.offsetBy(dx: 15, dy: 27))
        model.endGesture()
        expectEqual(model.document.frame.minY, fitted.minY + 27)
        model.undo(); expectEqual(model.document.frame, fitted)
        model.redo(); expectEqual(model.document.frame.minX, fitted.minX + 15)
        model.setCanvas(width: 300, height: 100)
        expectEqual(model.document.frame.midX, 165)
        expectEqual(model.document.frame.midY, 77)
        model.center()
        expectEqual(model.document.frame.midX, 150); expectEqual(model.document.frame.midY, 50)
        model.setScale(100)
        expectEqual(model.document.frame.size, CGSize(width: 12, height: 8))
        model.nudge(dx: 1, dy: -10)
        expectEqual(model.document.frame.midX, 151); expectEqual(model.document.frame.midY, 40)
        model.restoreOriginal()
        expectEqual(model.imageSize, CGSize(width: 20, height: 12))
        expectEqual(model.document.sourceBounds, CGRect(x: 0, y: 0, width: 20, height: 12))
        expectEqual(model.document.frame.midX, 150)
    }

    @MainActor func testCropWorkflow() async throws {
        let model = EditorModel()
        model.startCrop()
        expectTrue(!model.isCropping)
        let context = try ImageEngine.context(width: 20, height: 12)
        for y in 0..<12 {
            for x in 0..<20 {
                context.setFillColor(CGColor(red: CGFloat(x) / 20, green: CGFloat(y) / 12, blue: 0.4, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        model.importData(try ImageEngine.encode(try unwrap(context.makeImage()), format: .png, quality: 1))
        let deadline = Date().addingTimeInterval(10)
        while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(!model.isBusy)
        expectEqual(model.errorMessage, nil)
        model.setCanvas(width: 30, height: 24)
        model.setPadding(8)
        model.setScale(100)
        model.setPosition(x: 5, y: 6)
        let before = model.document
        let undoCount = model.undoStack.count
        let selection = CGRect(x: 8, y: 4, width: 12, height: 14)
        func render(_ snapshot: EditorSnapshot, format: ExportFormat = .png) throws -> CGImage {
            try ImageEngine.render(image: unwrap(snapshot.image), frame: snapshot.frame,
                                   canvas: snapshot.canvas, background: snapshot.background, format: format)
        }
        func pixels(_ image: CGImage) throws -> Data {
            let context = try ImageEngine.context(width: image.width, height: image.height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try unwrap(context.data), count: context.bytesPerRow * context.height)
        }
        model.startCrop()
        model.updateCrop(selection)
        expectTrue(!model.canEdit)
        // Preview cannot leak into document edits or history.
        model.setCanvas(width: 800)
        model.setPadding(0)
        model.setBackground(.black)
        model.fitAndCenter()
        model.nudge(dx: 10, dy: 10)
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.document.frame, before.frame)
        expectEqual(model.document.padding, before.padding)
        expectEqual(model.document.background, before.background)
        expectEqual(model.undoStack.count, undoCount)
        model.cancelCrop()
        expectTrue(model.canEdit)
        expectEqual(model.undoStack.count, undoCount)
        model.startCrop()
        model.updateCrop(selection)
        model.applyCrop()
        expectTrue(!model.isCropping)
        expectEqual(model.document.canvas, selection.size)
        expectEqual(model.document.frame, before.frame.offsetBy(dx: -8, dy: -4))
        expectEqual(model.document.padding, 5)
        expectEqual(model.document.sourceBounds, before.sourceBounds)
        expectTrue(model.document.original === before.original)
        expectTrue(model.document.image === before.image)
        expectEqual(model.undoStack.count, undoCount + 1)
        // Asymmetric colors and transparent margins catch a flipped or recentered crop.
        let expected = try unwrap(render(before).cropping(to: selection))
        let actual = try render(model.document)
        expectEqual(actual.width, 12); expectEqual(actual.height, 14)
        expectEqual(try pixels(actual), try pixels(expected))
        let png = try ImageEngine.decode(ImageEngine.encode(actual, format: .png, quality: 1))
        expectEqual(try pixels(png), try pixels(expected))
        let jpg = try ImageEngine.decode(ImageEngine.encode(render(model.document, format: .jpeg), format: .jpeg, quality: 0.9))
        expectEqual(jpg.width, 12); expectEqual(jpg.height, 14)
        let jpgPixels = try pixels(jpg)
        expectTrue(jpgPixels[0] > 245 && jpgPixels[1] > 245 && jpgPixels[2] > 245)
        model.undo()
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.document.frame, before.frame)
        expectEqual(model.document.padding, before.padding)
        // Cancel and accepting the full canvas both preserve redo history.
        model.startCrop(); model.updateCrop(selection); model.undo()
        expectTrue(!model.isCropping)
        expectEqual(model.document.canvas, before.canvas)
        expectEqual(model.redoStack.count, 1)
        model.startCrop(); model.applyCrop()
        expectEqual(model.redoStack.count, 1)
        model.redo()
        expectEqual(model.document.canvas, selection.size)
        let firstCrop = model.document
        model.startCrop()
        model.updateCrop(CGRect(x: 2, y: 3, width: 5, height: 6))
        model.applyCrop()
        expectEqual(model.document.frame, before.frame.offsetBy(dx: -10, dy: -7))
        model.undo()
        expectEqual(model.document.canvas, firstCrop.canvas)
        expectEqual(model.document.frame, firstCrop.frame)
        model.startCrop()
        model.updateCrop(CGRect(x: -100, y: 900, width: 1000, height: 0))
        expectEqual(model.cropRect, CGRect(x: 0, y: 13, width: 12, height: 1))
        model.updateCrop(CGRect(x: CGFloat.nan, y: 0, width: 3, height: 4))
        expectEqual(model.cropRect, CGRect(x: 0, y: 13, width: 12, height: 1))
        model.setCrop(width: 3.4, height: 8)
        expectEqual(model.cropRect, CGRect(x: 0, y: 13, width: 3, height: 1))
        model.setCrop(x: 100, y: -100)
        expectEqual(model.cropRect, CGRect(x: 9, y: 0, width: 3, height: 1))
        model.resetCrop()
        expectEqual(model.cropRect, CGRect(origin: .zero, size: firstCrop.canvas))
        model.updateCrop(CGRect(x: 11, y: 13, width: 1, height: 1))
        model.applyCrop()
        expectEqual(model.document.canvas, CGSize(width: 1, height: 1))
        expectEqual(model.document.padding, 0)
        expectEqual(try render(model.document).width, 1)
    }

    @MainActor func testCanvasResizeAndUndoRedo() {
        let model = EditorModel()
        model.setCanvas(width: 1600, height: 900)
        expectEqual(model.document.canvas, CGSize(width: 1600, height: 900))
        model.undo()
        expectEqual(model.document.canvas, CGSize(width: 1200, height: 1200))
        model.redo()
        expectEqual(model.document.canvas, CGSize(width: 1600, height: 900))
        model.setBackground(.black)
        expectTrue(model.redoStack.isEmpty)
        model.undo()
        expectEqual(model.document.background, .transparent)
    }

    @MainActor func testCanvasLimitsAndPaddingClamp() {
        let model = EditorModel()
        model.setCanvas(width: -20, height: 90_000)
        expectEqual(model.document.canvas, CGSize(width: 1, height: 8192))
        expectEqual(model.document.padding, 0)
        model.setPadding(500)
        expectEqual(model.document.padding, 0)
    }
}
