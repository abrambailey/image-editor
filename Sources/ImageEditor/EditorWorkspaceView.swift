import AppKit
import SwiftUI

struct EditorWorkspaceView: View {
    @ObservedObject var workspace: EditorWorkspace
    private let tabBarHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(workspace.tabs) { model in
                                ImageTab(workspace: workspace, model: model)
                                    .id(model.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: workspace.selectedID) { _, id in proxy.scrollTo(id) }
                }
                Divider().padding(.vertical, 8)
                Button { workspace.newTab() } label: {
                    Image(systemName: "plus").frame(width: 34, height: tabBarHeight)
                }.buttonStyle(.plain).help("New image tab (⌘N)").accessibilityLabel("New image tab")
                Menu {
                    ForEach(workspace.tabs) { model in
                        TabMenuItem(workspace: workspace, model: model)
                    }
                } label: {
                    Image(systemName: "chevron.down").frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.trailing, 8).help("Show all image tabs").accessibilityLabel("Show all image tabs")
            }
            .frame(height: tabBarHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            EditorView(model: workspace.activeModel, minimumHeight: 660 - tabBarHeight - 1)
                .id(workspace.selectedID)
        }
        .frame(minWidth: 860, minHeight: 660)
    }
}

private struct TabMenuItem: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var model: EditorModel
    var body: some View {
        Button { workspace.select(model.id) } label: {
            if workspace.selectedID == model.id { Label(model.document.filename, systemImage: "checkmark") }
            else { Text(model.document.filename) }
        }
    }
}

private struct ImageTab: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var model: EditorModel
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool
    private var selected: Bool { workspace.selectedID == model.id }
    private var renaming: Bool { workspace.renamingID == model.id }

    var body: some View {
        HStack(spacing: 6) {
            if model.busyMessage != nil { ProgressView().controlSize(.mini).frame(width: 14) }
            if model.hasUnexportedChanges {
                Image(systemName: "circle.fill").font(.system(size: 6))
                    .foregroundStyle(.secondary).help("Changes not exported")
                    .accessibilityLabel("Changes not exported")
            }
            if renaming {
                TextField("Image name", text: $draftName)
                    .textFieldStyle(.roundedBorder).focused($renameFocused)
                    .onAppear { draftName = model.document.filename; renameFocused = true }
                    .onSubmit(commitName)
                    .onExitCommand { workspace.renamingID = nil }
                    .onChange(of: renameFocused) { _, focused in if !focused { commitName() } }
                    .accessibilityLabel("Image tab name")
            } else {
                TabTitleButton(name: model.document.filename, selected: selected,
                               select: { workspace.select(model.id) },
                               rename: { workspace.beginRenaming(model.id) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { workspace.close(model.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 22, height: 28)
            }.buttonStyle(.plain).disabled(model.isBusy || model.isCropping)
                .help("Close tab (⌘W)").accessibilityLabel("Close \(model.document.filename)")
        }
        .font(.system(size: 12))
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(width: 200, height: 36)
        .background(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if selected { Color.accentColor.frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Divider().padding(.vertical, 8) }
        .contextMenu {
            Button("Rename Tab…") { workspace.beginRenaming(model.id) }.disabled(model.isBusy)
            Button("Close Tab") { workspace.close(model.id) }.disabled(model.isBusy || model.isCropping)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitImageEditorFields)) { notification in
            if notification.object as? EditorModel === model { commitName() }
        }
    }

    private func commitName() {
        guard renaming else { return }
        model.renameDocument(draftName)
        workspace.renamingID = nil
    }
}

/// Native click counts keep double-click rename reliable when selection redraws the tab.
private struct TabTitleButton: NSViewRepresentable {
    let name: String
    let selected: Bool
    let select: () -> Void
    let rename: () -> Void

    func makeNSView(context: Context) -> ImageTabButton { ImageTabButton() }
    func updateNSView(_ button: ImageTabButton, context: Context) {
        button.attributedTitle = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
            .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor
        ])
        button.selectTab = select
        button.renameTab = rename
        button.setAccessibilityLabel("Image tab: \(name)")
        button.setAccessibilityValue(selected ? "Selected" : "")
        button.toolTip = "\(name) — Double-click to rename"
    }
}

final class ImageTabButton: NSButton {
    var selectTab: (() -> Void)?
    var renameTab: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isBordered = false
        alignment = .left
        lineBreakMode = .byTruncatingMiddle
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(selectAction)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { renameTab?() }
        else { selectTab?() }
    }
    @objc private func selectAction() { selectTab?() }
}
