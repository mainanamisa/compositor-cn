import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated struct ImportedImage: @unchecked Sendable {
    // Immutable CGImages can be shared with the main-thread renderer.
    let image: CGImage
    let thumbnail: CGImage
    let name: String
    var raster: RasterSnapshot? = nil
}

nonisolated enum ImageImportError: LocalizedError {
    case unreadable, unreadablePDF, pdfLocked, unsupported, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取该图像，它可能已损坏或不可用"
        case .unreadablePDF: "无法读取 PDF，它可能已损坏或不可用"
        case .pdfLocked: "PDF 已加密，请先移除密码"
        case .unsupported: "请选择 JPEG、PNG、HEIC、TIFF 或 Photoshop（PSD）文件"
        case .tooLarge: "此导入超出当前 \(DocumentLimits.documentBudgetMegapixels) 百万像素的文档预算或 \(DocumentLimits.maxSide.formatted()) 像素的边长限制"
        }
    }
}

actor ImageImporter {
    static let shared = ImageImporter()
    // Created only on first import, never during empty-app launch.
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An SVG drawn once into pixels, by macOS's own SVG renderer: fitted to `fitting` (the canvas) when there is one,
    /// otherwise at the size the file declares. It comes in as an ordinary image layer, so it doesn't stay vector.
    func decodeSVG(_ url: URL, fitting: CGSize?, remainingPixels: Int = DocumentLimits.documentPixelBudget) throws -> ImportedImage {
        guard let svg = NSImage(contentsOf: url), svg.size.width > 0, svg.size.height > 0 else { throw ImageImportError.unreadable }
        let scale = fitting.map { min($0.width / svg.size.width, $0.height / svg.size.height) } ?? 1
        let width = max(1, Int((svg.size.width * scale).rounded())), height = max(1, Int((svg.size.height * scale).rounded()))
        guard width <= DocumentLimits.maxSide, height <= DocumentLimits.maxSide, width * height <= remainingPixels else {
            throw ImageImportError.tooLarge
        }
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        // Layer pixels are stored top row first; AppKit draws bottom-up, so the drawing is turned over to match.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        svg.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw ImageImportError.unreadable }
        return ImportedImage(image: image, thumbnail: try PixelAdjust.thumbnail(of: image), name: url.deletingPathExtension().lastPathComponent)
    }

    /// Every page of a PDF as one layer each, rasterized by PDFKit on white at 2× (144 DPI), Photoshop-fashion:
    /// a page is opaque paper, so transparency does not carry over. The pages share the remaining pixel budget,
    /// the scale stepping down from 2× rather than failing when a long or oversized document needs it.
    func decodePDF(_ url: URL, remainingPixels: Int = DocumentLimits.documentPixelBudget) throws -> [ImportedImage] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw ImageImportError.unreadablePDF }
        guard !document.isLocked else { throw ImageImportError.pdfLocked }
        let name = url.deletingPathExtension().lastPathComponent
        let budget = max(1, remainingPixels / document.pageCount)
        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw ImageImportError.unreadablePDF }
            return try autoreleasepool {
                let box = page.bounds(for: .mediaBox)
                guard box.width > 0, box.height > 0 else { throw ImageImportError.unreadablePDF }
                let scale = min(2, DocumentLimits.maxSideExtent / box.width, DocumentLimits.maxSideExtent / box.height,
                                (CGFloat(budget) / (box.width * box.height)).squareRoot())
                let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
                guard width >= 1, height >= 1 else { throw ImageImportError.tooLarge }
                let context = try BrushRaster.context(width: width, height: height, mask: false)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                // Layer pixels are stored top row first; PDFKit draws bottom-up, so the drawing is turned over
                // to match, scaled from points to pixels.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context)
                guard let image = context.makeImage() else { throw ImageImportError.unreadablePDF }
                return ImportedImage(image: image, thumbnail: try PixelAdjust.thumbnail(of: image),
                                     name: document.pageCount > 1 ? "\(name) 第 \(index + 1) 页" : name)
            }
        }
    }

    /// `flattenedPhotoshop`: a PSD or PSB with no layer records (only a background), read as its merged image.
    func decode(_ url: URL, remainingPixels: Int = DocumentLimits.documentPixelBudget, flattenedPhotoshop: Bool = false) throws -> ImportedImage {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let identifier = CGImageSourceGetType(source) as String?,
                  let type = UTType(identifier) else { throw ImageImportError.unreadable }
            let photoshop = flattenedPhotoshop ? [UTType.photoshopImage, .photoshopLargeImage] : []
            guard ([UTType.jpeg, .png, .heic, .tiff] + photoshop).contains(where: { type.conforms(to: $0) }) else {
                throw ImageImportError.unsupported
            }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else { throw ImageImportError.unreadable }
            guard width <= DocumentLimits.maxSide, height <= DocumentLimits.maxSide, width * height <= remainingPixels else {
                throw ImageImportError.tooLarge
            }
            guard let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw ImageImportError.unreadable
            }
            let orientation = (properties[kCGImagePropertyOrientation] as? Int32) ?? 1
            let oriented = CIImage(cgImage: decoded).oriented(forExifOrientation: orientation)
            guard let image = context.createCGImage(oriented, from: oriented.extent, format: .RGBA8, colorSpace: sRGB) else {
                throw ImageImportError.unreadable
            }
            let scale = min(1, 96 / max(oriented.extent.width, oriented.extent.height))
            let preview = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let thumbnail = context.createCGImage(preview, from: preview.extent.integral, format: .RGBA8, colorSpace: sRGB) else {
                throw ImageImportError.unreadable
            }
            return ImportedImage(image: image, thumbnail: thumbnail, name: url.deletingPathExtension().lastPathComponent)
        }
    }

    func loadPhotoshop(_ url: URL, remainingPixels: Int = DocumentLimits.documentPixelBudget) throws -> PSDDocument {
        try PSDReader.read(from: url, remainingPixels: remainingPixels)
    }

    func photoshopAssets(_ document: PSDDocument) throws -> [UUID: ImportedImage] {
        try PSDDocumentBuilder.assets(from: document)
    }
}
