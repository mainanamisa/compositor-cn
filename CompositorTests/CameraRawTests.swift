import AppKit
import Testing
@testable import Compositor

@MainActor
struct CameraRawTests {
    private func image(width: Int = 4, height: Int = 4, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func gray(width: Int = 4, height: Int = 4, alpha: CGFloat = 1) throws -> CGImage {
        try image(width: width, height: height, red: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: alpha)
    }

    /// Straight RGBA bytes, top row first.
    private func pixels(_ image: CGImage) throws -> [[Int]] {
        let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var result: [[Int]] = []
        for index in 0..<image.width * image.height {
            let alpha = Int(data[index * 4 + 3])
            var pixel: [Int] = []
            for channel in 0..<3 {
                let value: Int = alpha == 0 ? 0 : min(255, (Int(data[index * 4 + channel]) * 255 + alpha / 2) / alpha)
                pixel.append(value)
            }
            pixel.append(alpha)
            result.append(pixel)
        }
        return result
    }

    private func chroma(_ pixel: [Int]) -> Int {
        let rgb = [pixel[0], pixel[1], pixel[2]]
        return (rgb.max() ?? 0) - (rgb.min() ?? 0)
    }

    @Test func defaultsLeavePixelsAndAlphaAlone() throws {
        let input = try gray(alpha: 0.5)
        #expect(try pixels(CameraRawSettings().apply(input)) == pixels(input))
        var broken = CameraRawSettings()
        broken.exposure = .nan
        broken.temperature = 400
        #expect(!broken.isValid)
        #expect(broken.normalized.exposure == 0 && broken.normalized.temperature == 100)
        #expect(!FilterKind.cameraRaw.isImageAdjustment)
    }

    /// Exposure and Contrast as Photoshop's Camera Raw Filter draws them: the numbers are its own, measured.
    @Test func exposureAndContrastMatchPhotoshop() throws {
        let input = try gray()
        var settings = CameraRawSettings()
        settings.exposure = 1
        let brighter = try pixels(settings.apply(input))[0]
        #expect(abs(brighter[0] - 181) <= 2, "+1 stop: \(brighter)")
        #expect(brighter[0] == brighter[1] && brighter[1] == brighter[2])
        let translucent = try gray(alpha: 0.5)
        #expect(try pixels(settings.apply(translucent))[0][3] == pixels(translucent)[0][3])

        let context = try BrushRaster.context(width: 2, height: 1, mask: false)
        context.setFillColor(CGColor(srgbRed: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(srgbRed: 192 / 255, green: 192 / 255, blue: 192 / 255, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let pair = try #require(context.makeImage())
        settings = CameraRawSettings()
        settings.contrast = 100
        let pushed = try pixels(settings.apply(pair))
        #expect(abs(pushed[0][0] - 36) <= 3 && abs(pushed[1][0] - 213) <= 3, "contrast +100 drives the pair apart: \(pushed)")
        settings.contrast = -100
        let flat = try pixels(settings.apply(pair))
        #expect(abs(flat[0][0] - 88) <= 3 && abs(flat[1][0] - 174) <= 3, "contrast −100 draws them together: \(flat)")
    }

    @Test func tonalSlidersMoveTheEndTheyName() throws {
        let context = try BrushRaster.context(width: 2, height: 1, mask: false)
        context.setFillColor(CGColor(srgbRed: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let brightAndMid = try #require(context.makeImage())
        var settings = CameraRawSettings()
        settings.highlights = -100
        let recovered = try pixels(settings.apply(brightAndMid))
        // Photoshop: 230 → 209, mid gray kept.
        #expect(recovered[0][0] < 222, "highlights −100 darkens the bright tone: \(recovered[0])")
        #expect(abs(recovered[1][0] - 128) <= 4, "and leaves mid gray: \(recovered[1])")

        settings = CameraRawSettings()
        settings.whites = 100
        let clipped = try pixels(settings.apply(brightAndMid))
        #expect(clipped[0][0] == 255, "whites +100 clips the bright tone: \(clipped[0])")
        #expect(clipped[1][0] > 128, "and lifts the midtone with it, as in Photoshop: \(clipped[1])")
        let viz = try pixels(settings.apply(brightAndMid, clipping: .highlights))
        #expect(viz[0] == [255, 255, 255, 255] && viz[1] == [0, 0, 0, 255], "highlight clipping is not the grade: \(viz)")

        let darkContext = try BrushRaster.context(width: 2, height: 1, mask: false)
        darkContext.setFillColor(CGColor(srgbRed: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1))
        darkContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        darkContext.setFillColor(CGColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1))
        darkContext.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let darkAndMid = try #require(darkContext.makeImage())
        settings = CameraRawSettings()
        settings.shadows = 100
        let opened = try pixels(settings.apply(darkAndMid))
        // Photoshop: 20 → 33, mid gray kept.
        #expect(opened[0][0] > 22, "shadows +100 opens the dark tone: \(opened[0])")
        #expect(abs(opened[1][0] - 128) <= 6, "and leaves mid gray: \(opened[1])")

        settings = CameraRawSettings()
        settings.blacks = -100
        let crushed = try pixels(settings.apply(darkAndMid))
        #expect(crushed[0][0] == 0, "blacks −100 crushes the dark tone: \(crushed[0])")
        #expect(abs(crushed[1][0] - 91) <= 3, "and darkens the midtone, as in Photoshop: \(crushed[1])")
        let shadowViz = try pixels(settings.apply(darkAndMid, clipping: .shadows))
        #expect(shadowViz[0] == [0, 0, 0, 255] && shadowViz[1] == [255, 255, 255, 255], "shadow clipping is not the grade: \(shadowViz)")
    }

    @Test func temperatureWarmsAndTintMovesTowardMagenta() throws {
        let input = try gray()
        var settings = CameraRawSettings()
        settings.temperature = 100
        let warm = try pixels(settings.apply(input))[0]
        #expect(warm[0] > 128 && warm[2] < 128 && warm[0] > warm[2], "warm shifts red up and blue down: \(warm)")
        settings = CameraRawSettings()
        settings.tint = 100
        let magenta = try pixels(settings.apply(input))[0]
        #expect(magenta[1] < 128 && magenta[1] < magenta[0] && magenta[1] < magenta[2], "magenta lowers green: \(magenta)")
    }

    /// Temperature, Tint and Vibrance as Photoshop's Camera Raw Filter draws them, its own measured numbers. They were
    /// once a few percent either way, a fraction of Photoshop's strength (issue #252).
    @Test func whiteBalanceAndVibranceMatchPhotoshop() throws {
        func applied(_ red: Int, _ green: Int, _ blue: Int, _ adjust: (inout CameraRawSettings) -> Void) throws -> [Int] {
            var settings = CameraRawSettings()
            adjust(&settings)
            return Array(try pixels(settings.apply(image(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                                                         blue: CGFloat(blue) / 255)))[0].prefix(3))
        }
        func near(_ got: [Int], _ expected: [Int]) -> Bool { zip(got, expected).allSatisfy { abs($0 - $1) <= 4 } }
        let cases: [(String, [Int], (inout CameraRawSettings) -> Void, [Int])] = [
            ("temperature +100", [128, 128, 128], { $0.temperature = 100 }, [235, 189, 117]),
            ("temperature −50", [128, 128, 128], { $0.temperature = -50 }, [102, 146, 210]),
            ("tint +100", [128, 128, 128], { $0.tint = 100 }, [159, 125, 215]),
            ("tint −100", [128, 128, 128], { $0.tint = -100 }, [98, 198, 120]),
            ("vibrance +100 spares skin", [153, 107, 107], { $0.vibrance = 100 }, [167, 98, 98]),
            ("vibrance +100 fills a dull cyan", [107, 153, 153], { $0.vibrance = 100 }, [0, 160, 160]),
            ("vibrance −100", [92, 92, 230], { $0.vibrance = -100 }, [164, 164, 210]),
        ]
        for (name, input, adjust, expected) in cases {
            let got = try applied(input[0], input[1], input[2], adjust)
            #expect(near(got, expected), "\(name): \(got), Photoshop \(expected)")
        }
    }

    /// The Color Mixer, Calibration, the parametric curve and both vignettes as Photoshop's Camera Raw Filter draws them:
    /// its own measured numbers.
    @Test func mixerCalibrationCurveAndVignettesMatchPhotoshop() throws {
        func applied(_ input: [Int], _ adjust: (inout CameraRawSettings) -> Void) throws -> [Int] {
            var settings = CameraRawSettings()
            adjust(&settings)
            let source = try image(red: CGFloat(input[0]) / 255, green: CGFloat(input[1]) / 255, blue: CGFloat(input[2]) / 255)
            return Array(try pixels(settings.apply(source))[0].prefix(3))
        }
        func near(_ got: [Int], _ expected: [Int]) -> Bool { zip(got, expected).allSatisfy { abs($0 - $1) <= 4 } }
        let cases: [(String, [Int], (inout CameraRawSettings) -> Void, [Int])] = [
            ("orange saturation −60", [230, 115, 0], { $0.mixer.saturation[1] = -60 }, [189, 130, 107]),
            ("red hue +60", [230, 92, 92], { $0.mixer.hue[0] = 60 }, [227, 125, 83]),
            ("blue luminance +60", [92, 92, 230], { $0.mixer.luminance[5] = 60 }, [142, 142, 248]),
            ("blue primary saturation −60", [92, 92, 230], { $0.calibration.blueSaturation = -60 }, [149, 149, 226]),
            ("red primary hue +60", [230, 92, 92], { $0.calibration.redHue = 60 }, [228, 118, 37]),
            ("darks −60", [130, 130, 130], { $0.curve.darks = -60 }, [101, 101, 101]),
        ]
        for (name, input, adjust, expected) in cases {
            let got = try applied(input, adjust)
            #expect(near(got, expected), "\(name): \(got), Photoshop \(expected)")
        }
        // Vignettes on mid gray, 3:2, at a corner: the lens correction brightens it to 223, the post-crop one at −60
        // darkens it to 30.
        let wide = try image(width: 300, height: 200, red: 128 / 255, green: 128 / 255, blue: 128 / 255)
        var lens = CameraRawSettings()
        lens.optics.vignetteAmount = 100
        #expect(abs(try pixels(lens.apply(wide))[0][0] - 223) <= 6)
        var postCrop = CameraRawSettings()
        postCrop.vignetteAmount = -60
        #expect(abs(try pixels(postCrop.apply(wide))[0][0] - 30) <= 6)
    }

    @Test func vibranceFavorsDullColorsAndProtectsSkinWhileSaturationDoesNot() throws {
        let dullGreen = try image(red: 77 / 255, green: 153 / 255, blue: 77 / 255)
        let saturatedGreen = try image(red: 20 / 255, green: 200 / 255, blue: 20 / 255)
        let skin = try image(red: 153 / 255, green: 115 / 255, blue: 77 / 255)
        var settings = CameraRawSettings()
        settings.vibrance = 100
        let dullBefore = try chroma(pixels(dullGreen)[0])
        let saturatedBefore = try chroma(pixels(saturatedGreen)[0])
        let skinBefore = try chroma(pixels(skin)[0])
        let dullDelta = try chroma(pixels(settings.apply(dullGreen))[0]) - dullBefore
        let saturatedDelta = try chroma(pixels(settings.apply(saturatedGreen))[0]) - saturatedBefore
        let skinDelta = try chroma(pixels(settings.apply(skin))[0]) - skinBefore
        #expect(dullDelta > saturatedDelta + 10, "dull \(dullDelta) vs saturated \(saturatedDelta)")
        #expect(dullBefore == skinBefore)
        #expect(dullDelta > skinDelta + 10, "skin is protected at the same saturation: \(skinDelta) vs \(dullDelta)")

        let red = try image(red: 160 / 255, green: 120 / 255, blue: 120 / 255)
        let blue = try image(red: 100 / 255, green: 100 / 255, blue: 140 / 255)
        settings = CameraRawSettings()
        settings.saturation = 100
        let redBefore = try chroma(pixels(red)[0])
        let blueBefore = try chroma(pixels(blue)[0])
        let redAfter = try chroma(pixels(settings.apply(red))[0])
        let blueAfter = try chroma(pixels(settings.apply(blue))[0])
        let redRatio = Double(redAfter) / Double(redBefore)
        let blueRatio = Double(blueAfter) / Double(blueBefore)
        // Photoshop doubles chroma in linear light, which is a little less in sRGB values, and less again for blue.
        #expect(abs(redRatio - 1.85) < 0.15 && abs(blueRatio - 1.73) < 0.15, "saturation raises both: \(redRatio), \(blueRatio)")
    }

    @Test func eyedropperAndAutoNeutralizeAWarmPixel() throws {
        let straightRed = 160.0 / 255
        let straightGreen = 140.0 / 255
        let straightBlue = 120.0 / 255
        let warm = try image(width: 8, height: 8, red: straightRed, green: straightGreen, blue: straightBlue)
        let before = try pixels(warm)[0]
        let solved = try #require(CameraRawSettings.neutralize(straightRed: straightRed, green: straightGreen, blue: straightBlue))
        var settings = CameraRawSettings()
        settings.temperature = solved.temperature
        settings.tint = solved.tint
        let neutral = try pixels(settings.apply(warm))[0]
        #expect(chroma(neutral) < chroma(before) / 2, "eyedropper pulls the cast in: \(before) → \(neutral)")

        let auto = try #require(CameraRawSettings.autoBalance(of: warm))
        settings.temperature = auto.temperature
        settings.tint = auto.tint
        let averaged = try pixels(settings.apply(warm))[0]
        #expect(chroma(averaged) < chroma(before) / 2, "auto matches the solid color: \(averaged)")

        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(ImportedImage(image: warm, thumbnail: warm, name: "Warm"))
        session.beginFilter(.cameraRaw)
        let edit = try #require(session.filterEdit)
        edit.samplesWhiteBalance = true
        session.sampleCameraRawWhiteBalance(at: CGPoint(x: 1, y: 1))
        #expect(edit.settings.cameraRaw.whiteBalance == .custom)
        #expect(edit.settings.cameraRaw.temperature != 0 || edit.settings.cameraRaw.tint != 0)
        let sampled = try pixels(edit.renderSettings().cameraRaw.apply(warm))[0]
        #expect(chroma(sampled) < chroma(before) / 2, "the canvas sample neutralizes: \(sampled)")

        session.cancelFilter()
        let clear = try image(width: 8, height: 8, red: 1, green: 0, blue: 0, alpha: 0)
        let empty = EditorSession()
        empty.createDocument(width: 8, height: 8)
        empty.insert(ImportedImage(image: clear, thumbnail: clear, name: "Clear"))
        empty.beginFilter(.cameraRaw)
        let untouched = try #require(empty.filterEdit).settings
        empty.filterEdit?.samplesWhiteBalance = true
        empty.sampleCameraRawWhiteBalance(at: CGPoint(x: 1, y: 1))
        #expect(empty.filterEdit?.settings == untouched, "a transparent pixel is ignored")
    }

    /// Auto stores its mode, then fills Temperature and Tint from the layer once the scan finishes.
    @Test func autoWhiteBalanceNeutralizesAfterTheScan() async throws {
        let straightRed = 160.0 / 255
        let straightGreen = 140.0 / 255
        let straightBlue = 120.0 / 255
        let warm = try image(width: 8, height: 8, red: straightRed, green: straightGreen, blue: straightBlue)
        let before = try pixels(warm)[0]
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(ImportedImage(image: warm, thumbnail: warm, name: "Warm"))
        session.beginFilter(.cameraRaw)
        await session.applyCameraRawAutoWhiteBalance()
        let raw = try #require(session.filterEdit).settings.cameraRaw
        #expect(raw.whiteBalance == .auto)
        let averaged = try pixels(raw.apply(warm))[0]
        #expect(chroma(averaged) < chroma(before) / 2, "auto neutralizes after the scan: \(averaged)")

        session.cancelFilter()
        let clear = try image(width: 8, height: 8, red: 1, green: 0, blue: 0, alpha: 0)
        let empty = EditorSession()
        empty.createDocument(width: 8, height: 8)
        empty.insert(ImportedImage(image: clear, thumbnail: clear, name: "Clear"))
        empty.beginFilter(.cameraRaw)
        await empty.applyCameraRawAutoWhiteBalance()
        let untouched = try #require(empty.filterEdit).settings.cameraRaw
        #expect(untouched.whiteBalance == .auto)
        #expect(untouched.temperature == 0 && untouched.tint == 0, "a layer with no coverage leaves the sliders alone")
    }

    @Test func hiddenGroupIsLeftOutAndOkIsOneUndoOrNone() async throws {
        let input = try gray(width: 8, height: 8)
        var settings = CameraRawSettings()
        settings.exposure = 1
        settings.temperature = 40
        let hiddenLight = settings.applying(showsLight: false, showsColor: true)
        let colorOnly = try pixels(hiddenLight.apply(input))
        let source = try pixels(input)
        #expect(colorOnly != source)
        #expect(hiddenLight.exposure == 0 && hiddenLight.temperature == 40)
        let neither = settings.applying(showsLight: false, showsColor: false)
        #expect(neither.isIdentity)
        #expect(try pixels(neither.apply(input)) == source)

        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(ImportedImage(image: input, thumbnail: input, name: "Gray"))
        session.beginFilter(.cameraRaw)
        let original = try pixels(input)
        var count = session.history.undoCount
        await session.commitFilter()
        #expect(session.filterEdit == nil && session.history.undoCount == count, "an unchanged grade is not an edit")
        #expect(try pixels(try #require(session.activeLayer?.asset?.image)) == original)

        session.beginFilter(.cameraRaw)
        var editSettings = try #require(session.filterEdit).settings
        editSettings.cameraRaw.exposure = 1
        session.updateFilter(editSettings, preview: true)
        session.filterEdit?.showsCameraRawLight = false
        count = session.history.undoCount
        await session.commitFilter()
        #expect(session.history.undoCount == count, "an eye turned off drops that group")
        #expect(try pixels(try #require(session.activeLayer?.asset?.image)) == original)

        session.beginFilter(.cameraRaw)
        editSettings = try #require(session.filterEdit).settings
        editSettings.cameraRaw.exposure = 1
        session.updateFilter(editSettings, preview: true)
        session.cancelFilter()
        #expect(session.filterEdit == nil)
        #expect(try pixels(try #require(session.activeLayer?.asset?.image)) == original)

        session.beginFilter(.cameraRaw)
        editSettings = try #require(session.filterEdit).settings
        editSettings.cameraRaw.exposure = 1
        session.updateFilter(editSettings, preview: true)
        count = session.history.undoCount
        await session.commitFilter()
        #expect(session.history.undoCount == count + 1 && session.history.undoName == "Camera Raw 滤镜")
        let baked = try pixels(try #require(session.activeLayer?.asset?.image))[0]
        #expect(abs(baked[0] - 181) <= 2, "OK bakes the grade: \(baked)")
    }

    /// OK stores the grade the eye left in the layer. A hidden slider must not come back on the next open.
    @Test func hiddenGroupStaysOutOfTheNextOpen() async throws {
        let input = try gray(width: 8, height: 8)
        let session = EditorSession()
        session.createDocument(width: 8, height: 8)
        session.insert(ImportedImage(image: input, thumbnail: input, name: "Gray"))
        session.beginFilter(.cameraRaw)
        var editSettings = try #require(session.filterEdit).settings
        editSettings.cameraRaw.exposure = 1
        editSettings.cameraRaw.temperature = 40
        session.updateFilter(editSettings, preview: true)
        session.filterEdit?.showsCameraRawLight = false
        await session.commitFilter()
        let baked = try pixels(try #require(session.activeLayer?.asset?.image))
        let source = try pixels(input)
        #expect(baked != source)

        session.beginFilter(.cameraRaw)
        let restored = try #require(session.filterEdit).settings.cameraRaw
        #expect(restored.exposure == 0)
        #expect(restored.temperature == 40)
        session.cancelFilter()
    }

    /// A wide step from 40 to 200, so a small blur and a wide blur reach different pixels.
    /// A checkerboard, for the geometry and optics tests: a warp moves pixels, so it can only be seen
    /// in an image whose pixels differ. A flat fill comes back byte-identical however hard it is bent.
    private func checker(_ width: Int = 24, _ height: Int = 24) throws -> CGImage {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        for y in 0..<height {
            for x in 0..<width {
                let light = ((x / 2) + (y / 2)) % 2 == 0
                context.setFillColor(CGColor(srgbRed: light ? 0.9 : 0.1, green: light ? 0.9 : 0.1,
                                             blue: light ? 0.9 : 0.1, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return try #require(context.makeImage())
    }

    private func step() throws -> CGImage {
        let width = 24
        let context = try BrushRaster.context(width: width, height: 4, mask: false)
        context.setFillColor(CGColor(srgbRed: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 4))
        context.setFillColor(CGColor(srgbRed: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1))
        context.fill(CGRect(x: 12, y: 0, width: 12, height: 4))
        return try #require(context.makeImage())
    }

    private func byte(_ image: CGImage, x: Int) throws -> Int {
        try pixels(image)[x][0]
    }

    @Test func textureAndClaritySharpenAnEdgeAndLeaveAFlatField() throws {
        let flat = try gray()
        let flatPixels = try pixels(flat)
        var settings = CameraRawSettings()
        settings.texture = 100
        settings.clarity = 100
        let flatResult = try pixels(settings.apply(flat))
        #expect(flatResult == flatPixels, "a flat field has no local contrast")

        let edge = try step()
        let originalFar = try byte(edge, x: 0)
        let originalNear = try byte(edge, x: 8)
        let originalEdge = try byte(edge, x: 11)
        settings = CameraRawSettings()
        settings.texture = 100
        let textured = try settings.apply(edge)
        #expect(try byte(textured, x: 0) == originalFar)
        #expect(try byte(textured, x: 8) == originalNear, "texture's fine radius does not reach this far")
        #expect(try byte(textured, x: 11) != originalEdge)

        settings = CameraRawSettings()
        settings.clarity = 100
        let clarified = try settings.apply(edge)
        #expect(try byte(clarified, x: 0) == originalFar)
        #expect(try byte(clarified, x: 8) != originalNear, "clarity's wider radius reaches further in")
        settings.clarity = -100
        let softened = try settings.apply(edge)
        let hardBright = try byte(edge, x: 12)
        let hardDark = try byte(edge, x: 11)
        let softBright = try byte(softened, x: 12)
        let softDark = try byte(softened, x: 11)
        let hardGap = abs(hardBright - hardDark)
        let softGap = abs(softBright - softDark)
        #expect(softGap < hardGap, "negative clarity pulls the step together: \(softGap) vs \(hardGap)")
    }

    /// Dehaze takes away, or adds, the haze of a picture's brightest part: a shadow under a pale sky deepens or lifts.
    /// A picture of one color has no haze to find, and Photoshop leaves it be.
    @Test func dehazeDeepensOrLiftsAndKeepsAlpha() throws {
        let context = try BrushRaster.context(width: 10, height: 10, mask: false)
        context.setFillColor(CGColor(srgbRed: 200 / 255, green: 195 / 255, blue: 190 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
        context.setFillColor(CGColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        let skyAndShadow = try #require(context.makeImage())
        let index = try #require(try pixels(skyAndShadow).firstIndex { $0[0] == 30 })
        var settings = CameraRawSettings()
        settings.dehaze = 100
        let deepened = try pixels(settings.apply(skyAndShadow))[index]
        #expect(deepened[0] < 30, "positive dehaze deepens the shadow: \(deepened)")
        settings.dehaze = -100
        let lifted = try pixels(settings.apply(skyAndShadow))[index]
        #expect(lifted[0] > 30, "negative dehaze lifts it: \(lifted)")
        let pale = try image(red: 180 / 255, green: 150 / 255, blue: 150 / 255)
        for amount in [100.0, -100.0] {
            settings.dehaze = amount
            let kept = try pixels(settings.apply(pale))[0]
            #expect(kept == [180, 150, 150, 255], "one color is left be at \(amount): \(kept)")
        }
        let translucent = try image(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 0.5)
        let translucentAlpha = try pixels(translucent)[0][3]
        settings.dehaze = 100
        let dehazedAlpha = try pixels(settings.apply(translucent))[0][3]
        #expect(dehazedAlpha == translucentAlpha)
    }

    @Test func glowIsIdleAtZeroAndHalationFringeIsRedderThanDiffusion() throws {
        let context = try BrushRaster.context(width: 21, height: 21, mask: false)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 21, height: 21))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: 5, height: 5))
        let spot = try #require(context.makeImage())
        let spotPixels = try pixels(spot)
        var settings = CameraRawSettings()
        settings.glowWarmth = 100
        settings.glowRange = 100
        let idle = try pixels(settings.apply(spot))
        #expect(idle == spotPixels, "range and warmth do nothing until Glow is raised")

        settings.glow = 100
        settings.glowWarmth = 100
        settings.glowStyle = .diffusion
        let diffusion = try pixels(settings.apply(spot))
        settings.glowStyle = .halation
        let halation = try pixels(settings.apply(spot))
        let fringe = 10 * 21 + 15
        let far = 0
        #expect(diffusion[fringe][0] > diffusion[far][0], "glow brightens the neighborhood: \(diffusion[fringe])")
        #expect(halation[far] == [0, 0, 0, 255])
        let diffusionRed = diffusion[fringe][0] - diffusion[fringe][1]
        let halationRed = halation[fringe][0] - halation[fringe][1]
        #expect(halationRed > diffusionRed, "halation is redder than diffusion at the same warmth: \(halation[fringe]) vs \(diffusion[fringe])")
    }

    @Test func vignetteDarkensCornersAndHighlightsOnlyWhileDarkening() throws {
        let grayField = try gray(width: 9, height: 9)
        var settings = CameraRawSettings()
        settings.vignetteAmount = -100
        let darkened = try pixels(settings.apply(grayField))
        let center = darkened[4 * 9 + 4][0]
        let corner = darkened[0][0]
        #expect(abs(center - 128) <= 2, "the center stays: \(center)")
        #expect(corner < center - 40, "the corner darkens: \(corner)")

        let white = try image(width: 9, height: 9, red: 1, green: 1, blue: 1)
        settings.vignetteHighlights = 100
        settings.vignetteStyle = .highlightPriority
        let protected = try pixels(settings.apply(white))[0][0]
        settings.vignetteHighlights = 0
        let exposed = try pixels(settings.apply(white))[0][0]
        #expect(protected > exposed + 40, "highlights holds a bright corner: \(protected) vs \(exposed)")
        settings.vignetteHighlights = 100
        settings.vignetteStyle = .paintOverlay
        let painted = try pixels(settings.apply(white))[0][0]
        #expect(painted < protected, "paint overlay does not use Highlights: \(painted)")

        settings = CameraRawSettings()
        settings.vignetteAmount = 100
        settings.vignetteHighlights = 0
        let plain = try pixels(settings.apply(grayField))
        settings.vignetteHighlights = 100
        let withHighlights = try pixels(settings.apply(grayField))
        #expect(plain == withHighlights, "highlights is idle while the vignette lightens")
    }

    @Test func grainIsStableAndTheEffectsEyeDropsTheWholeGroup() throws {
        let field = try gray(width: 16, height: 16)
        let fieldPixels = try pixels(field)
        var settings = CameraRawSettings()
        settings.grainSize = 40
        settings.grainRoughness = 80
        let silent = try pixels(settings.apply(field, seed: 4))
        #expect(silent == fieldPixels, "size and roughness do nothing at amount zero")
        settings.grainAmount = 70
        let first = try pixels(settings.apply(field, seed: 4))
        let second = try pixels(settings.apply(field, seed: 4))
        #expect(first == second, "the same seed keeps the same grain")
        #expect(first != fieldPixels)
        #expect(first[0][0] == first[0][1] && first[0][1] == first[0][2], "grain moves brightness only")
        let clear = try image(width: 4, height: 4, red: 0.5, green: 0.5, blue: 0.5, alpha: 0)
        let clearPixels = try pixels(settings.apply(clear, seed: 4))
        #expect(clearPixels[0][3] == 0)

        let edge = try step()
        let edgePixels = try pixels(edge)
        settings = CameraRawSettings()
        settings.texture = 100
        settings.grainAmount = 50
        let shown = try pixels(settings.apply(edge, seed: 2))
        let hidden = settings.applying(showsLight: true, showsColor: true, showsEffects: false)
        let hiddenPixels = try pixels(hidden.apply(edge, seed: 2))
        #expect(hidden.isIdentity)
        #expect(hiddenPixels == edgePixels)
        #expect(shown != edgePixels)
    }

    @Test func histogramFollowsTheGradeAndClippingPaintStaysOffTheResult() throws {
        let black = try image(red: 0, green: 0, blue: 0)
        let white = try image(red: 1, green: 1, blue: 1)
        let blackScope = try #require(CameraRawScope.make(black))
        let whiteScope = try #require(CameraRawScope.make(white))
        #expect(peakIndex(blackScope.red) == 0)
        #expect(peakIndex(whiteScope.red) == 255)
        var settings = CameraRawSettings()
        settings.exposure = 1
        let shifted = try #require(CameraRawScope.make(settings.apply(try gray())))
        #expect(peakIndex(shifted.red) > 128, "exposure moves the midtones toward white")

        let shadowed = try pixels(CameraRawScope.overlay(black, shadows: true, highlights: false))[0]
        #expect(shadowed[2] > shadowed[0], "clipped shadows are painted blue: \(shadowed)")
        let highlighted = try pixels(CameraRawScope.overlay(white, shadows: false, highlights: true))[0]
        #expect(highlighted[0] > highlighted[2], "clipped highlights are painted red: \(highlighted)")
        let untouched = try pixels(CameraRawScope.overlay(black, shadows: false, highlights: false))
        let originalBlack = try pixels(black)
        #expect(untouched == originalBlack)

        let red = try image(red: 1, green: 0, blue: 0)
        let scope = try #require(CameraRawScope.make(red))
        let hottest = scope.vectorscope.enumerated().max { $0.element < $1.element }?.offset ?? 0
        #expect(hottest % CameraRawScope.scopeSide > CameraRawScope.scopeSide / 2, "red sits on the right of the vectorscope")
    }

    @Test func scopeSamplingChangesAtFourMegapixelsWithoutChangingColors() throws {
        // The C kernel divides rows among 16 bands, rounding each band's sample count up.
        for (width, height, count) in [(2000, 2000, 256_000), (2001, 2000, 64_256)] {
            let red = try image(width: width, height: height, red: 1, green: 0, blue: 0)
            let scope = try #require(CameraRawScope.make(red))
            #expect(scope.red[255] == Double(count))
            #expect(scope.green[0] == Double(count) && scope.blue[0] == Double(count))
            #expect(scope.red.reduce(0, +) == Double(count))
            #expect(scope.vectorscope.reduce(0, +) == Double(count))
        }
    }

    @Test func curveMixerAndGradingChangeOnlyTheirOwnTones() throws {
        let dark = try image(red: 0.12, green: 0.12, blue: 0.12)
        let light = try image(red: 0.62, green: 0.62, blue: 0.62)
        var settings = CameraRawSettings()
        settings.curve.shadows = 100
        let darkGain = try pixels(settings.apply(dark))[0][0] - Int((0.12 * 255).rounded())
        let lightGain = try pixels(settings.apply(light))[0][0] - Int((0.62 * 255).rounded())
        #expect(darkGain > lightGain + 8, "parametric shadows lift the dark tone more: \(darkGain) vs \(lightGain)")

        settings = CameraRawSettings()
        settings.curve.rgb = CameraRawCurveSettings.strongContrast
        let contrasted = try pixels(settings.apply(image(red: 0.25, green: 0.25, blue: 0.25)))[0][0]
        #expect(contrasted < 55, "strong contrast pulls a dark midtone down: \(contrasted)")

        settings = CameraRawSettings()
        settings.mixer.hue[0] = 100
        let shifted = try pixels(settings.apply(image(red: 1, green: 0, blue: 0)))[0]
        #expect(shifted[1] > shifted[2], "reds hue moves red toward orange: \(shifted)")

        settings = CameraRawSettings()
        settings.grading.shadows.saturation = 100
        let gradedDark = try pixels(settings.apply(dark))[0]
        let gradedLight = try pixels(settings.apply(image(red: 1, green: 1, blue: 1)))[0]
        #expect(gradedDark[0] > gradedDark[1] + 5, "shadow grading tints a dark pixel: \(gradedDark)")
        #expect(abs(gradedLight[0] - gradedLight[1]) <= 2, "and leaves white alone: \(gradedLight)")
        settings.grading.balance = 100
        let balanced = try pixels(settings.apply(dark))[0]
        #expect(balanced[0] - balanced[1] < gradedDark[0] - gradedDark[1], "balance toward highlights weakens the shadow tint")

        settings = CameraRawSettings()
        settings.curve.shadows = 100
        let hidden = settings.applying(showsLight: true, showsColor: true, showsCurve: false)
        #expect(try pixels(hidden.apply(dark)) == pixels(dark))
    }

    /// The parametric curve is one smooth, rising curve with fixed ends, as Camera Raw's is: no kinks at the dividers.
    @Test func parametricCurveIsSmooth() {
        var curve = CameraRawCurveSettings()
        #expect(curve.parametric(0.3) == 0.3)
        for amounts in [(100.0, 0.0, 0.0, 0.0), (0, 100, -100, 0), (-100, 50, 100, -60)] {
            (curve.shadows, curve.darks, curve.lights, curve.highlights) = amounts
            let samples = (0...200).map { curve.parametric(Double($0) / 200) }
            #expect(samples.first == 0 && samples.last == 1, "\(amounts): the ends stay black and white")
            #expect(zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 }, "\(amounts): the curve keeps rising")
            // Smooth: sampled twice as finely, the largest step-to-step change of slope about halves. At a corner, where
            // one region stopped dead and the next began, it stays the same however finely it's sampled.
            func jump(_ steps: Int) -> Double {
                let values = (0...steps).map { curve.parametric(Double($0) / Double(steps)) }
                let slopes = zip(values, values.dropFirst()).map { ($1 - $0) * Double(steps) }
                return zip(slopes, slopes.dropFirst()).map { abs($1 - $0) }.max() ?? 0
            }
            #expect(jump(400) < jump(200) * 0.7, "\(amounts): a corner in the curve")
        }
        curve = CameraRawCurveSettings()
        curve.darks = 100
        let before = curve.parametric(0.4)
        curve.darkSplit = 70
        #expect(curve.parametric(0.4) > before, "widening the darks region spreads its lift")
    }

    /// Darks −51 and Lights +59 give Photoshop's curve, traced from Camera Raw 18.6 at the default dividers.
    @Test func parametricCurveMatchesPhotoshop() {
        var curve = CameraRawCurveSettings()
        curve.darks = -51
        curve.lights = 59
        let photoshop: [(Double, Double)] = [(0.093, 0.011), (0.192, 0.089), (0.267, 0.174), (0.367, 0.310), (0.491, 0.498),
                                             (0.616, 0.698), (0.690, 0.804), (0.765, 0.886), (0.840, 0.947), (0.915, 0.982)]
        for (tone, expected) in photoshop {
            #expect(abs(curve.parametric(tone) - expected) < 0.035, "at \(tone): \(curve.parametric(tone)), Photoshop \(expected)")
        }
    }

    /// Like Photoshop's, the curve works on red, green and blue alike, so an S-curve deepens an orange toward red as it
    /// adds contrast; Refine Saturation at −100 keeps it to brightness, leaving the color's balance as it was.
    @Test func curveDeepensColorLikePhotoshop() throws {
        let orange = try image(red: 0.85, green: 0.35, blue: 0.1)
        var settings = CameraRawSettings()
        settings.curve.darks = -51
        settings.curve.lights = 59
        let curved = try pixels(settings.apply(orange))[0]
        #expect(curved[0] > 230 && curved[1] < 80, "red up and green down, as Photoshop's: \(curved)")
        settings.curve.refineSaturation = -100
        let brightness = try pixels(settings.apply(orange))[0]
        #expect(Double(brightness[1]) / Double(brightness[0]) > 0.35, "brightness only keeps orange orange: \(brightness)")
    }

    @Test func detailSharpeningNoiseAndMaskingPreview() throws {
        let edge = try step()
        var settings = CameraRawSettings()
        settings.detail.sharpenAmount = 150
        settings.detail.sharpenRadius = 50
        let sharpened = try settings.apply(edge)
        let before = try pixels(edge)
        let after = try pixels(sharpened)
        #expect(before != after, "sharpening changes the step image")

        settings = CameraRawSettings()
        settings.detail.noiseLuminance = 80
        let flat = try gray(width: 8, height: 8)
        let smoothedFlat = try pixels(settings.apply(flat))
        let flatPixels = try pixels(flat)
        #expect(smoothedFlat == flatPixels, "luminance NR leaves a flat field alone")

        settings.detail.sharpenMasking = 50
        let mask = try settings.apply(edge, sharpenMask: true)
        let maskPixels = try pixels(mask)
        #expect(maskPixels.allSatisfy { $0[0] == $0[1] && $0[1] == $0[2] }, "mask preview is grayscale")
        #expect(settings.detail.adjusts)
    }

    @Test func opticsDistortionDefringeAndDetailEye() throws {
        let stepped = try checker()
        var settings = CameraRawSettings()
        settings.optics.distortion = 100
        let warped = try settings.apply(stepped)
        let warpedPixels = try pixels(warped)
        let steppedPixels = try pixels(stepped)
        // Not the step image: its one edge sits at the centre, where a radial distortion moves nothing.
        #expect(warpedPixels != steppedPixels, "distortion resamples pixels")

        let purple = try image(red: 0.8, green: 0.2, blue: 0.9)
        let purpleBefore = try pixels(purple)[0]
        settings = CameraRawSettings()
        settings.optics.purpleAmount = 100
        settings.optics.purpleHueLow = 250
        settings.optics.purpleHueHigh = 320
        let defringed = try pixels(settings.apply(purple))[0]
        #expect(chroma(defringed) < chroma(purpleBefore), "purple defringe lowers chroma")

        settings = CameraRawSettings()
        settings.optics.removeChromaticAberration = true
        #expect(settings.optics.adjusts)
        settings = CameraRawSettings()
        settings.detail.sharpenAmount = 40
        let hidden = settings.applying(showsLight: true, showsColor: true, showsDetail: false)
        let edgeImage = try step()
        let original = try pixels(edgeImage)
        let preview = try pixels(hidden.apply(edgeImage))
        #expect(preview == original)
    }

    @Test func geometryWarpAndCalibrationPrimaries() throws {
        let grid = try checker(12, 12)
        var settings = CameraRawSettings()
        settings.geometry.vertical = 40
        let warped = try settings.geometry.apply(grid)
        let warpedPixels = try pixels(warped)
        let gridPixels = try pixels(grid)
        #expect(warpedPixels != gridPixels)

        settings = CameraRawSettings()
        settings.calibration.redHue = 80
        let red = try image(red: 1, green: 0, blue: 0)
        let before = try pixels(red)[0]
        let after = try pixels(settings.apply(red))[0]
        #expect(after != before, "calibration shifts a pure red: \(before) → \(after)")

        settings.calibration.redHue = 80
        let hidden = settings.applying(showsLight: true, showsColor: true, showsCalibration: false)
        let hiddenPixels = try pixels(hidden.apply(red))
        #expect(hiddenPixels[0] == before)
    }

    /// Upright is Off or Guided. Guided reads a drawn line; without one it must not invent a warp,
    /// and two different pictures must not receive one shared result.
    @Test func guidedUprightFollowsADrawnLineAndLeavesAnUnguidedPicture() throws {
        #expect(Set(CameraRawUprightMode.allCases) == [.off, .guided])
        let cool = try image(width: 16, height: 16, red: 0.2, green: 0.45, blue: 0.8)
        let warm = try image(width: 16, height: 16, red: 0.85, green: 0.25, blue: 0.15)
        let coolPixels = try pixels(cool)
        let warmPixels = try pixels(warm)
        var settings = CameraRawSettings()
        settings.geometry.upright = .guided
        #expect(try pixels(settings.apply(cool)) == coolPixels)
        #expect(try pixels(settings.apply(warm)) == warmPixels)

        settings.geometry.guides = [CameraRawGeometryGuide(startX: 0.1, startY: 0.15, endX: 0.9, endY: 0.8)]
        let coolGuided = try pixels(settings.apply(cool))
        let warmGuided = try pixels(settings.apply(warm))
        #expect(coolGuided != coolPixels)
        #expect(warmGuided != warmPixels)
        #expect(coolGuided != warmGuided)
    }

    private func peakIndex(_ bins: [Double]) -> Int {
        bins.enumerated().max { $0.element < $1.element }?.offset ?? -1
    }

    /// Color noise reduction blurs a saturation plane in which clear pixels must count as zero, as the luma plane's
    /// do. Left unwritten, they held whatever that memory held before, so the pixels beside a clear area changed from
    /// run to run.
    @Test func colorNoiseReductionIgnoresWhatClearPixelsHeld() throws {
        var settings = CameraRawSettings()
        settings.detail.noiseColor = 60
        let context = try BrushRaster.context(width: 97, height: 61, mask: false)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<61 {
            for x in 0..<97 {
                let p = y * context.bytesPerRow + x * 4
                let alpha = x < 30 ? 0 : 255
                bytes[p] = UInt8((x * 7 + y * 3) % 256 * alpha / 255); bytes[p + 1] = UInt8((x * x + y * 5) % 256 * alpha / 255)
                bytes[p + 2] = UInt8((x * 2 + y * y) % 256 * alpha / 255); bytes[p + 3] = UInt8(alpha)
            }
        }
        let picture = try #require(context.makeImage())
        func pixels(_ image: CGImage) throws -> Data { try #require(image.dataProvider?.data) as Data }
        let first = try pixels(try settings.apply(picture))
        // Leaves saturation values in freed memory the size of the kernel's planes.
        let red = try BrushRaster.context(width: 97, height: 61, mask: false)
        red.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 1))
        red.fill(CGRect(x: 0, y: 0, width: 97, height: 61))
        let saturated = try #require(red.makeImage())
        for _ in 0..<4 { _ = try settings.apply(saturated) }
        #expect(try pixels(try settings.apply(picture)) == first)
    }

    /// Color noise reduction takes the random color out of grain and keeps its brightness: speckle of every hue over
    /// a gray goes most of the way back to the gray at 100. Blurring saturation alone, each speck kept its own hue and
    /// the speckle stayed.
    @Test func colorNoiseReductionRemovesColorGrainNotBrightness() throws {
        let context = try BrushRaster.context(width: 120, height: 120, mask: false)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 12345
        for y in 0..<120 { for x in 0..<120 {
            let p = y * context.bytesPerRow + x * 4
            for c in 0..<3 { seed = seed &* 1664525 &+ 1013904223; bytes[p + c] = UInt8(64 + Int(seed >> 25)) }
            bytes[p + 3] = 255
        } }
        let grain = try #require(context.makeImage())
        func measure(_ image: CGImage) throws -> (color: Double, brightness: Double) {
            let copy = try BrushRaster.copy(image)
            let d = try #require(copy.data).assumingMemoryBound(to: UInt8.self)
            var color = 0.0, brightness = 0.0
            for y in 10..<110 { for x in 10..<110 {
                let p = y * copy.bytesPerRow + x * 4
                let r = Double(d[p]), g = Double(d[p + 1]), b = Double(d[p + 2])
                color += max(r, g, b) - min(r, g, b); brightness += 0.2126 * r + 0.7152 * g + 0.0722 * b
            } }
            return (color / 10_000, brightness / 10_000)
        }
        var settings = CameraRawSettings()
        let before = try measure(settings.apply(grain))
        settings.detail.noiseColor = 100
        let after = try measure(settings.apply(grain))
        #expect(after.color < before.color * 0.25, "color speckle \(before.color) → \(after.color)")
        #expect(abs(after.brightness - before.brightness) < 1, "brightness \(before.brightness) → \(after.brightness)")
    }

    /// Shadows and Highlights keep tones in order: a gray ramp from black to white still rises after either at ±100,
    /// with black and white where they were. Shadows +100 once lifted black to middle gray, above the tones over it,
    /// and lifted dark areas broke into blotches of color.
    /// Shadows adapts to the picture as Photoshop's does, measured on a made-up landscape (value noise over seven octaves
    /// from a fixed seed: a cloudy sky brightening upward over dark textured ground) against Photoshop's own renders of
    /// exactly these pictures. A picture under about 1020 pixels on its long side gets Photoshop's gentler treatment of
    /// small pictures, which ours follows less closely.
    @Test func shadowsAdaptsToThePictureAsPhotoshopDoes() throws {
        struct Noise {
            var state: UInt64
            mutating func unit() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(1 << 53)
            }
        }
        func field(_ width: Int, _ height: Int, seed: UInt64) -> [Double] {
            var out = [Double](repeating: 0, count: width * height), noise = Noise(state: seed), amplitude = 1.0, total = 0.0
            for octave in 0..<7 {
                let cell = max(1, max(width, height) >> (octave + 2)), gw = width / cell + 2, gh = height / cell + 2
                let grid = (0..<(gw * gh)).map { _ in noise.unit() }
                for y in 0..<height { for x in 0..<width {
                    let fx = Double(x) / Double(cell), fy = Double(y) / Double(cell), x0 = Int(fx), y0 = Int(fy)
                    let tx = fx - Double(x0), ty = fy - Double(y0)
                    let top = grid[y0 * gw + x0] * (1 - tx) + grid[y0 * gw + x0 + 1] * tx
                    let bottom = grid[(y0 + 1) * gw + x0] * (1 - tx) + grid[(y0 + 1) * gw + x0 + 1] * tx
                    out[y * width + x] += amplitude * (top * (1 - ty) + bottom * ty)
                } }
                total += amplitude
                amplitude *= 0.6
            }
            return out.map { $0 / total }
        }
        func landscape(width: Int) throws -> CGImage {
            let height = width * 2 / 3
            let clouds = field(width, height, seed: 1), lay = field(width, height, seed: 2)
            let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            // Memory row 0 is the top of the picture. The horizon wanders with the second field.
            for y in 0..<height { for x in 0..<width {
                let i = y * width + x
                let horizon = Double(height) * (0.5 + 0.25 * (lay[x] - 0.5))
                let sky = 140 + 80 * (1 - Double(y) / horizon) + 60 * (clouds[i] - 0.5)
                let ground = 4 + 70 * pow(clouds[i], 2.2) + 20 * (lay[i] - 0.5)
                let value = UInt8(max(0, min(255, (Double(y) < horizon ? sky : ground).rounded())))
                bytes[i * 4] = value; bytes[i * 4 + 1] = value; bytes[i * 4 + 2] = value; bytes[i * 4 + 3] = 255
            } }
            return try #require(context.makeImage())
        }
        /// The bottom fifth's mean, all ground, and the top fifth's, all sky.
        func means(_ image: CGImage) throws -> (ground: Double, sky: Double) {
            let context = try BrushRaster.context(width: image.width, height: image.height, mask: false)
            BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            func mean(_ rows: Range<Int>) -> Double {
                var sum = 0.0
                for y in rows { for x in 0..<image.width { sum += Double(bytes[y * context.bytesPerRow + x * 4 + 1]) } }
                return sum / Double(rows.count * image.width)
            }
            return (mean((image.height * 4 / 5)..<image.height), mean(0..<(image.height / 5)))
        }
        // Width, Shadows, Photoshop's ground and sky, and how near ours must be. Unchanged: ground 19.7, sky 204.7.
        let cases: [(Int, Double, Double, Double, Double)] = [
            (1200, 100, 59.0, 205.9, 4), (1200, 50, 34.9, 205.3, 4), (1200, -100, 4.2, 203.6, 4),
            (600, 100, 51.0, 205.8, 10), (600, 50, 32.2, 205.2, 4), (600, -100, 5.5, 203.6, 4),
        ]
        for (width, amount, ground, sky, tolerance) in cases {
            var settings = CameraRawSettings()
            settings.shadows = amount
            let result = try means(settings.apply(try landscape(width: width)))
            #expect(abs(result.ground - ground) <= tolerance, "\(width) wide, Shadows \(amount): ground \(result.ground), Photoshop \(ground)")
            #expect(abs(result.sky - sky) <= 2, "\(width) wide, Shadows \(amount): sky \(result.sky), Photoshop \(sky)")
        }
    }

    @Test func shadowsAndHighlightsKeepTonesInOrder() throws {
        let ramp = try BrushRaster.context(width: 256, height: 1, mask: false)
        for x in 0..<256 {
            let level = CGFloat(x) / 255
            ramp.setFillColor(CGColor(srgbRed: level, green: level, blue: level, alpha: 1))
            ramp.fill(CGRect(x: x, y: 0, width: 1, height: 1))
        }
        let image = try #require(ramp.makeImage())
        func levels(shadows: Double, highlights: Double) throws -> [Int] {
            var settings = CameraRawSettings()
            settings.shadows = shadows
            settings.highlights = highlights
            let row: [[Int]] = try pixels(settings.apply(image))
            return row.map { $0[1] }
        }
        for (shadows, highlights) in [(100.0, 0.0), (-100.0, 0.0), (0.0, 100.0), (0.0, -100.0)] {
            let out = try levels(shadows: shadows, highlights: highlights)
            let rising = zip(out, out.dropFirst()).allSatisfy { pair in pair.1 >= pair.0 }
            #expect(rising, "shadows \(shadows), highlights \(highlights): tones out of order")
            // Photoshop's Highlights −100 brings white down to 239 on this ramp; everything else keeps it.
            #expect(out[0] <= 2 && out[255] >= (highlights < 0 ? 235 : 253), "black \(out[0]), white \(out[255])")
        }
        let lifted = try levels(shadows: 100, highlights: 0)
        #expect(lifted[45] >= 45 + 12, "shadows +100 lifts the dark tones: 45 → \(lifted[45])")
    }

    private func largePreviewSession() throws -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 3000, height: 16, emptyLayer: true)
        let context = try BrushRaster.context(width: 3000, height: 16, mask: false)
        // Single-pixel stripes lose detail in the 2048-pixel interactive source.
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 16))
        context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        for x in stride(from: 0, to: 3000, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: 16))
        }
        let input = try #require(context.makeImage())
        session.insert(ImportedImage(image: input, thumbnail: input, name: "Fine detail"))
        session.beginFilter(.cameraRaw)
        return session
    }

    @Test func largeCameraRawPreviewKeepsNativeResolutionAcrossSliderUpdates() async throws {
        let session = try largePreviewSession()
        let edit = try #require(session.filterEdit)
        defer { session.cancelFilter() }
        #expect(edit.previewSource === edit.original.image, "no downsized source or extra full-size copy")
        #expect(edit.previewScale == 1 && edit.previewMapping == edit.mapping)
        #expect(edit.previewBrightness == nil, "opening does not measure full-size pixels on the main thread")
        while let task = edit.previewTask { await task.value }
        let brightness = try #require(edit.previewBrightness)
        let expectedBrightness = CameraRawTables.brightness(of: edit.original.image)
        #expect(brightness.brightest == expectedBrightness.brightest)
        #expect(brightness.logBrightest == expectedBrightness.logBrightest)
        #expect(brightness.luminance == expectedBrightness.luminance)
        #expect(edit.preparedPreview?.width == 3000)
        for exposure in [0.5, -0.5, 1] {
            var settings = edit.settings
            settings.cameraRaw.exposure = exposure
            settings.cameraRaw.contrast = 10
            session.updateFilter(settings, preview: true)
            #expect(edit.preparedPreview?.width == 3000, "the previous sharp preview stays up while rendering")
            while let task = edit.previewTask { await task.value }
            let shown = try #require(edit.preparedPreview)
            #expect(shown.width == 3000 && shown.height == 16)
            let reference = try CameraRawScope.preview(edit.previewJob).image
            #expect(try pixels(shown) == pixels(reference), "the existing renderer is unchanged")
        }
        let shown = try #require(edit.preparedPreview)
        session.updateCameraRawReadout(at: CGPoint(x: 2997.5, y: 8.5))
        let expected = try pixels(shown)[8 * 3000 + 2997]
        #expect(edit.cameraRawReadout?.red == expected[0])
    }

    @Test func nativeCameraRawPreviewsCoalesceSliderChangesAndRespectPreviewOffAndCancel() async throws {
        let session = try largePreviewSession()
        let edit = try #require(session.filterEdit)
        defer { session.cancelFilter() }
        var settings = edit.settings
        for exposure in [0.5, -1, 1.5] {
            settings.cameraRaw.exposure = exposure
            session.updateFilter(settings, preview: true)
        }
        #expect(edit.pending?.settings == settings, "only the latest pending slider settings are kept")
        while let task = edit.previewTask { await task.value }
        let reference = try CameraRawScope.preview(edit.previewJob).image
        let newest = try #require(edit.preparedPreview)
        #expect(try pixels(newest) == pixels(reference))
        #expect(edit.preparedSettings == settings && edit.pending == nil)

        settings.cameraRaw.exposure = -1
        session.updateFilter(settings, preview: true)
        session.updateFilter(settings, preview: false)
        while let task = edit.previewTask { await task.value }
        #expect(edit.preparedPreview == nil && edit.previewImage(for: edit.layerID) == nil)
        session.updateFilter(settings, preview: true)
        let closing = try #require(edit.previewTask)
        session.cancelFilter()
        await closing.value
        #expect(session.filterEdit == nil)
    }
}
