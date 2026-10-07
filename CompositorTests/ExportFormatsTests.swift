import AppKit
import ImageIO
import Testing
@testable import Compositor

@MainActor
struct ExportFormatsTests {
    /// A raster whose left half is opaque color and whose right half stays transparent, so flattened
    /// formats exercise the matte and alpha-keeping formats have alpha to keep.
    private func raster() throws -> ExportRaster {
        let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
            bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        return ExportRaster(image: try #require(context.makeImage()))
    }

    @Test func coreFormatsAreAlwaysOffered() {
        #expect(ExportFormat.available.contains(.png))
        #expect(ExportFormat.available.contains(.jpeg))
        #expect(ExportFormat.available.contains(.pdf))
    }

    @Test func everyAvailableFormatEncodesWithTheRightMagicBytes() async throws {
        let raster = try raster()
        for format in ExportFormat.available {
            let result = try await ImageExporter.shared.encode(raster,
                options: ExportOptions(format: format, quality: 0.7, red: 1, green: 0, blue: 1))
            #expect(!result.data.isEmpty)
            #expect(result.preview.width > 0 && result.preview.height > 0)
            let data = result.data
            switch format {
            case .png: #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
            case .jpeg: #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
            case .heic: #expect(Array(data[4...7]) == Array("ftyp".utf8))
            case .webp:
                #expect(Array(data.prefix(4)) == Array("RIFF".utf8))
                #expect(Array(data[8...11]) == Array("WEBP".utf8))
            case .tiff: #expect(Array(data.prefix(2)) == [0x49, 0x49] || Array(data.prefix(2)) == [0x4D, 0x4D])
            case .gif: #expect(Array(data.prefix(4)) == Array("GIF8".utf8))
            case .bmp: #expect(Array(data.prefix(2)) == Array("BM".utf8))
            case .pdf: #expect(Array(data.prefix(4)) == Array("%PDF".utf8))
            }
        }
    }

    @Test func formatsWithoutAlphaFlattenOntoTheMatte() async throws {
        let raster = try raster()
        for format in ExportFormat.available where !format.supportsAlpha {
            let result = try await ImageExporter.shared.encode(raster,
                options: ExportOptions(format: format, red: 1, green: 0, blue: 1))
            let bitmap = try #require(NSBitmapImageRep(data: result.data))
            // The transparent right half became the magenta matte.
            let pixel = try #require(bitmap.colorAt(x: 12, y: 8))
            #expect(pixel.alphaComponent == 1)
            #expect(pixel.redComponent > 0.9 && pixel.blueComponent > 0.9 && pixel.greenComponent < 0.1)
        }
    }

    @Test func formatsWithAlphaKeepTransparentPixels() async throws {
        let raster = try raster()
        // PNG and TIFF decode losslessly; HEIC/WebP are covered by the magic-bytes test instead.
        for format in [ExportFormat.png, .tiff] where ExportFormat.available.contains(format) {
            let result = try await ImageExporter.shared.encode(raster, options: ExportOptions(format: format))
            let bitmap = try #require(NSBitmapImageRep(data: result.data))
            #expect(try #require(bitmap.colorAt(x: 12, y: 8)).alphaComponent == 0)
        }
    }
}
