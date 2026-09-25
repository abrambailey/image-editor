import AppKit

@MainActor
final class ExportSafetyTests {
    private func imported(_ existing: EditorModel? = nil) async throws -> EditorModel {
        let model = existing ?? EditorModel()
        let source = try AIEditTests().solid()
        model.importData(try ImageEngine.encode(source, format: .png, quality: 1), name: "Safety fixture")
        let deadline = Date().addingTimeInterval(5)
        while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expectTrue(model.hasImage && !model.isBusy && model.errorMessage == nil)
        return model
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSuccessfulExportAndHistory() async throws {
        let model = try await imported()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("saved.png")
        expectTrue(model.hasUnexportedChanges)
        let saved = model.pendingExport
        try await model.writeExport(saved, to: destination)
        expectEqual(try Data(contentsOf: destination), try saved.encoded())
        expectTrue(!model.hasUnexportedChanges)
        model.zoomIn()
        model.selectLayer(try unwrap(model.document.selectedLayerID))
        expectTrue(!model.hasUnexportedChanges)
        model.nudge(dx: 10, dy: 0)
        expectTrue(model.hasUnexportedChanges)
        model.undo(); expectTrue(!model.hasUnexportedChanges)
        model.redo(); expectTrue(model.hasUnexportedChanges)
        model.undo()
        model.beginGesture()
        model.updateFrame(model.document.frame.offsetBy(dx: 20, dy: 0))
        model.prepareForTabSwitch()
        expectTrue(model.hasUnexportedChanges)
        model.undo(); expectTrue(!model.hasUnexportedChanges)
        model.format = .jpeg; expectTrue(model.hasUnexportedChanges)
        model.format = .png; expectTrue(!model.hasUnexportedChanges)
        model.includeCanvasPadding = true; expectTrue(model.hasUnexportedChanges)
        model.includeCanvasPadding = false; expectTrue(!model.hasUnexportedChanges)
        model.startCrop()
        model.setCrop(width: 400, height: 400)
        model.applyCrop(); expectTrue(model.hasUnexportedChanges)
        model.undo(); expectTrue(!model.hasUnexportedChanges)
    }

    func testFailedAndOlderExportsStayDirty() async throws {
        let model = try await imported()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = model.pendingExport
        do {
            try await model.writeExport(snapshot, to: directory.appendingPathComponent("missing/file.png"))
            fail("Writing to a missing directory should fail")
        } catch { expectTrue(model.hasUnexportedChanges) }
        model.nudge(dx: 30, dy: 0)
        let destination = directory.appendingPathComponent("older.png")
        try await model.writeExport(snapshot, to: destination)
        expectEqual(try Data(contentsOf: destination), try snapshot.encoded())
        expectTrue(model.hasUnexportedChanges)
        model.undo(); expectTrue(!model.hasUnexportedChanges)
        model.deleteLayer()
        expectTrue(!model.hasImage && model.hasUnexportedChanges)
        model.undo(); expectTrue(!model.hasUnexportedChanges)
    }

    func testCloseRequiresExplicitDecision() async throws {
        let workspace = EditorWorkspace()
        let model = try await imported(workspace.activeModel)
        expectTrue(!workspace.close(model.id)) // No presenter is never permission to discard.
        expectTrue(workspace.activeModel === model)
        var requested: UUID?
        workspace.confirmClose = { requested = $0.id }
        expectTrue(!workspace.close(model.id))
        expectEqual(requested, model.id)
        expectTrue(workspace.activeModel === model && !workspace.canReopenTab)
        expectTrue(workspace.close(model.id, discardingChanges: true))
        workspace.reopenTab()
        expectTrue(workspace.activeModel === model && model.hasUnexportedChanges)
        model.startCrop()
        expectTrue(!workspace.close(model.id, discardingChanges: true))
        model.cancelCrop()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await model.writeExport(model.pendingExport, to: directory.appendingPathComponent("saved.png"))
        requested = nil
        expectTrue(workspace.close(model.id))
        expectTrue(requested == nil)
        // Every dirty tab must be acknowledged before it can enter the eviction cache.
        for _ in 0..<7 {
            let next = try await imported(workspace.newTab())
            expectTrue(!workspace.close(next.id))
            expectTrue(workspace.close(next.id, discardingChanges: true))
        }
        let empty = EditorModel()
        empty.setCanvas(width: 900)
        empty.renameDocument("Prepared")
        expectTrue(!empty.hasUnexportedChanges)
    }

    func testClipboardDoesNotAcknowledgeFileExport() async throws {
        if CommandLine.arguments.contains("--headless") {
            throw TestSkipped("Clipboard service omitted by --headless; run locally for copy coverage.")
        }
        let model = try await imported()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.format = .jpeg
        try await model.copyExport(model.pendingExport, to: board)
        let copied = try ImageEngine.decode(unwrap(board.data(forType: .png)))
        expectGreater(copied.width, 0)
        expectTrue(model.hasUnexportedChanges)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await model.writeExport(model.pendingExport, to: directory.appendingPathComponent("saved.jpg"))
        expectTrue(!model.hasUnexportedChanges)
        model.nudge(dx: 1, dy: 0)
        try await model.copyExport(model.pendingExport, to: board)
        expectTrue(model.hasUnexportedChanges)
    }

    func testExportCompletionOutcomes() async throws {
        let model = try await imported()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var result: Bool?
        model.chooseExportDestination = { _, choose in choose(nil) }
        model.exportImage { result = $0 }
        expectEqual(result, false)
        expectTrue(model.hasUnexportedChanges && !model.isBusy)

        func waitForExport() async throws {
            let deadline = Date().addingTimeInterval(5)
            while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            expectTrue(!model.isBusy)
        }
        model.chooseExportDestination = { _, choose in choose(directory.appendingPathComponent("missing/file.png")) }
        result = nil
        model.exportImage { result = $0 }
        try await waitForExport()
        expectEqual(result, false)
        expectTrue(model.hasUnexportedChanges && model.errorMessage != nil)
        model.errorMessage = nil

        let destination = directory.appendingPathComponent("completed.png")
        model.chooseExportDestination = { _, choose in choose(destination) }
        result = nil
        model.exportImage { result = $0 }
        try await waitForExport()
        expectEqual(result, true)
        expectTrue(!model.hasUnexportedChanges)
        expectTrue(FileManager.default.fileExists(atPath: destination.path))

        model.nudge(dx: 2, dy: 0)
        var choose: ((URL?) -> Void)?
        model.chooseExportDestination = { _, completion in choose = completion }
        model.exportImage { result = $0 }
        expectTrue(model.isBusy)
        model.format = .jpeg
        choose?(destination)
        try await waitForExport()
        expectEqual(result, true)
        expectTrue(model.hasUnexportedChanges) // The pending PNG did not save the newer JPG settings.
    }
}
