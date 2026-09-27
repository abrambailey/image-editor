import AppKit
import ImageIO
import UniformTypeIdentifiers

enum EditorError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPG"
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
}

enum CanvasBackground: String, CaseIterable, Identifiable {
    case transparent = "Transparent", white = "White", black = "Black"
    var id: String { rawValue }
    var color: CGColor? {
        switch self {
        case .transparent: return nil
        case .white: return CGColor(gray: 1, alpha: 1)
        case .black: return CGColor(gray: 0, alpha: 1)
        }
    }
}

enum PixelSelectionShape: String, CaseIterable {
    case rectangle = "Rectangle", ellipse = "Ellipse"
}

struct PixelSelection {
    var rect: CGRect // Canvas pixels, top-left origin.
    var shape: PixelSelectionShape
}

enum LayerExpansionUnit: String, CaseIterable {
    case pixels = "Pixels", percent = "Percent"
    var suffix: String { self == .pixels ? "px" : "%" }
}

struct LayerExpansion {
    var unit: LayerExpansionUnit = .pixels
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0
    var left: Double = 0

    struct Insets: Equatable {
        let top: Int, right: Int, bottom: Int, left: Int
        var isEmpty: Bool { top == 0 && right == 0 && bottom == 0 && left == 0 }
        func expandedSize(_ size: CGSize) -> CGSize {
            CGSize(width: size.width + CGFloat(left + right), height: size.height + CGFloat(top + bottom))
        }
    }

    /// Percentages apply to each edge: left/right use width, top/bottom use height.
    func pixelInsets(for size: CGSize) throws -> Insets {
        func pixels(_ amount: Double, dimension: CGFloat) throws -> Int {
            guard amount.isFinite, amount >= 0 else {
                throw EditorError.message("Enter a number of 0 or more for each side.")
            }
            let value = (unit == .pixels ? amount : amount / 100 * dimension).rounded()
            guard value.isFinite, value <= Double(ImageEngine.maxDimension) else {
                throw EditorError.message("The expanded layer must be no larger than 8,192 × 8,192 px. Reduce the amounts.")
            }
            return Int(value)
        }
        let insets = try Insets(top: pixels(top, dimension: size.height), right: pixels(right, dimension: size.width),
                                bottom: pixels(bottom, dimension: size.height), left: pixels(left, dimension: size.width))
        let expanded = insets.expandedSize(size)
        guard expanded.width >= 1, expanded.height >= 1,
              expanded.width <= CGFloat(ImageEngine.maxDimension), expanded.height <= CGFloat(ImageEngine.maxDimension) else {
            throw EditorError.message("The expanded layer must be no larger than 8,192 × 8,192 px. Reduce the amounts.")
        }
        return insets
    }
}

enum ImageEngine {
    static let maxDimension = 8192
    static let maxDownloadBytes = 50 * 1024 * 1024
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Normalize EXIF orientation, and limit decoded memory before reading pixels.
    static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= maxDownloadBytes else {
            throw EditorError.message("This image is larger than 50 MB. Open a smaller copy.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw EditorError.message("This file isn’t a supported image. Try PNG, JPEG, WebP, HEIC, or TIFF.")
        }
        return image
    }

