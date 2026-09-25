import AppKit

@MainActor
final class WorkspaceTests {
    private func wait(_ models: [EditorModel]) async throws {
        let deadline = Date().addingTimeInterval(5)
        while models.contains(where: { $0.busyMessage != nil }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expectTrue(models.allSatisfy { $0.busyMessage == nil && $0.errorMessage == nil })
    }

    func testTabsAndNames() async throws {
        let fixture = try AIEditTests().solid()
        let data = try ImageEngine.encode(fixture, format: .png, quality: 1)
        let workspace = EditorWorkspace()
        let first = workspace.activeModel
        first.importData(data, name: "First")
        try await wait([first])
        first.setPosition(x: 75, y: 80)
        let firstFrame = first.document.frame
        first.requestImport([.data(data, name: "Second"), .data(data, name: "Third")], isPaste: true)
        first.resolveImport(.newImages)
        try await wait(workspace.tabs)
        expectEqual(workspace.tabs.count, 3)
        expectEqual(workspace.tabs.map { $0.document.filename }, ["First", "Second", "Third"])
        let second = workspace.activeModel
        expectEqual(second.document.filename, "Second")
        second.setCanvas(width: 700, height: 600)
        second.format = .jpeg
        second.renameDocument("  Publication photo  ")
        expectEqual(second.document.filename, "Publication photo")
        expectEqual(second.suggestedExportFilename, "Publication photo.jpg")
        second.undo(); expectEqual(second.document.filename, "Second")
        second.redo(); expectEqual(second.document.filename, "Publication photo")
        second.renameDocument("   \n")
        expectEqual(second.document.filename, "Publication photo")
        second.renameDocument("Product.png")
        expectEqual(second.suggestedExportFilename, "Product.jpg")
        second.format = .png
        expectEqual(second.suggestedExportFilename, "Product.png")
        second.renameDocument("Product / Left: front")
        expectEqual(second.suggestedExportFilename, "Product - Left- front.png")
        workspace.select(first.id)
        expectTrue(workspace.activeModel === first)
        expectEqual(first.document.frame, firstFrame)
        expectEqual(first.document.canvas, CGSize(width: 1200, height: 1200))
        expectEqual(first.document.filename, "First")
        first.undo()
        expectEqual(second.document.filename, "Product / Left: front")
        workspace.selectAdjacentTab(-1)
        expectEqual(workspace.activeModel.document.filename, "Third")
        workspace.selectAdjacentTab(1)
        expectTrue(workspace.activeModel === first)
        workspace.close(second.id, discardingChanges: true)
        expectEqual(workspace.tabs.count, 2)
        expectTrue(workspace.activeModel === first)
        workspace.reopenTab()
        expectTrue(workspace.activeModel === second)
        expectEqual(second.document.canvas, CGSize(width: 700, height: 600))
        expectEqual(second.document.filename, "Product / Left: front")
        workspace.close(second.id, discardingChanges: true)
        expectEqual(workspace.activeModel.document.filename, "Third")
        workspace.close(first.id, discardingChanges: true)
        workspace.close(workspace.activeModel.id, discardingChanges: true)
        expectEqual(workspace.tabs.count, 1)
        expectTrue(!workspace.activeModel.hasImage)
        let empty = workspace.activeModel
        empty.renameDocument("Prepared canvas")
        empty.importData(data, name: "Source")
        try await wait([empty])
        expectEqual(empty.document.filename, "Prepared canvas")
        expectEqual(empty.suggestedExportFilename, "Prepared canvas.png")
        let new = workspace.newTab()
        expectEqual(workspace.tabs.count, 2)
        expectTrue(workspace.activeModel === new)
        expectEqual(new.document.filename, "Untitled")
    }
}
