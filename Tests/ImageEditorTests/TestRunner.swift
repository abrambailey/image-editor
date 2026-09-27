import Foundation

// A dependency-free runner so verification works with Command Line Tools alone.
// XCTest is supplied by full Xcode, which is intentionally not required here.
private var failures = 0
struct TestSkipped: Error { let message: String; init(_ message: String) { self.message = message } }
struct TestFailure: Error {}

func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}

func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { fail("Unexpected nil", file: file, line: line); throw TestFailure() }
    return value
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs != rhs { fail("\(lhs) != \(rhs)", file: file, line: line) }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
func expectGreater<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs <= rhs { fail("\(lhs) must exceed \(rhs)", file: file, line: line) }
}
func expectGreaterOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs < rhs { fail("\(lhs) must be >= \(rhs)", file: file, line: line) }
}
func expectLess<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs >= rhs { fail("\(lhs) must be < \(rhs)", file: file, line: line) }
}
func expectLessOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs > rhs { fail("\(lhs) must be <= \(rhs)", file: file, line: line) }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T,
                     file: StaticString = #filePath, line: UInt = #line,
                     inspect: (Error) -> Void = { _ in }) {
    do { _ = try expression(); fail("Expected an error", file: file, line: line) }
    catch { inspect(error) }
}

