import AppKit
import SwiftUI

/// One native confirmation flow serves tab close, window close, and Command-Q.
@MainActor
final class EditorCloseCoordinator {
    private let workspace: EditorWorkspace
    private weak var window: NSWindow?
    private let windowDelegate = CloseWindowDelegate()
    private(set) var isReviewing = false
    private var approvedWindowClose = false

    init(workspace: EditorWorkspace, window: NSWindow) {
        self.workspace = workspace
        self.window = window
        // SwiftUI owns the original delegate. Forward all other callbacks to it.
        windowDelegate.original = window.delegate
        windowDelegate.coordinator = self
        window.delegate = windowDelegate
        workspace.confirmClose = { [weak self] model in self?.requestTabClose(model) }
    }

    private func prepareForClosing() -> Bool {
        guard !isReviewing, let window else { return false }
        workspace.activeModel.prepareForTabSwitch()
        if window.attachedSheet != nil { return false }
        if let busy = workspace.tabs.first(where: { $0.isBusy || $0.isCropping }) {
            workspace.select(busy.id)
            window.makeKeyAndOrderFront(nil)
            let alert = NSAlert()
            alert.messageText = "Finish the current edit first"
            alert.informativeText = busy.isCropping
                ? "Apply or cancel the crop before closing the window or quitting."
                : "Wait for the current operation, or finish or cancel the open dialog, before quitting."
            alert.addButton(withTitle: "Keep Editing")
            alert.beginSheetModal(for: window)
            return false
        }
        return true
    }

    private func requestTabClose(_ model: EditorModel) {
        guard !isReviewing, let window, window.attachedSheet == nil else { return }
        isReviewing = true
        workspace.select(model.id)
        confirm(model, action: "closing") { [weak self] confirmed in
            guard let self else { return }
            self.isReviewing = false
            if confirmed { self.workspace.close(model.id, discardingChanges: true) }
        }
    }

    func requestWindowClose() {
        guard prepareForClosing() else { return }
        reviewAll(action: "closing the window") { [weak self] confirmed in
            guard let self, confirmed else { return }
            self.approvedWindowClose = true
            self.window?.close()
        }
    }

    func requestQuit(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        if approvedWindowClose { return .terminateNow }
        guard prepareForClosing() else { return .terminateCancel }
        guard workspace.tabs.contains(where: \.hasUnexportedChanges) else { return .terminateNow }
        reviewAll(action: "quitting", completion: reply)
        return .terminateLater
    }

    private func reviewAll(action: String, completion: @escaping (Bool) -> Void) {
        isReviewing = true
        var approved: [UUID: ExportState] = [:]
        func next() {
            // Finder can deliver new images while a modal dialog is open. Never
            // quit using an obsolete list of tabs or an earlier discard decision.
            guard !workspace.tabs.contains(where: { $0.isBusy || $0.isCropping }) else {
                isReviewing = false
                completion(false)
                return
            }
            guard let model = workspace.tabs.first(where: {
                $0.hasUnexportedChanges && approved[$0.id] != $0.pendingExport.state
            }) else {
                isReviewing = false
                completion(true)
                return
            }
            let state = model.pendingExport.state
            workspace.select(model.id)
            confirm(model, action: action) { confirmed in
                if confirmed { approved[model.id] = state; next() }
                else { self.isReviewing = false; completion(false) }
            }
        }
        next()
    }

    private func confirm(_ model: EditorModel, action: String, completion: @escaping (Bool) -> Void) {
        guard let window else { completion(false); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        let filename = model.document.filename
        let name = filename.count > 80 ? String(filename.prefix(80)) + "…" : filename
        alert.messageText = "Export “\(name)” before \(action)?"
        alert.informativeText = "Changes that haven’t been exported will be lost. PNG and JPG exports combine visible layers and don’t save editable layers or Undo history."
        let canExport = model.canEdit
        if canExport { alert.addButton(withTitle: "Export…") }
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = canExport ? "\u{1b}" : "\r"
        let discard = alert.addButton(withTitle: "Don’t Export")
        discard.hasDestructiveAction = true
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = [.command]
        if !canExport {
            alert.messageText = "Discard the changes to “\(name)”?"
            alert.informativeText = "There are no layers to export. Cancel to recover the deleted image with Undo, or choose Don’t Export to discard this tab’s history."
        }
        alert.beginSheetModal(for: window) { response in
            if response == (canExport ? .alertThirdButtonReturn : .alertSecondButtonReturn) {
                completion(true)
            } else if canExport && response == .alertFirstButtonReturn {
                model.exportImage { saved in completion(saved && !model.hasUnexportedChanges) }
            } else { completion(false) }
        }
    }
}

@MainActor
private final class CloseWindowDelegate: NSObject, NSWindowDelegate {
    var original: (any NSWindowDelegate)?
    weak var coordinator: EditorCloseCoordinator?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        coordinator?.requestWindowClose()
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

struct CloseProtectionView: NSViewRepresentable {
    let workspace: EditorWorkspace
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.didFindWindow = { window in appDelegate.protectWindow(window, workspace: workspace) }
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {
        if let window = view.window { appDelegate.protectWindow(window, workspace: workspace) }
    }
}

final class WindowObserverView: NSView {
    var didFindWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { didFindWindow?(window) }
    }
}
