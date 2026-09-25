import AppKit
import SwiftUI

/// Compiled only by window-test.sh, into a separate test executable.
@MainActor
enum EditorWindowSmoke {
    static var started = false
    static func schedule(delegate: AppDelegate) {
        guard !started else { return }
        started = true
        // A native modal regression must fail instead of leaving a test window open forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            fputs("FAIL native window test timed out\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            func check(_ value: Bool, _ message: String) {
                guard value else { print("FAIL tabs: \(message)"); exit(1) }
            }
            func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }
            @MainActor func fields(_ view: NSView) -> [NSTextField] {
                if let field = view as? NSTextField { return [field] }
                return view.subviews.flatMap(fields)
            }
            @MainActor func menuItem(_ menu: NSMenu, _ title: String) -> NSMenuItem? {
                for item in menu.items {
                    if item.title == title { return item }
                    if let submenu = item.submenu, let match = menuItem(submenu, title) { return match }
                }
                return nil
            }
            @MainActor func performMenu(_ title: String) {
                guard let menu = NSApp.mainMenu, let existing = menuItem(menu, title), let parent = existing.menu else {
                    print("FAIL menu missing: \(title)"); exit(1)
                }
                parent.delegate?.menuNeedsUpdate?(parent)
                parent.delegate?.menuWillOpen?(parent)
                parent.update()
                guard let item = menuItem(menu, title), let parent = item.menu, item.isEnabled else {
                    print("FAIL menu disabled: \(title)"); exit(1)
                }
                parent.performActionForItem(at: parent.index(of: item))
            }
            await settle()
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let host = window.contentView, let workspace = delegate.workspace else {
                print("FAIL initial workspace"); exit(1)
            }
            @MainActor func clickAlert(_ title: String) {
                func button(_ view: NSView) -> NSButton? {
                    if let button = view as? NSButton, button.title == title { return button }
                    return view.subviews.lazy.compactMap(button).first
                }
                guard let sheet = window.attachedSheet, let content = sheet.contentView,
                      let button = button(content) else {
                    print("FAIL missing close-dialog button: \(title)"); exit(1)
                }
                button.performClick(nil)
            }
            let compact = CommandLine.arguments.contains("--compact")
            let dark = CommandLine.arguments.contains("--dark")
            if dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
            window.setContentSize(compact ? CGSize(width: 860, height: 660) : CGSize(width: 1120, height: 800))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil); window.makeMain()
            let first = workspace.activeModel
            let data: Data
            if let index = CommandLine.arguments.firstIndex(of: "--image") {
                data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            } else {
                let context = try! ImageEngine.context(width: 40, height: 40)
                context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
                data = try! ImageEngine.encode(context.makeImage()!, format: .png, quality: 1)
            }
            @MainActor func waitForImports() async {
                let deadline = Date().addingTimeInterval(15)
                while workspace.tabs.contains(where: { $0.busyMessage != nil }) && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
                check(workspace.tabs.allSatisfy { $0.busyMessage == nil && $0.errorMessage == nil }, "image imports completed")
            }
            first.importData(data, name: "First")
            await waitForImports()
            await settle()
            first.setPosition(x: 123, y: 234)
            let originalFrame = first.document.frame
            first.requestImport([.data(data, name: "Second"), .data(data, name: "Third image with a longer name")], isPaste: true)
            await settle()
            check(first.pendingImport != nil, "destination choice is pending")
            first.resolveImport(.newImages)
            await waitForImports()
            await settle(); await settle()
            check(workspace.tabs.count == 3, "batch import creates three tabs (\(workspace.tabs.count))")
            check(NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.count == 1, "images share one window")
            check(first.document.layers.count == 1 && first.document.frame == originalFrame, "original canvas retained")
            let second = workspace.tabs[1]
            check(workspace.activeModel === second && second.document.layers.count == 1, "first imported tab selected")
            second.setPosition(x: 50, y: 50)
            performMenu("Center Layer")
            await settle()
            check(second.document.frame.midX == second.document.canvas.width / 2, "menu acts on active tab")
            check(first.document.frame == originalFrame, "menu leaves other tab unchanged")
            // Pending numeric values must commit before the editor view is swapped.
            guard let width = fields(host).first(where: { $0.placeholderString == "Width" }) else { exit(1) }
            window.makeFirstResponder(width)
            await settle()
            width.stringValue = "1000"
            width.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: width))
            await settle()
            workspace.select(first.id)
            await settle()
            check(second.document.canvas.width == 1000 && first.document.canvas.width == 1200, "switch commits only outgoing tab fields")
            check(delegate.model === first, "standard Paste routes to active tab")
            performMenu("Center Layer")
            await settle()
            check(first.document.frame.midX == 600, "menu follows selected tab")
            first.undo(); check(first.document.frame == originalFrame, "independent Undo")

            @MainActor func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = [], target: NSWindow? = nil) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: (target ?? window).windowNumber,
                                             context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                             isARepeat: false, keyCode: code)!
                NSApp.sendEvent(event)
            }
            // Shortcuts must follow selection even before the menu is opened again.
            workspace.select(second.id)
            second.setPosition(x: 40, y: 60)
            window.makeFirstResponder(nil)
            await settle()
            key(40, "k", flags: [.command])
            await settle()
            check(second.document.frame.midX == second.document.canvas.width / 2 && first.document.frame == originalFrame,
                  "keyboard shortcut resolves the active tab without opening menus")
            workspace.select(first.id)
            await settle()
            // Double-click the second tab through the real window event pipeline.
            @MainActor func findTabButton(_ view: NSView) -> ImageTabButton? {
                if let button = view as? ImageTabButton, button.attributedTitle.string == "Second" { return button }
                return view.subviews.lazy.compactMap(findTabButton).first
            }
            guard let tabButton = findTabButton(host) else { print("FAIL tab button missing"); exit(1) }
            let location = tabButton.convert(CGPoint(x: tabButton.bounds.midX, y: tabButton.bounds.midY), to: nil)
            for count in 1...2 {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil,
                                                   eventNumber: count, clickCount: count, pressure: 1)!
                    NSApp.sendEvent(event)
                }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            await settle()
            check(workspace.renamingID == second.id && workspace.activeModel === second, "double click selects and renames tab")
            guard let nameField = fields(host).first(where: { $0.placeholderString == "Image name" }) else {
                print("FAIL inline tab name field missing"); exit(1)
            }
            nameField.stringValue = "Product comparison"
            nameField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: nameField))
            await settle()
            key(36, "\r")
            await settle()
            check(second.document.filename == "Product comparison" && workspace.renamingID == nil, "Return commits tab rename")
            check(second.suggestedExportFilename == "Product comparison.png", "name feeds export suggestion")

            workspace.beginRenaming(second.id)
            await settle()
            guard let canceled = fields(host).first(where: { $0.placeholderString == "Image name" }) else { exit(1) }
            canceled.stringValue = "Discard me"
            canceled.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: canceled))
            await settle()
            key(53, "\u{1b}")
            await settle()
            check(second.document.filename == "Product comparison" && workspace.renamingID == nil, "Escape cancels rename")

            workspace.beginRenaming(second.id)
            await settle()
            guard let pending = fields(host).first(where: { $0.placeholderString == "Image name" }) else { exit(1) }
            pending.stringValue = "Hearing aid comparison"
            pending.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: pending))
            await settle()
            second.format = .jpeg
            second.exportImage()
            await settle(); await settle()
            guard let panel = NSApp.windows.compactMap({ $0 as? NSSavePanel }).first else {
                print("FAIL native export panel missing"); exit(1)
            }
            check(panel.nameFieldStringValue == "Hearing aid comparison.jpg", "export commits inline rename and suggests matching JPG filename")
            panel.cancel(nil)
            await settle()
            check(second.document.filename == "Hearing aid comparison", "export keeps tab name")
            second.format = compact ? .jpeg : .png
            // Standard close shortcut closes the tab, preserving the editor window.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil); window.makeMain()
            window.makeFirstResponder(nil)
            await settle()
            key(13, "w", flags: [.command])
            await settle()
            check(workspace.tabs.count == 3 && window.attachedSheet != nil, "Command-W protects an unexported tab")
            clickAlert("Cancel")
            await settle()
            check(workspace.tabs.count == 3 && second.hasUnexportedChanges, "Cancel retains the tab and dirty state")
            key(13, "w", flags: [.command])
            await settle()
            clickAlert("Don’t Export")
            await settle()
            check(workspace.tabs.count == 2 && window.isVisible, "Command-W closes the active tab, not the window (tabs=\(workspace.tabs.count), visible=\(window.isVisible))")
            performMenu("Reopen Closed Tab")
            await settle()
            check(workspace.activeModel === second && second.document.filename == "Hearing aid comparison", "reopen retains name and document (active=\(workspace.activeModel.document.filename), second=\(second.document.filename))")
            second.fitAndCenter()

            @MainActor func capture(_ flag: String) {
                guard let index = CommandLine.arguments.firstIndex(of: flag) else { return }
                let rect = host.safeAreaRect
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else { exit(1) }
                host.cacheDisplay(in: rect, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            await settle()
            capture("--capture")
            workspace.beginRenaming(second.id)
            await settle()
            capture("--capture-rename")
            workspace.renamingID = nil
            await settle()
            // Canceling the Save panel reached from Close must not close the tab.
            fputs("Checking canceled close export…\n", stderr)
            workspace.close(second.id)
            await settle()
            clickAlert("Export…")
            await settle(); await settle()
            guard let canceledExport = NSApp.windows.compactMap({ $0 as? NSSavePanel }).first(where: \.isVisible) else {
                print("FAIL close export panel missing"); exit(1)
            }
            check(second.isBusy && !workspace.close(second.id, discardingChanges: true), "saving blocks tab closure")
            canceledExport.cancel(nil)
            await settle()
            check(workspace.tabs.contains { $0 === second } && second.hasUnexportedChanges && !second.isBusy,
                  "canceled export leaves work open and unexported")

            // Supply a deterministic destination: macOS's remote Save panel does
            // not accept synthetic Save events. The file write and close callback
            // remain real; the native panel and its Cancel path were tested above.
            fputs("Checking successful close export…\n", stderr)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            second.format = .png
            let destination = directory.appendingPathComponent("exported.png")
            second.chooseExportDestination = { _, choose in choose(destination) }
            workspace.close(second.id)
            await settle()
            clickAlert("Export…")
            let saveDeadline = Date().addingTimeInterval(10)
            while workspace.tabs.contains(where: { $0 === second }) && Date() < saveDeadline { await settle() }
            second.chooseExportDestination = nil
            check(FileManager.default.fileExists(atPath: destination.path), "file was written")
            check(!workspace.tabs.contains { $0 === second } && !second.hasUnexportedChanges, "successful export closes a clean tab")
            workspace.reopenTab()
            check(workspace.activeModel === second && !second.hasUnexportedChanges, "reopening exported work stays clean")

            let deleted = workspace.newTab()
            deleted.importData(data, name: "Deleted image")
            await waitForImports()
            deleted.deleteLayer()
            workspace.close(deleted.id)
            await settle()
            check(window.attachedSheet != nil, "deleted last layer still protects Undo history")
            clickAlert("Cancel")
            await settle()
            check(window.attachedSheet == nil && workspace.activeModel === deleted,
                  "Cancel preserves history when no layer can be exported")
            workspace.close(deleted.id, discardingChanges: true)

            guard let coordinator = delegate.closeCoordinator else { print("FAIL missing close coordinator"); exit(1) }
            fputs("Checking multi-tab quit…\n", stderr)
            var quitReply: Bool?
            let terminate = coordinator.requestQuit { quitReply = $0 }
            check(terminate == .terminateLater, "quit waits for unsaved tabs")
            await settle()
            clickAlert("Don’t Export")
            await settle()
            clickAlert("Cancel")
            await settle()
            check(quitReply == false && workspace.tabs.count == 3 && first.hasUnexportedChanges,
                  "canceling a later quit dialog preserves every tab and earlier discard decisions are not persisted")

            // Exercise the actual red-close-button delegate path, then its Cancel.
            fputs("Checking native window close…\n", stderr)
            window.performClose(nil)
            await settle()
            check(window.attachedSheet != nil && window.isVisible, "window close is intercepted")
            clickAlert("Cancel")
            await settle()
            check(window.isVisible && !coordinator.isReviewing, "cancel keeps the window open")
            window.performClose(nil)
            for _ in workspace.tabs.filter(\.hasUnexportedChanges) {
                await settle()
                clickAlert("Don’t Export")
            }
            await settle()
            check(!window.isVisible, "confirmed window close completes")
            print("PASS one-window tabs, menu/paste routing, pending fields, actual double-click rename, Return/Escape, export filename, close/reopen and independent Undo")
            print("PASS native close/quit protection, Cancel, explicit discard, canceled export, successful file save and saved-state reopening")
            NSApp.terminate(nil)
        }
    }
}