@main
struct TestRunner {
    @MainActor static func main() async {
        let engine = ImageEngineTests()
        let model = EditorModelTests()
        let ai = AIEditTests()
        let tests: [(String, () throws -> Void)] = [
            ("fit and padding", engine.testFitPreservesAspectRatioAndMinimumPadding),
            ("excessive padding", engine.testExcessivePaddingStillProducesPositiveImageSize),
            ("asymmetric alpha trim", engine.testTrimPreservesAsymmetricContentAndItsPixelPosition),
            ("transparent image rejection", engine.testFullyTransparentImageProducesHelpfulError),
            ("PNG alpha, dimensions, placement", engine.testPNGExportRetainsAlphaAndUsesTopLeftCoordinates),
            ("JPEG white matte", engine.testJPEGFlattensTransparentPixelsOntoWhite),
            ("black canvas export", engine.testBlackCanvasIsIncludedInPNGAndJPEG),
            ("image-only PNG/JPG export and optional canvas padding", engine.testImageOnlyExportRemovesCanvasPaddingButKeepsWhiteImagePixels),
            ("image-only export preserves faint alpha before matting", engine.testImageOnlyExportRetainsFaintAlphaAndMattesAfterTrimming),
            ("image-only export preserves crop and fractional placement", engine.testImageOnlyExportKeepsCroppedPixelsAndFractionalPlacement),
            ("image-only export rejects invisible content", engine.testImageOnlyExportRejectsInvisibleContent),
            ("JPEG quality", engine.testQualitySettingChangesJPEGEncoding),
            ("white edge cleanup", engine.testWhiteCleanupPreservesEnclosedWhiteDetails),
            ("EXIF orientation", engine.testEXIFOrientationIsAppliedWhenImporting),
            ("invalid input", engine.testInvalidImageAndOutOfRangeCanvasAreRejected),
            ("mask preserves source detail and alpha", engine.testMaskKeepsSourceDetailAndExistingTransparency),
            ("mask alignment", engine.testMaskAlignmentOnNonSquareSource),
            ("local model product cutout", engine.testModelOnRealProductWhenFixtureIsSupplied),
            ("replacement cutout placement", model.testReplacingCutoutPreservesSourcePlacement),
            ("canvas and undo/redo", model.testCanvasResizeAndUndoRedo),
            ("canvas and padding limits", model.testCanvasLimitsAndPaddingClamp),
            ("AI request geometry and mask alignment", ai.testGeometryAndMask),
            ("AI blend preserves pixels outside selection", ai.testBlendPreservesOutsidePixels),
            ("Sunburst request and API error handling", ai.testRequestAndFailureHandling)
        ]
        var skipped = 0
        for (name, test) in tests {
            let before = failures
            let start = Date()
            do {
                try test()
                if before == failures { print(String(format: "PASS %@ (%.2f s)", name, Date().timeIntervalSince(start))) }
            } catch let error as TestSkipped {
                skipped += 1; print("SKIP \(name): \(error.message)")
            } catch { fail("\(name): \(error.localizedDescription)") }
        }
        let beforeWorkflow = failures
        do {
            try await model.testImportAndEditingWorkflow()
            if beforeWorkflow == failures { print("PASS image import, placement, resizing, nudging and undo workflow") }
        } catch { fail("editing workflow: \(error.localizedDescription)") }
        let beforeCrop = failures
        do {
            try await model.testCropWorkflow()
            if beforeCrop == failures { print("PASS crop preview, pixel output, PNG/JPG, history, repeated crops and bounds") }
        } catch { fail("crop workflow: \(error.localizedDescription)") }
        let beforeAI = failures
        do {
            try await ai.testSessionAndApply()
            if beforeAI == failures { print("PASS AI preview, apply, undo/redo, failure and cancellation") }
        } catch { fail("AI editing workflow: \(error.localizedDescription)") }
        let beforeAlpha = failures
        do {
            try await ai.testTransparencyThroughApplyAndExport()
            if beforeAlpha == failures { print("PASS AI transparency through generation, apply, PNG export and history") }
        } catch { fail("AI transparency workflow: \(error.localizedDescription)") }
        let layers = LayerTests()
        let selections = SelectionTests()
        let expansion = LayerExpansionTests()
        let layerTests: [(String, () async throws -> Void)] = [
            ("layer expansion pixels, percentages, fill, alpha and limits", { try expansion.testExpansionPixelsAndLimits() }),
            ("layer expansion scope, placement, crop, fit and Undo", expansion.testExpansionWorkflow),
            ("layer pixel crop, fit, original, bounds and history", selections.testLayerCropAndFit),
            ("rectangle and ellipse pixels, scale, clipping and orientation", { try selections.testSelectionPixels() }),
            ("selection deletion, layer scope, transparency and history", selections.testSelectionHistoryAndScope),
            ("selection PNG clipboard, placement and paste as layer", selections.testSelectionClipboard),
            ("layer import, selection, transforms, history and atomic failures", layers.testLayerWorkflow),
            ("composite order, visibility, export and alpha hit testing", { try layers.testCompositeRendering() }),
            ("paste choices, multiple files and separate documents", layers.testPasteChoicesAndSeparateDocuments),
            ("AI composite input, flattening and layer undo", layers.testAICompositeAndUndo),
            ("independent tabs, rename/export names, close/reopen and empty tabs", WorkspaceTests().testTabsAndNames),
            ("successful export, editing and Undo restore saved state", ExportSafetyTests().testSuccessfulExportAndHistory),
            ("failed and older exports protect newer work", ExportSafetyTests().testFailedAndOlderExportsStayDirty),
            ("tab close requires export or explicit discard before eviction", ExportSafetyTests().testCloseRequiresExplicitDecision),
            ("clipboard copy never acknowledges a file export", ExportSafetyTests().testClipboardDoesNotAcknowledgeFileExport),
            ("export completion handles cancel, failure and successful writes", ExportSafetyTests().testExportCompletionOutcomes)
        ]
        for (name, test) in layerTests {
            let before = failures
            do { try await test(); if before == failures { print("PASS \(name)") } }
            catch let error as TestSkipped { skipped += 1; print("SKIP \(name): \(error.message)") }
            catch { fail("\(name): \(error.localizedDescription)") }
        }
        print("\(tests.count + 4 + layerTests.count) tests, \(failures) failures, \(skipped) skipped")
        exit(failures == 0 ? 0 : 1)
    }
}
