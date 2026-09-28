import AppKit
import SwiftUI

// Extends the native light table: the image leads, controls stay in its inspector.
// Full output is the default; local blending is an explicit, reversible comparison.
struct AIEditView: View {
    @ObservedObject var session: AIEditSession
    let apply: () -> Void
    let close: () -> Void
    @FocusState private var promptFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(session.result == nil ? "Edit with Sunburst" : "Review the edit").font(.headline)
                    Spacer()
                    if session.result != nil {
                        Picker("Preview", selection: $session.preview) {
                            Text("Original").tag(AIEditPreview.original)
                            Text("Sunburst").tag(AIEditPreview.generated)
                            if session.hasSelection { Text("Blended").tag(AIEditPreview.blended) }
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 265)
                    }
                }.padding(18)
                ZStack {
                    AIEditCanvas(session: session)
                    if session.isWorking {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Sunburst is editing…").font(.callout)
                            Text("Your original is safe.").font(.caption).foregroundStyle(.secondary)
                            Button("Stop Waiting", action: session.cancelRequest)
                        }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text(previewHint).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 18).padding(.vertical, 12)
                Text(session.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 18).padding(.bottom, 12)
            }.background(Color(nsColor: .windowBackgroundColor))
            Divider()
            controls.frame(width: 276)
        }
        .onAppear { promptFocused = true }
        .onChange(of: session.feather) { _, _ in session.refreshBlend() }
    }

    private var previewHint: String {
        if session.isWorking { return "You can stop waiting without changing the original." }
        if session.result == nil {
            if !session.hasLayers { return "Choose at least one layer in Layers to edit." }
            return session.brushEnabled ? "Paint the area to change. Include nearby shadows or reflections if needed." : "Only the selected layers shown here will be sent as the reference image."
        }
        switch session.preview {
        case .original: return "Original layers · Choose Sunburst or Blended to apply an edit."
        case .generated: return "Full Sunburst result · Check for changes elsewhere in the image."
        case .blended: return session.isBlending ? "Updating the blend…" : "Selected area blended into the original · Check the boundary for seams."
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    layerPicker
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What would you like to change?").font(.system(size: 13, weight: .semibold))
                        TextEditor(text: $session.prompt)
                            .font(.system(size: 13)).focused($promptFocused)
                            .frame(height: 104).padding(5)
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                            .accessibilityLabel("Edit instruction")
                        Text("For example, “Make the casing brushed silver and keep the lettering.”")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.disabled(session.isWorking || !session.hasLayers)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Edit area").font(.system(size: 13, weight: .semibold))
                        if session.result == nil {
                            Toggle("Paint a selection", isOn: $session.brushEnabled)
                                .toggleStyle(.checkbox)
                            Text("Optional. Without a selection, Sunburst uses your instruction to locate the change.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if session.brushEnabled {
                                HStack {
                                    Text("Brush").font(.system(size: 11))
                                    Slider(value: $session.brushSize, in: 0.01...0.4)
                                        .accessibilityLabel("Selection brush size")
                                    Text("\(Int(session.brushSize * 100))%").font(.system(size: 11)).monospacedDigit().frame(width: 30)
                                }
                            }
                            if session.hasSelection {
                                HStack {
                                    Button("Undo Stroke", action: session.undoStroke)
                                    Button("Clear", action: session.clearSelection)
                                }
                                Text("The painted selection will guide this request.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(session.hasSelection ? "Your selection guided the edit. Compare the full result with an optional local blend." : "Sunburst used your instruction to locate the edit. Inspect the whole result.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("Change Selection", action: session.reviseSelection)
                            if session.hasSelection {
                                Text("Blend edge softness").font(.system(size: 11))
                                HStack {
                                    Slider(value: $session.feather, in: 0...60, step: 1)
                                        .accessibilityLabel("Blend edge softness in pixels")
                                    Text("\(Int(session.feather)) px").font(.system(size: 11)).monospacedDigit().frame(width: 38)
                                }
                                Text("Blended keeps original pixels outside your selection. It may need a wider selection to look natural.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }.disabled(session.isWorking || !session.hasLayers)
                    Divider()
                    DisclosureGroup("Connection", isExpanded: $session.connectionExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            SecureField("OpenAI API key", text: $session.apiKey)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("OpenAI API key")
                            HStack {
                                Button("Save in Keychain") {
                                    do { try OpenAIKeyStore.save(session.apiKey); session.message = "API key saved in this Mac’s Keychain." }
                                    catch { session.error = error.localizedDescription }
                                }.disabled(session.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Forget") {
                                    do { try OpenAIKeyStore.delete(); session.apiKey = ""; session.message = "Saved API key removed." }
                                    catch { session.error = error.localizedDescription }
                                }
                            }
                            Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                .font(.system(size: 11))
                        }.padding(.top, 10)
                    }.font(.system(size: 12)).disabled(session.isWorking)
                    if let error = session.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                            .textSelection(.enabled).accessibilityLabel("Error: \(error)")
                    }
                }
                .frame(width: 240, alignment: .leading).padding(18)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Generate sends the selected layers and instruction to OpenAI. API usage is billed separately from ChatGPT.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if session.result == nil {
                    Button(action: session.generate) { Text("Generate Edit").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!session.canGenerate)
                } else {
                    Button("Generate Again", action: session.generate)
                        .frame(maxWidth: .infinity).disabled(!session.canGenerate)
                }
                Text("High quality · Generates up to 2,048 px")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if session.result != nil {
                    Button(action: apply) {
                        Text(session.preview == .blended ? "Use Blended Result" : "Use Sunburst Result").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(session.applicableImage == nil)
                    Text(session.selectedLayerIDs.count == 1 ? "Applies to one layer. Undo restores the previous image." : "Combines only the \(session.selectedLayerIDs.count) selected layers. Undo restores them.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button("Cancel", action: close).frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }.padding(18)
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Layers to edit").font(.system(size: 13, weight: .semibold))
            ForEach(session.layers.reversed()) { layer in
                Toggle(isOn: Binding(
                    get: { session.selectedLayerIDs.contains(layer.id) },
                    set: { session.setLayerIncluded(layer.id, included: $0) }
                )) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSImage(cgImage: layer.image, size: .zero))
                            .resizable().scaledToFit().frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text(layer.name).lineLimit(1).truncationMode(.middle)
                        if !layer.isVisible {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                .help("Hidden in the canvas. Selecting it includes it in this edit.")
                        }
                    }
                }
                .toggleStyle(.checkbox).font(.system(size: 12))
                .disabled(!session.canChooseLayers)
                .help(layer.name)
                .accessibilityLabel("Include \(layer.name)\(layer.isVisible ? "" : ", hidden layer")")
                .accessibilityIdentifier("ai-layer-\(layer.id)")
            }
            Text(session.layerSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help("When combining layers, the result takes the topmost selected layer’s position in the stack.")
            if session.result != nil {
                Button("Change Layers", action: session.reviseLayers).disabled(session.isWorking)
                    .help("Discard this preview and choose different layers.")
            }
        }
    }
}

struct AIEditCanvas: NSViewRepresentable {
    @ObservedObject var session: AIEditSession
    func makeNSView(context: Context) -> AIEditCanvasView { AIEditCanvasView(session: session) }
    func updateNSView(_ view: AIEditCanvasView, context: Context) {
        view.session = session
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class AIEditCanvasView: NSView {
    var session: AIEditSession
    private var activeStroke: EditStroke?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var imageRect: CGRect {
        let size = CGSize(width: session.original.width, height: session.original.height)
        let scale = max(0.001, min((bounds.width - 48) / size.width, (bounds.height - 32) / size.height))
        return CGRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2,
                      width: size.width * scale, height: size.height * scale)
    }
    private var canPaint: Bool { session.hasLayers && session.brushEnabled && !session.isWorking && session.result == nil }

    init(session: AIEditSession) {
        self.session = session
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("AI edit preview. Optional selection can be painted with the mouse; instructions also work without a selection.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() { if canPaint { addCursorRect(imageRect, cursor: .crosshair) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        for y in stride(from: rect.minY, to: rect.maxY, by: 10) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 10) {
                let even = (Int((x - rect.minX) / 10) + Int((y - rect.minY) / 10)) % 2 == 0
                NSColor(calibratedWhite: even ? 0.98 : 0.9, alpha: 1).setFill()
                CGRect(x: x, y: y, width: 10, height: 10).fill()
            }
        }
        NSImage(cgImage: session.displayedImage, size: .zero)
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if session.result == nil && !session.isWorking {
            for stroke in session.strokes + (activeStroke.map { [$0] } ?? []) { draw(stroke, in: rect) }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ stroke: EditStroke, in rect: CGRect) {
        guard let p = stroke.points.first else { return }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        let width = stroke.diameter * min(rect.width, rect.height)
        NSColor.controlAccentColor.withAlphaComponent(0.35).set()
        if stroke.points.count == 1 {
            let c = point(p)
            NSBezierPath(ovalIn: CGRect(x: c.x - width / 2, y: c.y - width / 2, width: width, height: width)).fill()
        } else {
            let path = NSBezierPath()
            path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: point(p))
            for p in stroke.points.dropFirst() { path.line(to: point(p)) }
            path.stroke()
        }
    }

    private func normalized(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        return CGPoint(x: min(1, max(0, (p.x - r.minX) / r.width)), y: min(1, max(0, (p.y - r.minY) / r.height)))
    }
    override func mouseDown(with event: NSEvent) {
        guard canPaint, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        activeStroke = EditStroke(points: [normalized(event)], diameter: session.brushSize)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard canPaint, activeStroke != nil else { return }
        activeStroke?.points.append(normalized(event)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if canPaint, let stroke = activeStroke { session.addStroke(stroke) }
        activeStroke = nil; needsDisplay = true
    }
}
