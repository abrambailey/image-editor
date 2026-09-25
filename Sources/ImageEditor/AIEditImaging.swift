import AppKit

struct EditStroke {
    /// Points are normalized to the source image, measured from its top-left.
    var points: [CGPoint]
    var diameter: CGFloat
}

struct AIEditGeometry {
    let sourceSize: CGSize
    let requestSize: CGSize
    let imageRect: CGRect
    var sizeParameter: String { "\(Int(requestSize.width))x\(Int(requestSize.height))" }

    init(width: Int, height: Int) {
        sourceSize = CGSize(width: width, height: height)
        // Pad unusually wide/tall canvases to the API's 3:1 limit. Never stretch.
        let paddedWidth = max(CGFloat(width), CGFloat(height) / 3)
        let paddedHeight = max(CGFloat(height), CGFloat(width) / 3)
        let scale = max(sqrt(655_360 / (paddedWidth * paddedHeight)),
                        min(1, 2048 / max(paddedWidth, paddedHeight)))
        var w = ceil(paddedWidth * scale / 16) * 16
        var h = ceil(paddedHeight * scale / 16) * 16
        w = max(w, ceil(h / 3 / 16) * 16)
        h = max(h, ceil(w / 3 / 16) * 16)
        requestSize = CGSize(width: w, height: h)
        let imageScale = min(w / CGFloat(width), h / CGFloat(height))
        let iw = max(1, floor(CGFloat(width) * imageScale))
        let ih = max(1, floor(CGFloat(height) * imageScale))
        imageRect = CGRect(x: floor((w - iw) / 2), y: floor((h - ih) / 2), width: iw, height: ih)
    }
}

