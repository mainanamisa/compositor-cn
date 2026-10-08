import AppKit
import CoreImage

/// The Remove tool's fill: the painted area, filled from its surroundings by the LaMa model.
nonisolated enum RemoveFill {
    enum Failure: LocalizedError {
        case modelMissing, fillFailed
        var errorDescription: String? {
            switch self {
            case .modelMissing: "移除模型尚未下载"
            case .fillFailed: "移除失败，请重试"
            }
        }
    }

    /// The crop the model sees: the painted bounds with context around them — LaMa fills better the more
    /// surroundings it gets — clamped to the layer's own pixels, since past them there is nothing to fill
    /// from. At least 64 px of margin, so a tiny dab still offers a usable neighborhood.
    static func region(painted: CGRect, source: CGRect) -> CGRect {
        let margin = max(64, max(painted.width, painted.height) / 2)
        return painted.insetBy(dx: -margin, dy: -margin).integral.intersection(source)
    }

    /// The inpainter, compiled and loaded once (a few seconds the first time), then shared.
    private static let cache = InpainterCache()
    private final class InpainterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: LaMaInpainter?
        func inpainter() throws -> LaMaInpainter {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            let made = try LaMaInpainter(modelURL: RemoveModelStore.modelURL)
            value = made
            return made
        }
    }

    /// Fills the mask's white areas (white = remove) from the image around them, changing nothing outside
    /// the mask. Run off the main actor: the model takes a moment.
    static func inpainted(image: CGImage, mask: CGImage) throws -> CGImage {
        guard RemoveModelStore.isAvailable else { throw Failure.modelMissing }
        guard let filled = try cache.inpainter().inpaint(CIImage(cgImage: image), mask: CIImage(cgImage: mask)) else {
            throw Failure.fillFailed
        }
        return try PixelAdjust.render(filled, width: image.width, height: image.height, isMask: false)
    }
}
