import AppKit
import Testing
@testable import Compositor

/// The Remove tool: painting marks the area with a wash, and letting go asks the model to fill it.
/// Everything up to the model call runs without the download, so it is tested here; the model
/// itself runs only where it has been downloaded.
@MainActor
struct RemoveFillTests {
    private func pixels(_ image: CGImage) throws -> (Int, Int) -> [Int] {
        let read = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        read.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = Array(UnsafeBufferPointer(start: try #require(read.data).assumingMemoryBound(to: UInt8.self),
                                              count: image.width * image.height * 4))
        let width = image.width
        return { x, y in (0..<4).map { Int(bytes[(y * width + x) * 4 + $0]) } }
    }
    /// A solid red 200 × 200 layer over the whole 200 × 200 canvas.
    private func session() throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        let context = try BrushRaster.context(width: 200, height: 200, mask: false)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Photo"))
        let index = try #require(session.document?.layers.indices.last)
        session.document?.layers[index].transform = LayerTransform(origin: .zero, size: CGSize(width: 200, height: 200))
        return session
    }
    private func stroke(_ session: EditorSession, diameter: CGFloat = 40) throws -> BrushStroke {
        var settings = BrushSettings(diameter: diameter, hardness: 1, red: 0, green: 0, blue: 0)
        settings.removing = true
        let layer = try #require(session.activeLayer)
        return try BrushStroke(layer: layer, mask: false, settings: settings, canvas: session.document!.size, useGPU: false)
    }

    @Test func regionAddsContextAroundThePaintedArea() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Half the painted side, at least 64 px, of margin.
        #expect(RemoveFill.region(painted: CGRect(x: 400, y: 400, width: 100, height: 100), source: source)
                == CGRect(x: 336, y: 336, width: 228, height: 228))
        #expect(RemoveFill.region(painted: CGRect(x: 100, y: 100, width: 400, height: 200), source: source)
                == CGRect(x: 0, y: 0, width: 700, height: 500))
        // Past the layer's own pixels there is nothing to fill from.
        #expect(RemoveFill.region(painted: CGRect(x: 0, y: 0, width: 50, height: 50), source: source)
                == CGRect(x: 0, y: 0, width: 114, height: 114))
        // A tiny dab still offers the model a usable neighborhood.
        #expect(RemoveFill.region(painted: CGRect(x: 500, y: 500, width: 4, height: 4), source: source)
                == CGRect(x: 436, y: 436, width: 132, height: 132))
    }

    @Test func prepareRemovalCropsPixelsAndMaskAroundTheStroke() throws {
        let session = try session()
        let stroke = try stroke(session)
        try stroke.append(CGPoint(x: 100, y: 100))
        try stroke.flush()
        let removal = try #require(try stroke.prepareRemoval())
        #expect(removal.region.width == CGFloat(removal.pixels.width))
        #expect(removal.region.height == CGFloat(removal.pixels.height))
        #expect(removal.mask.width == removal.pixels.width && removal.mask.height == removal.pixels.height)
        // The mask is white where the brush went and black everywhere else.
        let mask = try pixels(removal.mask)
        let center = (x: Int(100 - removal.region.minX), y: Int(100 - removal.region.minY))
        #expect(mask(center.x, center.y)[0] > 200)
        #expect(mask(2, 2)[0] < 40)
        // The pixels are the layer's own: red, not the wash shown while painting.
        // (Color management shifts the channels a little, so check dominance, not equality.)
        let source = try pixels(removal.pixels)(center.x, center.y)
        #expect(source[0] > 200 && source[1] < 80 && source[3] == 255)
    }

    @Test func prepareRemovalSkipsStrokesOverTransparency() throws {
        let session = EditorSession()
        session.createDocument(width: 200, height: 200)
        let context = try BrushRaster.context(width: 100, height: 100, mask: false)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
        let image = try #require(context.makeImage())
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Photo"))
        let index = try #require(session.document?.layers.indices.last)
        session.document?.layers[index].transform = LayerTransform(origin: .zero, size: CGSize(width: 100, height: 100))
        // Only transparency under the brush: nothing to remove.
        let transparent = try stroke(session)
        try transparent.append(CGPoint(x: 75, y: 50))
        try transparent.flush()
        #expect(try transparent.prepareRemoval() == nil)
        // Off the layer altogether: nothing to remove either.
        let outside = try stroke(session)
        try outside.append(CGPoint(x: 150, y: 150))
        try outside.flush()
        #expect(try outside.prepareRemoval() == nil)
    }

    @Test func applyRemovalWritesTheFillBackAsOneUndoStep() throws {
        let session = try session()
        let stroke = try stroke(session)
        try stroke.append(CGPoint(x: 100, y: 100))
        try stroke.flush()
        let removal = try #require(try stroke.prepareRemoval())
        let count = session.history.undoCount
        // A stand-in for the model's fill: solid green over the whole region.
        let fill = try BrushRaster.context(width: Int(removal.region.width), height: Int(removal.region.height), mask: false)
        fill.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        fill.fill(CGRect(origin: .zero, size: removal.region.size))
        stroke.applyRemoval(try #require(fill.makeImage()), region: removal.region)
        try session.commitPaintSnapshot(stroke)
        #expect(session.history.undoCount == count + 1)
        let committed = try pixels(try #require(session.activeLayer?.asset?.image))
        let filled = committed(100, 100)
        #expect(filled[1] > 200 && filled[0] < 80 && filled[3] == 255)
        // Outside the region the layer keeps its pixels: the region's margin is the brush's 20 + 64.
        let kept = committed(4, 100)
        #expect(kept[0] > 200 && kept[1] < 80 && kept[3] == 255)
        session.undo()
        let restored = try pixels(try #require(session.activeLayer?.asset?.image))(100, 100)
        #expect(restored[0] > 200 && restored[1] < 80 && restored[3] == 255)
    }

    /// The model itself: only where the one-time download has already happened. A white square
    /// masked out of a red field comes back red, and nothing outside the mask changes.
    @Test(.enabled(if: RemoveModelStore.isAvailable))
    func inpaintedFillsTheMaskedAreaFromItsSurroundings() throws {
        let field = try BrushRaster.context(width: 200, height: 200, mask: false)
        field.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        field.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        field.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        field.fill(CGRect(x: 85, y: 85, width: 30, height: 30))
        let mask = try BrushRaster.context(width: 200, height: 200, mask: true)
        mask.setFillColor(CGColor(gray: 1, alpha: 1))
        mask.fill(CGRect(x: 85, y: 85, width: 30, height: 30))
        let filled = try RemoveFill.inpainted(image: try #require(field.makeImage()), mask: try #require(mask.makeImage()))
        #expect(filled.width == 200 && filled.height == 200)
        let result = try pixels(filled)
        let center = result(100, 100)
        #expect(center[0] > 150 && center[1] < 100 && center[3] == 255, "center is \(center), not filled red")
        let corner = result(20, 20)
        #expect(corner[0] > 200 && corner[1] < 80 && corner[3] == 255)
    }
}