enum AIEditImaging {
    static func drawStrokes(_ strokes: [EditStroke], in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            let diameter = stroke.diameter * min(rect.width, rect.height)
            let point = CGPoint(x: first.x * rect.width, y: first.y * rect.height)
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                              width: diameter, height: diameter))
            } else {
                context.setLineWidth(diameter)
                context.beginPath()
                context.move(to: point)
                for p in stroke.points.dropFirst() { context.addLine(to: CGPoint(x: p.x * rect.width, y: p.y * rect.height)) }
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    static func selection(size: CGSize, strokes: [EditStroke]) throws -> CGImage {
        let context = try ImageEngine.context(width: Int(size.width), height: Int(size.height))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        drawStrokes(strokes, in: context, rect: CGRect(origin: .zero, size: size))
        guard let image = context.makeImage() else { throw EditorError.message("Couldn’t draw the selection.") }
        return image
    }

    /// Inspect actual alpha, not just the PNG format or presence of an alpha channel.
    static func hasTransparency(_ image: CGImage) throws -> Bool {
        let context = try ImageEngine.context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw EditorError.message("Couldn’t read the image transparency.")
        }
        for i in stride(from: 3, to: image.width * image.height * 4, by: 4) {
            if pixels[i] < 255 { return true }
        }
        return false
    }

    static func prepare(_ source: CGImage, strokes: [EditStroke]) throws -> (image: Data, mask: Data?, geometry: AIEditGeometry, transparentBackground: Bool) {
        // Detect before aspect-ratio padding, which can add transparent pixels
        // even to an opaque photograph.
        let transparentBackground = try hasTransparency(source)
        let geometry = AIEditGeometry(width: source.width, height: source.height)
        let size = geometry.requestSize
        let context = try ImageEngine.context(width: Int(size.width), height: Int(size.height))
        context.interpolationQuality = .high
        let r = geometry.imageRect
        context.draw(source, in: CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height))
        guard let image = context.makeImage() else { throw EditorError.message("Couldn’t prepare the image.") }
        var maskData: Data?
        if !strokes.isEmpty {
            let mask = try ImageEngine.context(width: Int(size.width), height: Int(size.height))
            mask.setFillColor(CGColor(gray: 0, alpha: 1))
            mask.fill(CGRect(origin: .zero, size: size))
            mask.translateBy(x: 0, y: size.height)
            mask.scaleBy(x: 1, y: -1)
            mask.setBlendMode(.destinationOut)
            drawStrokes(strokes, in: mask, rect: geometry.imageRect)
            guard let maskImage = mask.makeImage() else { throw EditorError.message("Couldn’t prepare the selection.") }
            maskData = try ImageEngine.encode(maskImage, format: .png, quality: 1)
        }
        return (try ImageEngine.encode(image, format: .png, quality: 1), maskData, geometry, transparentBackground)
    }

    static func restoreSize(_ result: CGImage, geometry: AIEditGeometry) throws -> CGImage {
        guard result.width == Int(geometry.requestSize.width), result.height == Int(geometry.requestSize.height),
              let cropped = result.cropping(to: geometry.imageRect) else {
            throw EditorError.message("Sunburst returned different image dimensions. The result can’t be aligned safely; try generating again.")
        }
        let context = try ImageEngine.context(width: Int(geometry.sourceSize.width), height: Int(geometry.sourceSize.height))
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: geometry.sourceSize))
        guard let image = context.makeImage() else { throw EditorError.message("Couldn’t align the edited image.") }
        return image
    }

    /// Feather inward; pixels outside the painted selection are never replaced.
    static func blend(original: CGImage, edited: CGImage, strokes: [EditStroke], feather: CGFloat) throws -> CGImage {
        guard original.width == edited.width, original.height == edited.height, !strokes.isEmpty else {
            throw EditorError.message("Paint an edit area before blending a result.")
        }
        let size = CGSize(width: original.width, height: original.height)
        let mask = try selection(size: size, strokes: strokes)
        let output = try ImageEngine.context(width: original.width, height: original.height)
        let replacement = try ImageEngine.context(width: original.width, height: original.height)
        let hardMask = try ImageEngine.context(width: original.width, height: original.height)
        let rect = CGRect(origin: .zero, size: size)
        output.draw(original, in: rect)
        replacement.draw(edited, in: rect)
        hardMask.draw(mask, in: rect)
        guard let o = output.data?.assumingMemoryBound(to: UInt8.self),
              let e = replacement.data?.assumingMemoryBound(to: UInt8.self),
              let h = hardMask.data?.assumingMemoryBound(to: UInt8.self) else {
            throw EditorError.message("Couldn’t read the edit pixels.")
        }
        let width = original.width, height = original.height
        // Two-pass distance transform: a soft transition entirely inside the
        // selection, without GPU availability or unbounded Gaussian tails.
        var distance: [Float] = []
        if feather > 0 {
            distance = (0..<(width * height)).map { h[$0 * 4 + 3] == 0 ? 0 : Float(1_000_000) }
            let diagonal: Float = 1.414214
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    if x > 0 { distance[i] = min(distance[i], distance[i - 1] + 1) }
                    if y > 0 {
                        distance[i] = min(distance[i], distance[i - width] + 1)
                        if x > 0 { distance[i] = min(distance[i], distance[i - width - 1] + diagonal) }
                        if x + 1 < width { distance[i] = min(distance[i], distance[i - width + 1] + diagonal) }
                    }
                }
            }
            for y in (0..<height).reversed() {
                for x in (0..<width).reversed() {
                    let i = y * width + x
                    if x + 1 < width { distance[i] = min(distance[i], distance[i + 1] + 1) }
                    if y + 1 < height {
                        distance[i] = min(distance[i], distance[i + width] + 1)
                        if x > 0 { distance[i] = min(distance[i], distance[i + width - 1] + diagonal) }
                        if x + 1 < width { distance[i] = min(distance[i], distance[i + width + 1] + diagonal) }
                    }
                }
            }
        }
        for pixel in 0..<(width * height) {
            let i = pixel * 4
            let coverage = Int(h[i + 3])
            guard coverage > 0 else { continue }
            let t = feather > 0 ? min(1, Double(distance[pixel]) / Double(feather)) : 1
            let alpha = Int((Double(coverage) * t * t * (3 - 2 * t)).rounded())
            for c in 0..<4 { o[i + c] = UInt8((Int(e[i + c]) * alpha + Int(o[i + c]) * (255 - alpha) + 127) / 255) }
        }
        guard let result = output.makeImage() else { throw EditorError.message("Couldn’t merge the edit.") }
        return result
    }
}
