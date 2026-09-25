import AppKit
import SwiftUI

enum AIEditPreview: String, CaseIterable, Identifiable {
    case original = "Original", generated = "Sunburst", blended = "Blended"
    var id: String { rawValue }
}

@MainActor
final class AIEditSession: ObservableObject {
    let original: CGImage
    @Published var prompt = ""
    @Published var apiKey = ""
    @Published var connectionExpanded = false
    @Published var brushEnabled = false
    @Published var brushSize = 0.1
    @Published var feather = 12.0
    @Published var preview = AIEditPreview.original
    @Published private(set) var strokes: [EditStroke] = []
    @Published private(set) var result: CGImage?
    @Published private(set) var blended: CGImage?
    @Published private(set) var isWorking = false
    @Published private(set) var isBlending = false
    @Published var error: String?
    @Published var message = "Describe a change, or paint an area to guide the edit."
    private let client: any AIImageEditing
    private var requestTask: Task<Void, Never>?
    private var blendTask: Task<Void, Never>?
    private var requestID = UUID()
    private var blendID = UUID()

    init(original: CGImage, client: any AIImageEditing = SunburstClient(), loadCredential: Bool = true) {
        self.original = original
        self.client = client
        if loadCredential {
            apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? OpenAIKeyStore.load() ?? ""
        }
        connectionExpanded = apiKey.isEmpty
    }

    var hasSelection: Bool { !strokes.isEmpty }
    var canGenerate: Bool {
        !isWorking && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var displayedImage: CGImage {
        switch preview {
        case .original: return original
        case .generated: return result ?? original
        case .blended: return blended ?? result ?? original
        }
    }
    var applicableImage: CGImage? {
        guard !isWorking, !isBlending, preview != .original else { return nil }
        return preview == .blended ? blended : result
    }

    func addStroke(_ stroke: EditStroke) {
        guard !isWorking, result == nil, !stroke.points.isEmpty else { return }
        strokes.append(stroke)
    }
    func undoStroke() { if !isWorking && result == nil && !strokes.isEmpty { strokes.removeLast() } }
    func clearSelection() { if !isWorking && result == nil { strokes.removeAll() } }
    func reviseSelection() {
        guard !isWorking else { return }
        blendTask?.cancel(); blendID = UUID(); isBlending = false
        result = nil; blended = nil; preview = .original; brushEnabled = true
        message = "Adjust the selection, then generate a new edit from the original."
    }

    func generate() {
        guard canGenerate else { return }
        error = nil; isWorking = true; brushEnabled = false
        message = "Editing with Sunburst… This can take a few minutes."
        let id = UUID(); requestID = id
        let source = original, selection = strokes, instruction = prompt, key = apiKey, service = client
        requestTask = Task {
            do {
                let input = try await Task.detached(priority: .userInitiated) {
                    try AIEditImaging.prepare(source, strokes: selection)
                }.value
                try Task.checkCancellation()
                let data = try await service.edit(image: input.image, mask: input.mask, prompt: instruction,
                                                  size: input.geometry.sizeParameter,
                                                  transparentBackground: input.transparentBackground, apiKey: key)
                try Task.checkCancellation()
                let image = try await Task.detached(priority: .userInitiated) {
                    try AIEditImaging.restoreSize(ImageEngine.decode(data), geometry: input.geometry)
                }.value
                try Task.checkCancellation()
                guard requestID == id else { return }
                result = image; blended = nil; preview = .generated
                message = "Compare the result with the original before applying."
                isWorking = false
                if hasSelection { refreshBlend() }
            } catch {
                guard requestID == id else { return }
                isWorking = false
                if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                    self.error = error.localizedDescription
                    message = "The edit wasn’t applied. You can try again."
                }
            }
        }
    }

    func cancelRequest() {
        requestID = UUID(); requestTask?.cancel(); requestTask = nil; isWorking = false
        message = "Stopped waiting. OpenAI may still finish and charge for the request."
    }

    func close() { cancelRequest(); blendTask?.cancel(); blendID = UUID() }

    func refreshBlend() {
        guard let edited = result, hasSelection else { return }
        blendTask?.cancel()
        let id = UUID(); blendID = id; isBlending = true
        let source = original, selection = strokes, radius = feather
        blendTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                let image = try await Task.detached(priority: .userInitiated) {
                    try AIEditImaging.blend(original: source, edited: edited, strokes: selection, feather: radius)
                }.value
                try Task.checkCancellation()
                guard id == blendID else { return }
                blended = image; isBlending = false
            } catch {
                guard id == blendID else { return }
                isBlending = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
}
