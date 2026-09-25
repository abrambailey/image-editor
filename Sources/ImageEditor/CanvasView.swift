import AppKit
import SwiftUI

struct CanvasView: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> EditorCanvas {
        let view = EditorCanvas()
        view.model = model
        return view
    }

    func updateNSView(_ view: EditorCanvas, context: Context) {
        view.model = model
        view.needsDisplay = true
        view.setAccessibilityHelp(model.isCropping
            ? "Crop selection. Drag to select, drag inside to move, or drag an edge to resize. Arrow keys move the selection. Return applies; Escape cancels. Exact crop dimensions are available in the inspector."
            : "Click a layer to select it; drag to move it. Drag a corner to resize. Arrow keys move one pixel; Shift and arrow move ten pixels.")
        view.window?.invalidateCursorRects(for: view)
    }
}

final class EditorCanvas: NSView, NSUserInterfaceValidations {
    var model: EditorModel?
    private var dragOrigin: CGPoint?
    private var originalFrame = CGRect.zero
    private var activeCorner: Int?
    private enum CropDrag { case select, move, resize(Int) }
    private var cropDrag: CropDrag?
    private var snapX = false
    private var snapY = false
    private var dropHighlighted = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff, .URL, .string])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Image canvas")
        setAccessibilityHelp("Click a layer to select it; drag to move it. Drag a corner to resize. Arrow keys move one pixel; Shift and arrow move ten pixels.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var displayScale: CGFloat {
        guard let model else { return 1 }
        return max(0.001, min((bounds.width - 96) / model.document.canvas.width,
                             (bounds.height - 100) / model.document.canvas.height)) * model.zoom
    }

    private var canvasRect: CGRect {
        guard let model else { return .zero }
        let size = CGSize(width: model.document.canvas.width * displayScale,
                          height: model.document.canvas.height * displayScale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func screenRect(_ frame: CGRect) -> CGRect {
        CGRect(x: canvasRect.minX + frame.minX * displayScale,
               y: canvasRect.minY + frame.minY * displayScale,
               width: frame.width * displayScale, height: frame.height * displayScale)
    }

    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private func cropHandles(_ rect: CGRect) -> [CGPoint] {
        corners(rect) + [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                         CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }

    private func canvasPoint(_ point: CGPoint) -> CGPoint {
        guard let model else { return .zero }
        return CGPoint(x: min(model.document.canvas.width, max(0, (point.x - canvasRect.minX) / displayScale)),
                       y: min(model.document.canvas.height, max(0, (point.y - canvasRect.minY) / displayScale)))
    }

    private func drawCrop(_ crop: CGRect) {
        let rect = screenRect(crop)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: canvasRect).addClip()
        let shade = NSBezierPath(rect: canvasRect)
        shade.append(NSBezierPath(rect: rect))
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        shade.fill()
        let grid = NSBezierPath()
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            grid.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            grid.line(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        NSColor.black.withAlphaComponent(0.35).setStroke()
        grid.lineWidth = 2; grid.stroke()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        grid.lineWidth = 0.5; grid.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(rect: rect)
        NSColor.black.withAlphaComponent(0.7).setStroke()
        outline.lineWidth = 3; outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1; outline.stroke()
        for point in cropHandles(rect) {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8),
                                      xRadius: 1.5, yRadius: 1.5)
            NSColor.white.setFill(); handle.fill()
            NSColor.controlAccentColor.setStroke(); handle.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard model.hasImage else {
            if dropHighlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
                bounds.fill()
            }
            return
        }
        let canvas = canvasRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowOffset = CGSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 14
        shadow.set()
        NSColor.white.setFill()
        canvas.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: canvas).addClip()
        if let background = model.document.background.color {
            NSColor(cgColor: background)?.setFill()
            canvas.fill()
        } else {
            NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
            canvas.fill()
            NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
            let cell: CGFloat = 10
            let visible = canvas.intersection(bounds)
            let firstColumn = max(0, Int((visible.minX - canvas.minX) / cell))
            let firstRow = max(0, Int((visible.minY - canvas.minY) / cell))
            let lastColumn = max(firstColumn, Int(ceil((visible.maxX - canvas.minX) / cell)))
            let lastRow = max(firstRow, Int(ceil((visible.maxY - canvas.minY) / cell)))
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn where (row + column).isMultiple(of: 2) {
                    CGRect(x: canvas.minX + CGFloat(column) * cell, y: canvas.minY + CGFloat(row) * cell,
                           width: cell, height: cell).fill()
                }
            }
        }
        for layer in model.document.layers where layer.isVisible {
            let cgImage = layer.image
            let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            image.draw(in: screenRect(layer.frame), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        if snapX || snapY {
            NSColor.systemPink.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            if snapX { path.move(to: CGPoint(x: canvas.midX, y: canvas.minY)); path.line(to: CGPoint(x: canvas.midX, y: canvas.maxY)) }
            if snapY { path.move(to: CGPoint(x: canvas.minX, y: canvas.midY)); path.line(to: CGPoint(x: canvas.maxX, y: canvas.midY)) }
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        if let crop = model.cropRect {
            drawCrop(crop)
        } else if model.canEditLayer {
            let frame = screenRect(model.document.frame)
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let outline = NSBezierPath(rect: frame)
            outline.lineWidth = 1
            outline.stroke()
            for corner in corners(frame) {
                let handle = NSBezierPath(roundedRect: CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8),
                                          xRadius: 1.5, yRadius: 1.5)
                NSColor.white.setFill(); handle.fill()
                NSColor.controlAccentColor.setStroke(); handle.stroke()
            }
        }
        let label = "\(Int(model.document.canvas.width)) × \(Int(model.document.canvas.height)) px"
        label.draw(at: CGPoint(x: canvas.minX, y: canvas.minY - 23), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        if dropHighlighted {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: 8, yRadius: 8)
            outline.lineWidth = 3; outline.stroke()
        }
    }

    override func resetCursorRects() {
        if let model, !model.isBusy, let crop = model.cropRect {
            addVisibleCursorRect(canvasRect, cursor: .crosshair)
            let rect = screenRect(crop)
            if crop != CGRect(origin: .zero, size: model.document.canvas) {
                addVisibleCursorRect(rect, cursor: .openHand)
            }
            for (index, point) in cropHandles(rect).enumerated() {
                let cursor: NSCursor = index == 4 || index == 6 ? .resizeUpDown
                    : index == 5 || index == 7 ? .resizeLeftRight : .crosshair
                addVisibleCursorRect(CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18), cursor: cursor)
            }
            return
        }
        guard let model, model.canEdit else { return }
        for layer in model.document.layers where layer.isVisible {
            addVisibleCursorRect(screenRect(layer.frame).intersection(canvasRect), cursor: .openHand)
        }
        guard model.canEditLayer else { return }
        let frame = screenRect(model.document.frame)
        for corner in corners(frame) {
            addVisibleCursorRect(CGRect(x: corner.x - 8, y: corner.y - 8, width: 16, height: 16), cursor: .crosshair)
        }
    }

    private func addVisibleCursorRect(_ rect: CGRect, cursor: NSCursor) {
        let visible = rect.intersection(bounds)
        // Zoom can put a crop handle or the entire subject outside the view.
        // CGRect.null has infinite coordinates, which AppKit rejects.
        guard !visible.isNull, !visible.isEmpty else { return }
        addCursorRect(visible, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let model, !model.isBusy, let crop = model.cropRect {
            let point = convert(event.locationInWindow, from: nil)
            let rect = screenRect(crop)
            if let handle = cropHandles(rect).firstIndex(where: { abs($0.x - point.x) <= 9 && abs($0.y - point.y) <= 9 }) {
                cropDrag = .resize(handle)
            } else if rect.contains(point), crop != CGRect(origin: .zero, size: model.document.canvas) {
                cropDrag = .move
                NSCursor.closedHand.set()
            } else if canvasRect.contains(point) {
                cropDrag = .select
            } else { return }
            dragOrigin = canvasPoint(point)
            originalFrame = crop
            return
        }
        guard let model, model.canEdit else { return }
        let point = convert(event.locationInWindow, from: nil)
        let frame = screenRect(model.document.frame)
        activeCorner = model.canEditLayer ? corners(frame).firstIndex { abs($0.x - point.x) <= 9 && abs($0.y - point.y) <= 9 } : nil
        if activeCorner == nil {
            guard canvasRect.contains(point),
                  let layer = model.document.layers.reversed().first(where: { ImageEngine.containsPixel(canvasPoint(point), in: $0) }) else { return }
            model.selectLayer(layer.id)
        }
        dragOrigin = point
        originalFrame = model.document.frame
        model.beginGesture()
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        if let model, let cropDrag, let start = dragOrigin {
            let point = canvasPoint(convert(event.locationInWindow, from: nil))
            var rect = originalFrame
            switch cropDrag {
            case .select:
                rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            case .move:
                rect = rect.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            case .resize(let handle):
                let dx = point.x - start.x, dy = point.y - start.y
                var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
                if [0, 3, 7].contains(handle) { left = min(right - 1, max(0, left + dx)) }
                if [1, 2, 5].contains(handle) { right = max(left + 1, min(model.document.canvas.width, right + dx)) }
                if [0, 1, 4].contains(handle) { top = min(bottom - 1, max(0, top + dy)) }
                if [2, 3, 6].contains(handle) { bottom = max(top + 1, min(model.document.canvas.height, bottom + dy)) }
                rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            }
            model.updateCrop(rect)
            return
        }
        guard let model, let start = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = (point.x - start.x) / displayScale
        let dy = (point.y - start.y) / displayScale
        var frame = originalFrame
        snapX = false; snapY = false
        if let corner = activeCorner {
            let anchor = corners(originalFrame)[(corner + 2) % 4]
            let moving = corners(originalFrame)[corner]
            let vx = moving.x - anchor.x, vy = moving.y - anchor.y
            let factor = max(1 / min(originalFrame.width, originalFrame.height),
                             ((vx + dx) * vx + (vy + dy) * vy) / (vx * vx + vy * vy))
            let newPoint = CGPoint(x: anchor.x + vx * factor, y: anchor.y + vy * factor)
            frame = CGRect(x: min(anchor.x, newPoint.x), y: min(anchor.y, newPoint.y),
                           width: abs(newPoint.x - anchor.x), height: abs(newPoint.y - anchor.y))
        } else {
            frame.origin.x += dx; frame.origin.y += dy
            if !event.modifierFlags.contains(.option) {
                if abs(frame.midX - model.document.canvas.width / 2) < 6 / displayScale {
                    frame.origin.x = (model.document.canvas.width - frame.width) / 2; snapX = true
                }
                if abs(frame.midY - model.document.canvas.height / 2) < 6 / displayScale {
                    frame.origin.y = (model.document.canvas.height - frame.height) / 2; snapY = true
                }
            }
        }
        model.updateFrame(frame)
    }

    override func mouseUp(with event: NSEvent) {
        if dragOrigin != nil && cropDrag == nil { model?.endGesture() }
        cropDrag = nil
        dragOrigin = nil; activeCorner = nil; snapX = false; snapY = false
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == [.command] || modifiers == [.command, .shift],
           let model, model.hasImage, model.aiEdit == nil {
            switch event.charactersIgnoringModifiers {
            case "+", "=": model.zoomIn(); return true
            case "-": model.zoomOut(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        if let model, let crop = model.cropRect {
            switch event.keyCode {
            case 36, 76: model.applyCrop()
            case 53: model.cancelCrop()
            case 123: model.updateCrop(crop.offsetBy(dx: -delta, dy: 0))
            case 124: model.updateCrop(crop.offsetBy(dx: delta, dy: 0))
            case 125: model.updateCrop(crop.offsetBy(dx: 0, dy: delta))
            case 126: model.updateCrop(crop.offsetBy(dx: 0, dy: -delta))
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 51, 117: model?.deleteLayer()
        case 123: model?.nudge(dx: -delta, dy: 0)
        case 124: model?.nudge(dx: delta, dy: 0)
        case 125: model?.nudge(dx: 0, dy: delta)
        case 126: model?.nudge(dx: 0, dy: -delta)
        default: super.keyDown(with: event)
        }
    }

    // Let the native Copy command follow focus: the canvas copies pixels,
    // while text fields keep their normal selected-text behavior.
    @objc func copy(_ sender: Any?) { model?.exportImage(copy: true) }
    @objc func paste(_ sender: Any?) { model?.paste() }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): return model?.canEdit == true
        case #selector(paste(_:)): return model?.canImport == true
        default: return true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model?.canImport == true else { return [] }
        dropHighlighted = true; needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHighlighted = false; needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlighted = false; needsDisplay = true
        return model?.importPasteboard(sender.draggingPasteboard, isDrop: true) ?? false
    }
}
