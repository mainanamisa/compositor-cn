//
//  LaMaInpainter.swift
//  Compositor
//
//  Vendored from https://github.com/arraypress/swift-inpaint (single-file package,
//  no dependencies), with the model cache pointed at Compositor's Caches folder.
//
//  MIT License
//
//  Copyright (c) 2026 David Sherlock (ArrayPress)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//  The LaMa model weights it loads are Apache-2.0 (see RemoveModelStore for the download).

import CoreImage
import CoreML
import Foundation

/// Wraps the LaMa Core ML inpainting model (Apache): an image + a mask of what
/// to remove (white = remove) → a plausibly filled result. The model runs at
/// 800×800; the fill is composited back onto the full-resolution original so
/// only the masked region changes.
final class LaMaInpainter: @unchecked Sendable {

    static let side = 800
    private let model: MLModel
    private let ciContext = CIContext()

    init(modelURL: URL) throws {
        let url = try Self.compiledURL(for: modelURL, cacheFolder: "Compositor")
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: url, configuration: config)
    }


    /// Compiles once and caches in Caches/ keyed by name + mtime — compiling
    /// the .mlpackage on every init cost seconds of startup per session.
    static func compiledURL(for modelURL: URL, cacheFolder: String) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" { return modelURL }
        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: modelURL.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let dir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("\(cacheFolder)/CompiledModels", isDirectory: true)
        let dst = dir.appendingPathComponent("\(modelURL.deletingPathExtension().lastPathComponent)-\(Int(mtime)).mlmodelc")
        if fm.fileExists(atPath: dst.path) { return dst }
        let compiled = try MLModel.compileModel(at: modelURL)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try fm.moveItem(at: compiled, to: dst)
        return dst
    }

    /// Removes the masked region from `image` (mask white = remove) and fills it.
    /// `feather` softens the seam. Returns the full-resolution result.
    ///
    /// The model runs on a SQUARE crop around the mask's content (padded,
    /// clamped to the frame) rather than the squashed whole frame — squeezing a
    /// wide frame anisotropically into 800² smeared the fill's texture, and the
    /// crop also gives the model far more effective resolution in the region
    /// that matters.
    func inpaint(_ image: CIImage, mask: CIImage, feather: CGFloat = 2) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        // A generator mask (infinite extent) or one at another size would
        // silently misalign the model resize vs the composite-back.
        guard !mask.extent.isInfinite else { return nil }
        let mask = mask.cropped(to: extent)
        let N = Self.side

        // Region around the mask content: bounds + 35% context margin, at
        // least 320px per side, aiming square for aspect fidelity — but NEVER
        // smaller than the content (a forced square that couldn't contain a
        // tall mask left parts of it unfilled). The region must always cover
        // the mask; mild non-squareness is fine.
        let content = maskContentBounds(mask) ?? extent
        let want = max(max(content.width, content.height) * 1.7, 320)
        let w = min(max(want, content.width * 1.1), extent.width)
        let h = min(max(want, content.height * 1.1), extent.height)
        var region = CGRect(x: content.midX - w / 2, y: content.midY - h / 2, width: w, height: h)
        if region.minX < extent.minX { region.origin.x = extent.minX }
        if region.minY < extent.minY { region.origin.y = extent.minY }
        if region.maxX > extent.maxX { region.origin.x = extent.maxX - w }
        if region.maxY > extent.maxY { region.origin.y = extent.maxY - h }
        region = region.intersection(extent).union(content.intersection(extent))

        guard let imageBuffer = pixelBuffer(from: image.cropped(to: region), side: N, format: kCVPixelFormatType_32BGRA),
              let maskBuffer = pixelBuffer(from: mask.cropped(to: region), side: N, format: kCVPixelFormatType_OneComponent8)
        else { return nil }

        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image": imageBuffer, "mask": maskBuffer,
        ])),
              let filledBuffer = out.featureValue(for: "output")?.imageBufferValue
        else { return nil }

        // Upscale the 800² fill back onto the region, then composite it in only
        // where the mask is (feathered) — the rest stays full-res sharp.
        let filled = CIImage(cvPixelBuffer: filledBuffer)
        let sx = region.width / filled.extent.width, sy = region.height / filled.extent.height
        let filledUp = filled
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: region.minX - filled.extent.minX * sx,
                                               y: region.minY - filled.extent.minY * sy))
            .cropped(to: region)
            .composited(over: image)   // full frame with the filled region in place
            .cropped(to: extent)

        let softMask = feather > 0
            ? mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": feather]).cropped(to: extent)
            : mask
        return filledUp.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": image, "inputMaskImage": softMask,
        ]).cropped(to: extent)
    }

    /// Tight bounds of the mask's white content via a low-res scan.
    private func maskContentBounds(_ mask: CIImage) -> CGRect? {
        let extent = mask.extent
        let side = 128
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let scaled = mask
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width, y: CGFloat(side) / extent.height))
        ciContext.render(scaled, toBitmap: &buf, rowBytes: side * 4,
                         bounds: CGRect(x: 0, y: 0, width: side, height: side),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where buf[(y * side + x) * 4] > 32 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let fx = extent.width / CGFloat(side), fy = extent.height / CGFloat(side)
        // The scan's y is top-down (rendered bitmap); CI space is bottom-up.
        return CGRect(x: extent.minX + CGFloat(minX) * fx,
                      y: extent.minY + extent.height - CGFloat(maxY + 1) * fy,
                      width: CGFloat(maxX - minX + 1) * fx,
                      height: CGFloat(maxY - minY + 1) * fy)
    }

    private func pixelBuffer(from image: CIImage, side: Int, format: OSType) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(nil, side, side, format, attrs, &pb)
        guard let buffer = pb else { return nil }
        let sx = CGFloat(side) / image.extent.width, sy = CGFloat(side) / image.extent.height
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        ciContext.render(scaled, to: buffer)
        return buffer
    }
}
