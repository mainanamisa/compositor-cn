import AppKit
import ImageIO
import PDFKit
import Testing
@testable import Compositor

@MainActor
struct PDFImportTests {
    /// A PDF written to a temporary file: each page fills its left half with the given color, leaving the
    /// rest to the importer's white matte.
    private func pdfURL(colors: [CGColor], size: CGSize = CGSize(width: 100, height: 50), password: String? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("样张.pdf")
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = try #require(CGDataConsumer(data: data))
        let auxInfo = password.map { [kCGPDFContextUserPassword: $0, kCGPDFContextOwnerPassword: $0] as CFDictionary }
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, auxInfo))
        for color in colors {
            context.beginPDFPage(nil)
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
        return url
    }

    @Test func everyPageBecomesALayerSizedImageAtDoubleScaleFlattenedOnWhite() async throws {
        let url = try pdfURL(colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pages = try await ImageImporter.shared.decodePDF(url)
        #expect(pages.count == 2)
        #expect(pages.map(\.name) == ["样张 第 1 页", "样张 第 2 页"])
        // 100 × 50 points at 2× is 200 × 100 pixels.
        #expect(pages.allSatisfy { $0.image.width == 200 && $0.image.height == 100 })
        #expect(pages.allSatisfy { $0.thumbnail.width > 0 })
        for (page, isRed) in zip(pages, [true, false]) {
            let bitmap = NSBitmapImageRep(cgImage: page.image)
            let drawn = try #require(bitmap.colorAt(x: 50, y: 50))
            #expect(isRed ? drawn.redComponent > 0.99 : drawn.blueComponent > 0.99)
            // The empty half flattened onto opaque white.
            let matte = try #require(bitmap.colorAt(x: 150, y: 50))
            #expect(matte.alphaComponent == 1)
            #expect(matte.redComponent > 0.99 && matte.greenComponent > 0.99 && matte.blueComponent > 0.99)
        }
    }

    @Test func singlePageKeepsTheFileName() async throws {
        let url = try pdfURL(colors: [CGColor(red: 0, green: 1, blue: 0, alpha: 1)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pages = try await ImageImporter.shared.decodePDF(url)
        #expect(pages.count == 1)
        #expect(pages[0].name == "样张")
    }

    @Test func oversizedPagesAndTightBudgetsStepTheScaleDown() async throws {
        let wide = try pdfURL(colors: [CGColor(gray: 0, alpha: 1)], size: CGSize(width: 20_000, height: 10))
        defer { try? FileManager.default.removeItem(at: wide.deletingLastPathComponent()) }
        let scaled = try #require(try await ImageImporter.shared.decodePDF(wide).first)
        // 20,000 points at 2× exceeds the 30,000-pixel side limit, so the scale drops to 1.5×.
        #expect(scaled.image.width == DocumentLimits.maxSide && scaled.image.height == 15)

        let url = try pdfURL(colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // 5,000 pixels for each of two 100 × 50-point pages leaves room for exactly 1×, not 2×.
        let pages = try await ImageImporter.shared.decodePDF(url, remainingPixels: 10_000)
        #expect(pages.allSatisfy { $0.image.width == 100 && $0.image.height == 50 })
    }

    @Test func lockedAndCorruptFilesFailWithChineseMessages() async throws {
        let locked = try pdfURL(colors: [CGColor(gray: 0, alpha: 1)], password: "secret")
        defer { try? FileManager.default.removeItem(at: locked.deletingLastPathComponent()) }
        await #expect(throws: ImageImportError.self) { _ = try await ImageImporter.shared.decodePDF(locked) }
        do {
            _ = try await ImageImporter.shared.decodePDF(locked)
        } catch let error as ImageImportError {
            #expect(error == .pdfLocked)
            #expect(error.localizedDescription == "PDF 已加密，请先移除密码")
        } catch { Issue.record("Expected pdfLocked, got \(error)") }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let corrupt = folder.appendingPathComponent("损坏.pdf")
        try Data("这不是 PDF".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            _ = try await ImageImporter.shared.decodePDF(corrupt)
            Issue.record("A corrupt PDF decoded successfully")
        } catch let error as ImageImportError {
            #expect(error == .unreadablePDF)
            #expect(error.localizedDescription == "无法读取 PDF，它可能已损坏或不可用")
        } catch { Issue.record("Expected unreadablePDF, got \(error)") }
    }
}
