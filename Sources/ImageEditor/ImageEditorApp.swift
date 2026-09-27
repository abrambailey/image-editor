import AppKit
import SwiftUI

@main
struct ImageEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var workspace = EditorWorkspace()

    var body: some Scene {
        Window("Image Editor", id: "editor") {
            EditorWorkspaceView(workspace: workspace)
                .background(CloseProtectionView(workspace: workspace, appDelegate: delegate))
                .onAppear {
                    guard delegate.workspace == nil else { return }
                    delegate.workspace = workspace
                    delegate.openPendingFiles()
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    let model = workspace.activeModel
                    if CommandLine.arguments.contains("--preview-jpeg") { model.format = .jpeg }
                    if CommandLine.arguments.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                    if CommandLine.arguments.contains("--preview-small"), let window = NSApp.windows.first {
                        window.setContentSize(CGSize(width: 860, height: 660))
                    }
                    if let index = CommandLine.arguments.firstIndex(of: "--preview-image"),
                       CommandLine.arguments.indices.contains(index + 1), !model.hasImage, !model.isBusy {
                        model.importURL(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    }
                    #if !IMAGE_EDITOR_WINDOW_TEST
                    if let index = CommandLine.arguments.firstIndex(of: "--capture"),
                       CommandLine.arguments.indices.contains(index + 1) {
                        delegate.capturePath = CommandLine.arguments[index + 1]
                        delegate.captureWhenReady()
                    }
                    #endif
                    #if IMAGE_EDITOR_WINDOW_TEST
                    EditorWindowSmoke.schedule(delegate: delegate)
                    #endif
                }
        }
        .defaultSize(width: 1120, height: 800)
        .windowResizability(.contentMinSize)
        .commands { WorkspaceCommands(workspace: workspace) }
    }
}

private struct WorkspaceCommands: Commands {
    @ObservedObject var workspace: EditorWorkspace
    var body: some Commands { EditorCommands(model: workspace.activeModel, workspace: workspace) }
}

private struct EditorCommands: Commands {
    @ObservedObject var model: EditorModel
    @ObservedObject var workspace: EditorWorkspace

