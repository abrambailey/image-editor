import AppKit
import CoreML

/// A fixed, local segmentation model. Only its alpha mask is applied to source pixels.
final class ForegroundExtractor {
    static let shared = ForegroundExtractor()
    static let inputSize = 1024
    private let lock = NSLock()
    private var model: MLModel?

    func removeBackground(from image: CGImage) throws -> CGImage {
        // Reuse the loaded model and serialize inference across editor windows.
        lock.lock()
        defer { lock.unlock() }
        let model = try loadedModel()
        let size = Self.inputSize
        let inputContext = try ImageEngine.context(width: size, height: size)
        // Transparent inputs have no meaningful RGB in empty pixels. Composite onto
        // white for inference, then retain the source alpha in the final cutout.
        inputContext.setFillColor(CGColor(gray: 1, alpha: 1))
        inputContext.fill(CGRect(x: 0, y: 0, width: size, height: size))
        inputContext.interpolationQuality = .high
        inputContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = inputContext.data!.assumingMemoryBound(to: UInt8.self)
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let values = input.dataPointer.assumingMemoryBound(to: Float.self)
        let mean: [Float] = [0.485, 0.456, 0.406]
        let deviation: [Float] = [0.229, 0.224, 0.225]
        for channel in 0..<3 {
            for pixel in 0..<(size * size) {
                values[channel * size * size + pixel] = (Float(pixels[pixel * 4 + channel]) / 255 - mean[channel]) / deviation[channel]
            }
        }
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input]))
        guard let logits = prediction.featureValue(for: "mask_logits")?.multiArrayValue,
              logits.shape.map({ $0.intValue }) == [1, 1, size, size], logits.dataType == .float32 else {
            throw EditorError.message("The background model returned an unsupported mask.")
        }
        let output = logits.dataPointer.assumingMemoryBound(to: Float.self)
        let rowStride = logits.strides[2].intValue, columnStride = logits.strides[3].intValue
        var mask = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let logit = output[y * rowStride + x * columnStride]
                guard logit.isFinite else { throw EditorError.message("The background model returned an invalid mask. Try again.") }
                mask[y * size + x] = 1 / (1 + exp(-logit))
            }
        }
        return try Self.apply(mask: mask, width: size, height: size, to: image)
    }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        let url: URL?
        if let path = ProcessInfo.processInfo.environment["IMAGE_EDITOR_MODEL_PATH"] {
            url = URL(fileURLWithPath: path)
        } else {
            url = Bundle.main.url(forResource: "BiRefNetLite", withExtension: "mlmodelc")
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw EditorError.message("The background model is missing. Rebuild the app with scripts/build.sh.")
        }
        let configuration = MLModelConfiguration()
        // This conversion is validated for CPU inference, including its thin-detail path.
        configuration.computeUnits = .cpuOnly
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        model = loaded
        return loaded
    }

    /// Resize only the mask, never the source image. Pixel-center sampling keeps
    /// non-square images aligned; multiplying premultiplied RGBA preserves source alpha.
    static func apply(mask: [Float], width: Int, height: Int, to image: CGImage) throws -> CGImage {
        guard width > 0, height > 0, width <= ImageEngine.maxDimension, height <= ImageEngine.maxDimension,
              mask.count == width * height, mask.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw EditorError.message("The background mask is invalid.")
        }
        let context = try ImageEngine.context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            let my = max(0, min(Float(height - 1), (Float(y) + 0.5) * Float(height) / Float(image.height) - 0.5))
            let y0 = Int(my), y1 = min(height - 1, y0 + 1), fy = my - Float(y0)
            for x in 0..<image.width {
                let mx = max(0, min(Float(width - 1), (Float(x) + 0.5) * Float(width) / Float(image.width) - 0.5))
                let x0 = Int(mx), x1 = min(width - 1, x0 + 1), fx = mx - Float(x0)
                let alpha = (mask[y0 * width + x0] * (1 - fx) + mask[y0 * width + x1] * fx) * (1 - fy)
                    + (mask[y1 * width + x0] * (1 - fx) + mask[y1 * width + x1] * fx) * fy
                let offset = y * context.bytesPerRow + x * 4
                for channel in 0..<4 {
                    pixels[offset + channel] = UInt8(clamping: Int((Float(pixels[offset + channel]) * alpha).rounded()))
                }
            }
        }
        guard let cutout = context.makeImage() else { throw EditorError.message("Couldn’t create the cutout.") }
        return cutout
    }
}
