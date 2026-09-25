import SwiftUI

/// Independent documents share one editor window. Each model retains its own history.
@MainActor
final class EditorWorkspace: ObservableObject {
    @Published private(set) var tabs: [EditorModel]
    @Published private(set) var selectedID: UUID
    @Published var renamingID: UUID?
    var confirmClose: ((EditorModel) -> Void)?
    private var closedTabs: [EditorModel] = []

    init() {
        let first = EditorModel()
        tabs = [first]
        selectedID = first.id
        configure(first)
    }

    var activeModel: EditorModel { tabs.first { $0.id == selectedID } ?? tabs[0] }
    var canReopenTab: Bool { !closedTabs.isEmpty }

    private func configure(_ model: EditorModel) {
        model.openNewImages = { [weak self] items in self?.openImages(items) }
    }

    func select(_ id: UUID) {
        guard id != selectedID, tabs.contains(where: { $0.id == id }) else { return }
        activeModel.prepareForTabSwitch()
        renamingID = nil
        selectedID = id
    }

    @discardableResult
    func newTab() -> EditorModel {
        activeModel.prepareForTabSwitch()
        let model = EditorModel()
        configure(model)
        tabs.append(model)
        renamingID = nil
        selectedID = model.id
        return model
    }

    func openImages(_ items: [ImageImport]) {
        guard !items.isEmpty else { return }
        activeModel.prepareForTabSwitch()
        var imported: [EditorModel] = []
        for item in items {
            let model = EditorModel()
            configure(model)
            model.importImages([item])
            imported.append(model)
        }
        tabs.append(contentsOf: imported)
        renamingID = nil
        selectedID = imported[0].id
    }

    func beginRenaming(_ id: UUID) {
        guard let model = tabs.first(where: { $0.id == id }), !model.isBusy else { return }
        select(id)
        model.prepareForTabSwitch()
        renamingID = id
    }

    @discardableResult
    func close(_ id: UUID, discardingChanges: Bool = false) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isBusy, !tabs[index].isCropping else { return false }
        tabs[index].prepareForTabSwitch()
        if tabs[index].hasUnexportedChanges && !discardingChanges {
            confirmClose?(tabs[index])
            return false
        }
        var remaining = tabs
        let removed = remaining.remove(at: index)
        // Any unexported changes were explicitly discarded before entering this
        // bounded cache, so eviction never silently loses unacknowledged work.
        closedTabs.append(removed)
        if closedTabs.count > 5 { closedTabs.removeFirst() }
        if remaining.isEmpty {
            let model = EditorModel()
            configure(model)
            remaining = [model]
        }
        tabs = remaining
        if selectedID == id { selectedID = remaining[min(index, remaining.count - 1)].id }
        if renamingID == id { renamingID = nil }
        return true
    }

    func reopenTab() {
        guard let model = closedTabs.popLast() else { return }
        activeModel.prepareForTabSwitch()
        tabs.append(model)
        renamingID = nil
        selectedID = model.id
    }

    func selectAdjacentTab(_ offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        select(tabs[(index + offset + tabs.count) % tabs.count].id)
    }
}
