import AppKit
import Testing
@testable import Compositor

/// Filter › Progressive Blur: sharp at the start of a line dragged on the canvas, blurred to the full amount at its end
/// (or, radial, outwards from the start).
struct ProgressiveBlurTests {
    static let size = 200

    /// Black and white vertical stripes two pixels wide: sharp, they swing between 0 and 255; blurred, they gray out.
    private func stripes() throws -> CGImage {
        let context = try BrushRaster.context(width: Self.size, height: Self.size, mask: false)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 0, to: Self.size, by: 4) { context.fill(CGRect(x: x, y: 0, width: 2, height: Self.size)) }
        return try #require(context.makeImage())
    }

    /// How far the stripes still swing around (x, y), 0 (gray) to 255 (as sharp as they started).
    private func contrast(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let context = try BrushRaster.copy(image)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let values = (x..<(x + 8)).map { Int(bytes[y * context.bytesPerRow + $0 * 4]) }
        return values.max()! - values.min()!
    }

    private func blurred(radial: Bool, inverted: Bool = false, start: CGPoint, end: CGPoint) throws -> CGImage {
        var settings = FilterSettings()
        settings.progressiveTo = 6
        settings.progressiveStart = start
        settings.progressiveEnd = end
        settings.progressiveRadial = radial
        settings.progressiveInverted = inverted
        // The image placed at the document's origin, a pixel a unit: document points are its pixels.
        let job = FilterJob(kind: .progressiveBlur, image: try stripes(), settings: settings, scale: 1, selection: nil, mapping: .identity)
        return try PixelFilter.run(job)
    }

    @Test func linearIsSharpAtTheStartAndBlurredAtTheEnd() throws {
        let image = try blurred(radial: false, start: CGPoint(x: 100, y: 20), end: CGPoint(x: 100, y: 180))
        #expect(try contrast(image, x: 96, y: 10) > 230, "sharp before the start")
        let halfway = try contrast(image, x: 96, y: 100), early = try contrast(image, x: 96, y: 30)
        #expect(halfway < early, "softer halfway: \(halfway) against \(early)")
        #expect(try contrast(image, x: 96, y: 190) < 40, "blurred past the end")
    }

    /// From and To: blurred at both ends, more at To's.
    @Test func fromAndToSetTheBlurAtEachEnd() throws {
        var settings = FilterSettings()
        settings.progressiveFrom = 1.5
        settings.progressiveTo = 6
        settings.progressiveStart = CGPoint(x: 100, y: 20)
        settings.progressiveEnd = CGPoint(x: 100, y: 180)
        let job = FilterJob(kind: .progressiveBlur, image: try stripes(), settings: settings, scale: 1, selection: nil, mapping: .identity)
        let image = try PixelFilter.run(job)
        let start = try contrast(image, x: 96, y: 10), end = try contrast(image, x: 96, y: 190)
        #expect(start < 230 && start > end, "softened at the start (\(start)), more at the end (\(end))")
    }

    @Test func radialIsSharpInTheMiddleAndBlurredOutside() throws {
        let image = try blurred(radial: true, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 160, y: 100))
        #expect(try contrast(image, x: 96, y: 100) > 230, "sharp at the center")
        #expect(try contrast(image, x: 4, y: 4) < 40, "blurred in the corner, past the circle")
        let inverted = try blurred(radial: true, inverted: true, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 160, y: 100))
        #expect(try contrast(inverted, x: 96, y: 100) < 40, "inverted: blurred at the center")
        #expect(try contrast(inverted, x: 4, y: 4) > 230, "and sharp in the corner")
    }

    /// The filter starts with a line on the layer (sharp near its top, blurred at its foot); dragging moves it; and on
    /// a 16-bit layer it keeps the layer 16-bit, as the other blurs do.
    @Test @MainActor func theLineStartsOnTheLayerAndMoves() async throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 100)
        let context = try DeepLayer.context(width: 200, height: 100)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        session.insert(try DeepLayer.asset(try #require(context.makeImage()), name: "Deep"))
        session.beginFilter(.progressiveBlur)
        let edit = try #require(session.filterEdit)
        #expect(edit.settings.progressiveStart == CGPoint(x: 100, y: 35) && edit.settings.progressiveEnd == CGPoint(x: 100, y: 100))
        session.moveProgressiveBlur(end: CGPoint(x: 180, y: 50))
        #expect(session.filterEdit?.settings.progressiveEnd == CGPoint(x: 180, y: 50))
        await session.commitFilter()
        #expect(session.filterEdit == nil && session.activeLayer?.asset?.deep != nil, "applied, still 16-bit")
    }
}