    static func context(width: Int, height: Int) throws -> CGContext {
        guard (1...maxDimension).contains(width), (1...maxDimension).contains(height),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                        CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw EditorError.message("Couldn’t allocate this canvas. Use dimensions from 1 to 8,192 pixels.")
        }
        return context
    }

    /// Pixel bounds use image coordinates: the origin is the top-left pixel.
    static func contentBounds(of image: CGImage, minimumAlpha: UInt8 = 8) throws -> CGRect {
        let context = try context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw EditorError.message("Couldn’t read the image pixels.")
        }
        var left = image.width, top = image.height, right = -1, bottom = -1
        for y in 0..<image.height {
            for x in 0..<image.width where data[y * context.bytesPerRow + x * 4 + 3] > minimumAlpha {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else {
            throw EditorError.message("The image is completely transparent. Try a different image or restore the original.")
        }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    static func trimmed(_ image: CGImage) throws -> (image: CGImage, bounds: CGRect) {
        let bounds = try contentBounds(of: image)
        guard let cropped = image.cropping(to: bounds) else {
            throw EditorError.message("Couldn’t trim the transparent edges.")
        }
        return (cropped, bounds)
    }

    static func fittedFrame(imageSize: CGSize, canvas: CGSize, padding: CGFloat) -> CGRect {
        let inset = max(0, min(padding, (min(canvas.width, canvas.height) - 1) / 2))
        let scale = min((canvas.width - 2 * inset) / imageSize.width,
                        (canvas.height - 2 * inset) / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func imageRect(_ rect: CGRect, in layer: ImageLayer) -> CGRect {
        CGRect(x: (rect.minX - layer.frame.minX) * CGFloat(layer.image.width) / layer.frame.width,
               y: (rect.minY - layer.frame.minY) * CGFloat(layer.image.height) / layer.frame.height,
               width: rect.width * CGFloat(layer.image.width) / layer.frame.width,
               height: rect.height * CGFloat(layer.image.height) / layer.frame.height)
    }

    static func canvasRect(_ rect: CGRect, in layer: ImageLayer) -> CGRect {
        CGRect(x: layer.frame.minX + rect.minX * layer.frame.width / CGFloat(layer.image.width),
               y: layer.frame.minY + rect.minY * layer.frame.height / CGFloat(layer.image.height),
               width: rect.width * layer.frame.width / CGFloat(layer.image.width),
               height: rect.height * layer.frame.height / CGFloat(layer.image.height))
    }

    /// Include every touched source pixel, without floating-point roundoff adding an edge.
    static func pixelBounds(_ rect: CGRect, in image: CGImage) -> CGRect {
        let left = floor(rect.minX + 0.000001), top = floor(rect.minY + 0.000001)
        let right = ceil(rect.maxX - 0.000001), bottom = ceil(rect.maxY - 0.000001)
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// Copy only this layer at source resolution, retaining transparent ellipse corners.
    static func copySelection(_ selection: PixelSelection, from layer: ImageLayer) throws -> (image: CGImage, frame: CGRect) {
        let local = imageRect(selection.rect, in: layer)
        let pixels = pixelBounds(local, in: layer.image)
        guard !pixels.isNull, !pixels.isEmpty, let cropped = layer.image.cropping(to: pixels) else {
            throw EditorError.message("The selection doesn’t overlap this layer. Draw over the selected layer.")
        }
        if selection.shape == .rectangle { return (cropped, canvasRect(pixels, in: layer)) }
        let context = try context(width: cropped.width, height: cropped.height)
        let shape = local.offsetBy(dx: -pixels.minX, dy: -pixels.minY)
        // Quartz draws bottom-up, while the selection is measured from the top-left.
        context.addEllipse(in: CGRect(x: shape.minX, y: pixels.height - shape.maxY, width: shape.width, height: shape.height))
        context.clip()
        context.draw(cropped, in: CGRect(origin: .zero, size: pixels.size))
        guard let image = context.makeImage() else { throw EditorError.message("Couldn’t copy the selection.") }
        return (image, canvasRect(pixels, in: layer))
    }

    static func deletingSelection(_ selection: PixelSelection, from layer: ImageLayer) throws -> CGImage {
        let local = imageRect(selection.rect, in: layer)
        let pixels = pixelBounds(local, in: layer.image)
        guard !pixels.isNull, !pixels.isEmpty else {
            throw EditorError.message("The selection doesn’t overlap this layer. Draw over the selected layer.")
        }
        let context = try context(width: layer.image.width, height: layer.image.height)
        context.draw(layer.image, in: CGRect(x: 0, y: 0, width: layer.image.width, height: layer.image.height))
        let shape = selection.shape == .rectangle ? pixels : local
        let quartz = CGRect(x: shape.minX, y: CGFloat(layer.image.height) - shape.maxY, width: shape.width, height: shape.height)
        context.setBlendMode(.destinationOut)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        if selection.shape == .ellipse { context.fillEllipse(in: quartz) }
        else { context.fill(quartz) }
        guard let image = context.makeImage() else { throw EditorError.message("Couldn’t delete the selection.") }
        return image
    }

    static func expanded(_ image: CGImage, by expansion: LayerExpansion, fill: CGColor?) throws -> CGImage {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let insets = try expansion.pixelInsets(for: sourceSize)
        guard !insets.isEmpty else { return image }
        let size = insets.expandedSize(sourceSize)
        let context = try context(width: Int(size.width), height: Int(size.height))
        let sourceRect = CGRect(x: CGFloat(insets.left), y: CGFloat(insets.bottom), width: sourceSize.width, height: sourceSize.height)
        if let fill {
            // Only the new border is filled; transparency inside the source stays intact.
            context.setFillColor(fill)
            context.addRect(CGRect(origin: .zero, size: size))
            context.addRect(sourceRect)
            context.drawPath(using: .eoFill)
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: sourceRect)
        guard let result = context.makeImage() else { throw EditorError.message("Couldn’t expand the layer. Try smaller amounts.") }
        return result
    }

    static func removeBackground(from image: CGImage) throws -> CGImage {
        try ForegroundExtractor.shared.removeBackground(from: image)
    }

    /// Remove only near-white regions connected to transparency or the outer edge.
    /// Deliberately optional: white product details can be connected to the backdrop.
    static func cleanWhiteEdges(_ image: CGImage) throws -> CGImage {
        let context = try context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let width = image.width, height = image.height
        var visited = [Bool](repeating: false, count: width * height)
        var queue = [Int32]()
        queue.reserveCapacity(width * height / 4)
        func eligible(_ index: Int) -> Bool {
            let offset = index * 4
            let alpha = Int(pixels[offset + 3])
            if alpha <= 8 { return true }
            let darkest = min(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
            return darkest * 255 >= 242 * alpha
        }
        func enqueue(_ index: Int) {
            guard !visited[index], eligible(index) else { return }
            visited[index] = true
            queue.append(Int32(index))
        }
        for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
        for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }
        // Transparent holes also touch a background boundary (e.g. inside a wire loop).
        for index in 0..<(width * height) where pixels[index * 4 + 3] <= 8 {
            if index % width > 0 { enqueue(index - 1) }
            if index % width < width - 1 { enqueue(index + 1) }
            if index >= width { enqueue(index - width) }
            if index < width * (height - 1) { enqueue(index + width) }
        }
        var head = 0
        while head < queue.count {
            let index = Int(queue[head]); head += 1
            if index % width > 0 { enqueue(index - 1) }
            if index % width < width - 1 { enqueue(index + 1) }
            if index >= width { enqueue(index - width) }
            if index < width * (height - 1) { enqueue(index + width) }
        }
        for index in queue {
            let offset = Int(index) * 4
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let darkest = min(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2])) * 255 / alpha
            let retained = min(1, max(0, Double(250 - darkest) / 8))
            for channel in 0..<4 { pixels[offset + channel] = UInt8(Double(pixels[offset + channel]) * retained) }
        }
        guard let result = context.makeImage() else { throw EditorError.message("Couldn’t clean the edges.") }
        return result
    }

    /// Render at requested pixel dimensions, independent of Retina / preview zoom.
    static func render(image: CGImage, frame: CGRect, canvas: CGSize,
                       background: CanvasBackground, format: ExportFormat) throws -> CGImage {
        try render(images: [(image, frame)], canvas: canvas, background: background, format: format)
    }

    static func render(layers: [ImageLayer], canvas: CGSize,
                       background: CanvasBackground, format: ExportFormat) throws -> CGImage {
        try render(images: layers.filter(\.isVisible).map { ($0.image, $0.frame) },
                   canvas: canvas, background: background, format: format)
    }

    private static func render(images: [(CGImage, CGRect)], canvas: CGSize,
                               background: CanvasBackground, format: ExportFormat) throws -> CGImage {
        let context = try context(width: Int(canvas.width), height: Int(canvas.height))
        if let color = background.color ?? (format == .jpeg ? CGColor(gray: 1, alpha: 1) : nil) {
            context.setFillColor(color)
            context.fill(CGRect(origin: .zero, size: canvas))
        }
        context.interpolationQuality = .high
        for (image, frame) in images {
            // Convert editor coordinates (top-left) to Quartz drawing coordinates.
            let destination = CGRect(x: frame.minX, y: canvas.height - frame.maxY,
                                     width: frame.width, height: frame.height)
            context.draw(image, in: destination)
        }
        guard let output = context.makeImage() else { throw EditorError.message("Couldn’t render the canvas.") }
        return output
    }

    static func renderExport(image: CGImage, frame: CGRect, canvas: CGSize,
                             background: CanvasBackground, format: ExportFormat,
                             includeCanvasPadding: Bool) throws -> CGImage {
        try renderExport(images: [(image, frame)], canvas: canvas, background: background,
                         format: format, includeCanvasPadding: includeCanvasPadding)
    }

    static func renderExport(layers: [ImageLayer], canvas: CGSize,
                             background: CanvasBackground, format: ExportFormat,
                             includeCanvasPadding: Bool) throws -> CGImage {
        try renderExport(images: layers.filter(\.isVisible).map { ($0.image, $0.frame) },
                         canvas: canvas, background: background,
                         format: format, includeCanvasPadding: includeCanvasPadding)
    }

    /// Trim the composite before adding a matte, preserving white pixels and faint alpha.
    private static func renderExport(images: [(CGImage, CGRect)], canvas: CGSize,
                                     background: CanvasBackground, format: ExportFormat,
                                     includeCanvasPadding: Bool) throws -> CGImage {
        if includeCanvasPadding {
            return try render(images: images, canvas: canvas, background: background, format: format)
        }
        let canvasRect = CGRect(origin: .zero, size: canvas)
        let visibleFrame = images.reduce(CGRect.null) { $0.union($1.1.intersection(canvasRect)) }
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            throw EditorError.message("All layers are hidden or outside the canvas. Show a layer and move it onto the canvas, or use Fit & Center before exporting.")
        }
        let bounds = visibleFrame.integral
        let foreground = try render(images: images.map { ($0.0, $0.1.offsetBy(dx: -bounds.minX, dy: -bounds.minY)) },
                                    canvas: bounds.size, background: .transparent, format: .png)
        let content = try contentBounds(of: foreground, minimumAlpha: 0)
        guard let cropped = foreground.cropping(to: content) else {
            throw EditorError.message("Couldn’t crop the export to the image.")
        }
        if background == .transparent && format == .png { return cropped }
        let size = CGSize(width: cropped.width, height: cropped.height)
        return try render(image: cropped, frame: CGRect(origin: .zero, size: size), canvas: size,
                          background: background, format: format)
    }

    /// Hit testing respects transparent holes so covered layers remain reachable.
    static func containsPixel(_ point: CGPoint, in layer: ImageLayer) -> Bool {
        guard layer.isVisible, layer.frame.contains(point) else { return false }
        let x = floor((point.x - layer.frame.minX) / layer.frame.width * CGFloat(layer.image.width))
        let y = floor((point.y - layer.frame.minY) / layer.frame.height * CGFloat(layer.image.height))
        guard let pixel = layer.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = try? context(width: 1, height: 1), let data = context.data else { return false }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return data.assumingMemoryBound(to: UInt8.self)[3] > 0
    }

    static func encode(_ image: CGImage, format: ExportFormat, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else {
            throw EditorError.message("Couldn’t create the export.")
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg { options[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality)) }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EditorError.message("Couldn’t finish the export. Try another format.")
        }
        return data as Data
    }

    static func download(_ url: URL) async throws -> Data {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw EditorError.message("Enter a direct image URL beginning with https:// or http://.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw EditorError.message("The website didn’t provide the image. Try copying the image or saving it to your Mac first.")
        }
        guard response.expectedContentLength <= maxDownloadBytes else {
            throw EditorError.message("This image is larger than 50 MB. Try a smaller image.")
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxDownloadBytes {
                throw EditorError.message("This image is larger than 50 MB. Try a smaller image.")
            }
        }
        return data
    }
}
