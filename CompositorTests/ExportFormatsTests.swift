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

    /// Encodes the raster the way the Export As dialog does for each format.
    private func encode(_ raster: ExportRaster, format: ExportFormat,
                        options: JPEGOptions = JPEGOptions()) async throws -> (data: Data, preview: CGImage) {
        switch format {
        case .png: return (try await ImageExporter.shared.pngData(raster), raster.image)
        case .jpeg:
            let result = try await ImageExporter.shared.jpeg(raster, options: options)
            return (result.data, result.preview)
        case .pdf:
            return (try await ImageExporter.shared.pdfData(raster), raster.image)
        default:
            let result = try await ImageExporter.shared.encode(raster, format: format, options: options)
            return (result.data, result.preview)
        }
    }

    @Test func coreFormatsAreAlwaysOffered() {
        #expect(ExportFormat.available.contains(.png))
        #expect(ExportFormat.available.contains(.jpeg))
        #expect(ExportFormat.available.contains(.pdf))
    }

    @Test func everyAvailableFormatEncodesWithTheRightMagicBytes() async throws {
        let raster = try raster()
        var options = JPEGOptions()
        options.quality = 0.7
        options.red = 1; options.green = 0; options.blue = 1
        for format in ExportFormat.available {
            let (data, preview) = try await encode(raster, format: format, options: options)
            #expect(!data.isEmpty)
            #expect(preview.width > 0 && preview.height > 0)
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
            var options = JPEGOptions()
            options.red = 1; options.green = 0; options.blue = 1
            let (data, _) = try await encode(raster, format: format, options: options)
            let bitmap = try #require(NSBitmapImageRep(data: data))
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
            let (data, _) = try await encode(raster, format: format)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(try #require(bitmap.colorAt(x: 12, y: 8)).alphaComponent == 0)
        }
    }
}
