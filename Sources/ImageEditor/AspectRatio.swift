import Foundation

enum ImageDimension: Equatable { case width, height }

/// Ratios carry no target resolution. Pixel dimensions round only at the boundary.
struct AspectRatio: Equatable, Hashable {
    let width: Int
    let height: Int

    init(_ width: Int, _ height: Int) {
        precondition(width > 0 && height > 0)
        var a = width, b = height
        while b != 0 { (a, b) = (b, a % b) }
        self.width = width / a
        self.height = height / a
    }

    init(size: CGSize) { self.init(Int(size.width), Int(size.height)) }
    var label: String { "\(width):\(height)" }
    var value: CGFloat { CGFloat(width) / CGFloat(height) }
    var swapped: AspectRatio { AspectRatio(height, width) }

    func pixelRange(axis: ImageDimension, limit: CGSize) -> ClosedRange<Double> {
        if axis == .width {
            let maximum = max(1, floor(min(limit.width, limit.height * value)))
            return Double(min(maximum, max(1, ceil(value))))...Double(maximum)
        }
        let maximum = max(1, floor(min(limit.height, limit.width / value)))
        return Double(min(maximum, max(1, ceil(1 / value))))...Double(maximum)
    }

    func pixelSize(side: CGFloat, axis: ImageDimension, limit: CGSize) -> CGSize {
        let requestedWidth = axis == .width ? side : side * value
        let maximumWidth = min(limit.width, limit.height * value)
        let minimumWidth = max(1, value)
        let width = min(maximumWidth, max(minimumWidth, requestedWidth))
        return CGSize(width: min(limit.width, max(1, width.rounded())),
                      height: min(limit.height, max(1, (width / value).rounded())))
    }

    /// Keep a resize anchor fixed, then fit both dimensions together within bounds.
    func cropRect(_ proposed: CGRect, bounds: CGSize,
                  anchor: CGPoint = CGPoint(x: 0.5, y: 0.5), axis: ImageDimension? = nil) -> CGRect {
        let pivot = CGPoint(x: min(bounds.width, max(0, proposed.minX + proposed.width * anchor.x)),
                            y: min(bounds.height, max(0, proposed.minY + proposed.height * anchor.y)))
        var limit = bounds
        if anchor.x > 0 { limit.width = min(limit.width, pivot.x / anchor.x) }
        if anchor.x < 1 { limit.width = min(limit.width, (bounds.width - pivot.x) / (1 - anchor.x)) }
        if anchor.y > 0 { limit.height = min(limit.height, pivot.y / anchor.y) }
        if anchor.y < 1 { limit.height = min(limit.height, (bounds.height - pivot.y) / (1 - anchor.y)) }
        // A new selection can start at the very edge; keep at least one pixel.
        limit.width = max(1, limit.width); limit.height = max(1, limit.height)
        let side = axis == .height ? proposed.height
            : axis == .width ? proposed.width : min(proposed.width, proposed.height * value)
        let size = pixelSize(side: side, axis: axis ?? .width, limit: limit)
        return CGRect(x: min(bounds.width - size.width, max(0, (pivot.x - size.width * anchor.x).rounded())),
                      y: min(bounds.height - size.height, max(0, (pivot.y - size.height * anchor.y).rounded())),
                      width: size.width, height: size.height)
    }
}

struct AspectRatioPreset: Identifiable {
    let name: String
    let ratio: AspectRatio
    var id: String { label }
    var label: String { "\(name) · \(ratio.label)" }

    init(_ name: String, _ width: Int, _ height: Int) {
        self.name = name; ratio = AspectRatio(width, height)
    }

    static let common: [AspectRatioPreset] = [
        .init("Square", 1, 1), .init("Landscape", 16, 9), .init("Portrait", 4, 5),
        .init("Stories / Reels", 9, 16), .init("Landscape", 4, 3), .init("Portrait", 3, 4)
    ]

    // Proportions from the supplied social-media size chart, including cover photos.
    static let social: [(name: String, presets: [AspectRatioPreset])] = [
        ("Instagram", [.init("Profile / Square", 1, 1), .init("Landscape", 1080, 566),
                       .init("Vertical", 4, 5), .init("Stories / Reels", 9, 16)]),
        ("Facebook", [.init("Profile / Square", 1, 1), .init("Landscape", 1080, 566),
                      .init("Vertical", 1080, 1359), .init("Stories / Reels", 9, 16),
                      .init("Cover photo", 851, 315)]),
        ("X", [.init("Profile / Square", 1, 1), .init("Landscape", 16, 9),
               .init("Vertical", 9, 16), .init("Cover photo", 3, 1)]),
        ("LinkedIn", [.init("Profile / Square", 1, 1), .init("Landscape", 1200, 627),
                      .init("Vertical", 4, 5), .init("Cover photo", 1128, 191)]),
        ("TikTok", [.init("Profile / Square", 1, 1), .init("Landscape", 16, 9),
                    .init("Vertical / Stories", 9, 16)])
    ]
}

struct ExportResize: Equatable {
    let axis: ImageDimension
    let pixels: CGFloat

    func size(for canvas: CGSize) -> CGSize {
        AspectRatio(size: canvas).pixelSize(side: pixels, axis: axis,
                                          limit: CGSize(width: ImageEngine.maxDimension, height: ImageEngine.maxDimension))
    }
}