    var body: some Commands {

            CommandGroup(replacing: .newItem) {
                Button("New Image Tab") { workspace.newTab() }.keyboardShortcut("n")
                Button("Open Images…", action: { workspace.activeModel.openImage() }).keyboardShortcut("o").disabled(!model.canImport)
                Button("Add Images as Layers…", action: { workspace.activeModel.addImages() })
                    .keyboardShortcut("o", modifiers: [.command, .option]).disabled(!model.canImport)
                Button("Open Image from URL…") { workspace.activeModel.showURLSheet = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(!model.canImport)
                Divider()
                Button("Close Tab") { workspace.close(workspace.activeModel.id) }.keyboardShortcut("w").disabled(model.isBusy || model.isCropping)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export…") { workspace.activeModel.exportImage() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!model.canEdit)
                Button("Save Image As…") { workspace.activeModel.exportImage() }.keyboardShortcut("s").disabled(!model.canEdit)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: { workspace.activeModel.undo() }).keyboardShortcut("z").disabled((model.undoStack.isEmpty && !model.isCropping) || model.isBusy)
                Button("Redo", action: { workspace.activeModel.redo() }).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.redoStack.isEmpty || model.isBusy || model.isCropping)
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste Image", action: { workspace.activeModel.paste() }).keyboardShortcut("v", modifiers: [.command, .shift]).disabled(!model.canImport)
                Button("Copy Image") { workspace.activeModel.exportImage(copy: true) }
                    .keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!model.canEdit)
            }
            CommandMenu("Image") {
                Button("Edit with Sunburst…", action: { workspace.activeModel.startAIEdit() })
                    .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(!model.canEdit)
                Button("Crop Canvas…", action: { workspace.activeModel.startCrop() })
                    .keyboardShortcut("x", modifiers: [.command, .shift]).disabled(!model.canEdit)
                if model.isCropping {
                    Button("Apply Crop", action: { workspace.activeModel.applyCrop() }).disabled(model.isBusy)
                    Button("Cancel Crop", action: { workspace.activeModel.cancelCrop() }).disabled(model.isBusy)
                }
                Divider()
                Button("Remove Background", action: { workspace.activeModel.removeBackground() })
                    .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(!model.canEditLayer)
                Button("Restore Original", action: { workspace.activeModel.restoreOriginal() }).disabled(!model.canEditLayer)
                Button("Clean White Edges", action: { workspace.activeModel.cleanWhiteEdges() }).disabled(!model.canEditLayer)
                Divider()
                Button("Fit & Center", action: { workspace.activeModel.fitAndCenter() }).keyboardShortcut("f", modifiers: [.command, .shift]).disabled(!model.canEditLayer)
                Button("Center Layer", action: { workspace.activeModel.center() }).keyboardShortcut("k").disabled(!model.canEditLayer)
                Divider()
                Button("Fit Preview to Window") { workspace.activeModel.zoom = 1 }.keyboardShortcut("0").disabled(!model.hasImage)
            }

            CommandMenu("Tab") {
                Button("Rename Tab…") { workspace.beginRenaming(workspace.activeModel.id) }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.isBusy)
                Button("Reopen Closed Tab", action: workspace.reopenTab)
                    .keyboardShortcut("t", modifiers: [.command, .shift]).disabled(!workspace.canReopenTab)
                Divider()
                Button("Next Tab") { workspace.selectAdjacentTab(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift]).disabled(workspace.tabs.count < 2)
                Button("Previous Tab") { workspace.selectAdjacentTab(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift]).disabled(workspace.tabs.count < 2)
            }
            CommandMenu("Select") {
                Button("Rectangle Selection") { workspace.activeModel.setSelectionTool(.rectangle) }.disabled(!model.canSelectPixels)
                Button("Ellipse Selection") { workspace.activeModel.setSelectionTool(.ellipse) }.disabled(!model.canSelectPixels)
                Button("Deselect") { workspace.activeModel.setSelectionTool(nil) }
                    .keyboardShortcut("d").disabled(!model.isSelecting || model.isBusy)
                Divider()
                Button("Copy Selection") { workspace.activeModel.copySelection() }.disabled(!model.canUseSelection)
                Button("Delete Selected Pixels") { workspace.activeModel.deleteSelection() }.disabled(!model.canUseSelection)
            }
            CommandMenu("Layer") {
                Button("Crop Layer…") { workspace.activeModel.startLayerCrop() }.disabled(!model.canSelectPixels)
                Button("Expand Layer…") { workspace.activeModel.startLayerExpansion() }.disabled(!model.canSelectPixels)
                Button("Duplicate Layer", action: { workspace.activeModel.duplicateLayer() }).keyboardShortcut("j").disabled(!model.canEdit)
                Button("Delete Layer", action: { workspace.activeModel.deleteLayer() }).disabled(!model.canEdit)
                Divider()
                Button("Bring Forward") { workspace.activeModel.moveLayer(by: 1) }.keyboardShortcut("]").disabled(!model.canMoveLayer(by: 1))
                Button("Send Backward") { workspace.activeModel.moveLayer(by: -1) }.keyboardShortcut("[").disabled(!model.canMoveLayer(by: -1))
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspace: EditorWorkspace?
    var model: EditorModel? { workspace?.activeModel }
    private var pendingURLs: [URL] = []
    var capturePath: String?
    private(set) var closeCoordinator: EditorCloseCoordinator?

    func protectWindow(_ window: NSWindow, workspace: EditorWorkspace) {
        guard closeCoordinator == nil else { return }
        closeCoordinator = EditorCloseCoordinator(workspace: workspace, window: window)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeCoordinator?.requestQuit { sender.reply(toApplicationShouldTerminate: $0) } ?? .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model, model.canImport { model.requestImport(urls.map(ImageImport.url), isPaste: false) }
        else if let workspace { workspace.openImages(urls.map(ImageImport.url)) }
        else { pendingURLs.append(contentsOf: urls) }
    }

    func openPendingFiles() {
        guard let model, !pendingURLs.isEmpty else { return }
        let items = pendingURLs.map(ImageImport.url)
        pendingURLs.removeAll()
        model.requestImport(items, isPaste: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        #if IMAGE_EDITOR_WINDOW_TEST
        return false
        #else
        return true
        #endif
    }

    // Standard Paste follows the active tab even before its canvas receives a click.
    @objc func paste(_ sender: Any?) { model?.paste() }
    @objc func copy(_ sender: Any?) { model?.copyPixels() }

    func captureWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let path = self.capturePath else { return }
            if self.model?.isBusy == true { self.captureWhenReady(); return }
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView else { return }
            // The titlebar is a separate compositor surface; capture the app content
            // without its unpainted titlebar inset when no screen permission is needed.
            let captureRect = view.safeAreaRect
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: captureRect) else { return }
            view.cacheDisplay(in: captureRect, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            try? String(window.windowNumber).write(toFile: path + ".window-id", atomically: true, encoding: .utf8)
            self.capturePath = nil
            if CommandLine.arguments.contains("--quit-after-capture") { NSApp.terminate(nil) }
        }
    }
}
