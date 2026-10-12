import CoreGraphics
import Foundation

/// Camera Raw's Light and Color sliders as Photoshop's own Camera Raw Filter draws them: color tables measured from it
/// (Resources/CameraRawTables.bin), each the colors of a 17³ grid after one slider at one value. A value in between
/// blends the two nearest tables. Temperature and Tint, which Camera Raw turns into one white point together, come
/// from a grid of both and blend four. Contrast, Highlights and Shadows adapt to the picture, each to one measure of
/// its brightness, so theirs were measured on backgrounds of seven brightnesses and blend across those too.
nonisolated enum CameraRawTables {
    static let size = 17
    /// The grid the stages are composed onto, finer than the tables so composing adds little blur.
    static let grid = 33
    private static let entries = size * size * size * 3
    /// White balance: a 9 × 9 grid, Temperature by rows and Tint across, each −100…100 by 25. Then Exposure −5…5 by
    /// 0.5; Whites, Blacks, Saturation and Vibrance, each −100…100 by 25; and Contrast, Highlights and Shadows, each
    /// at the seven `brightnesses` by the seven `adaptiveValues`.
    private static let exposureStart = 81, whitesStart = 102, blacksStart = 111, saturationStart = 120, vibranceStart = 129
    private static let contrastStart = 138, highlightsStart = 187, shadowsStart = 236
    /// Then the Color Mixer, luminance, saturation and hue in turn, each for its eight colors (red, orange, yellow,
    /// green, aqua, blue, purple, magenta); Calibration's red, green and blue hue and saturation; and the parametric
    /// curve's Shadows, Darks, Lights and Highlights: each −100…100 by 50.
    private static let mixerStart = 285, calibrationStart = 405, parametricStart = 435
    /// Then Color Grading: its wheels each at twelve hues (0…330 by 30) and saturations 25, 50 and 100 — the shadow and
    /// highlight wheels at Blending 0, then all four (shadows, highlights, midtones, global) at 50, then shadows and
    /// highlights at 100 — and its four luminance sliders (shadows, midtones, highlights, global), −100…100 by 50.
    private static let gradingStart = 455, gradingLuminanceStart = 743, count = 763
    private static let brightnesses: [Double] = [53, 80, 104, 130, 160, 190, 224]
    private static let adaptiveValues: [Double] = [-100, -50, -25, 0, 25, 50, 100]

    /// Every table, red slowest then green then blue, 3 bytes a color. Read once and kept for the app's life.
    static let tables: UnsafeMutablePointer<UInt8>? = load()

    /// The file holds, for each table and channel in turn, each entry's change from no change, in steps of `step` levels
    /// (the rounding is at most a level, within the jitter of Photoshop's own 8-bit renders), as a running difference
    /// from the entry before, packed with LZMA (xz): the tables move smoothly, so this comes to about 1.25 MB.
    private static func load() -> UnsafeMutablePointer<UInt8>? {
        guard let url = Bundle.main.url(forResource: "CameraRawTables", withExtension: "bin"),
              let file = try? Data(contentsOf: url), file.count > 10, file.prefix(4) == Data("CRT3".utf8) else { return nil }
        let header = [UInt8](file.prefix(10))
        func field(_ at: Int) -> Int { Int(header[at]) | Int(header[at + 1]) << 8 }
        let step = field(8)
        guard field(4) == size, field(6) == count, step > 0,
              let planes = try? (file.dropFirst(10) as NSData).decompressed(using: .lzma) as Data,
              planes.count == count * entries else { return nil }
        let tables = UnsafeMutablePointer<UInt8>.allocate(capacity: count * entries)
        let cells = size * size * size
        let level = (0..<size).map { Int((Double($0) * 255 / Double(size - 1)).rounded()) }
        planes.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for table in 0..<count {
                for channel in 0..<3 {
                    let base = (table * 3 + channel) * cells
                    var running: UInt8 = 0
                    for cell in 0..<cells {
                        running &+= bytes[base + cell]
                        let axis = channel == 0 ? cell / (size * size) : channel == 1 ? (cell / size) % size : cell % size
                        let value = level[axis] + Int(Int8(bitPattern: running)) * step
                        tables[table * entries + cell * 3 + channel] = UInt8(min(255, max(0, value)))
                    }
                }
            }
        }
        return tables
    }

    /// Exposure's 21 tables, −5…5 by 0.5, one after another: the lens vignette correction is Exposure by position.
    static var exposureTables: UnsafePointer<UInt8>? { table(exposureStart) }

    private static func table(_ index: Int) -> UnsafePointer<UInt8>? {
        tables.map { UnsafePointer($0 + index * entries) }
    }

    /// A stage from up to eight tables and their weights.
    private static func blend(_ parts: [(UnsafePointer<UInt8>?, Double)]) -> CameraRawStage {
        var stage = CameraRawStage()
        withUnsafeMutableBytes(of: &stage.table) { tables in
            let slots = tables.bindMemory(to: UnsafePointer<UInt8>?.self)
            for (index, part) in parts.prefix(8).enumerated() { slots[index] = part.0 }
        }
        withUnsafeMutableBytes(of: &stage.weight) { weights in
            let slots = weights.bindMemory(to: Float.self)
            for (index, part) in parts.prefix(8).enumerated() { slots[index] = Float(part.1) }
        }
        return stage
    }

    /// The two entries of `points` (rising) either side of `value`, and how far it is between them.
    private static func between(_ value: Double, in points: [Double]) -> (Int, Double) {
        let value = min(points[points.count - 1], max(points[0], value))
        var index = 0
        while index < points.count - 2 && value > points[index + 1] { index += 1 }
        return (index, (value - points[index]) / (points[index + 1] - points[index]))
    }

    /// An adaptive slider at `value`, for a picture whose measure of brightness is `brightness` (sRGB, 0…255): the
    /// four tables around both, blended.
    private static func adaptive(_ start: Int, _ value: Double, brightness: Double) -> CameraRawStage {
        let (row, down) = between(brightness, in: brightnesses)
        let (column, across) = between(value, in: adaptiveValues)
        let width = adaptiveValues.count, base = start + row * width + column
        return blend([(table(base), (1 - down) * (1 - across)), (table(base + 1), (1 - down) * across),
                      (table(base + width), down * (1 - across)), (table(base + width + 1), down * across)])
    }

    /// The two tables either side of `value` on a run of tables `step` apart from `low`, and how far it is between.
    private static func between(_ value: Double, low: Double, step: Double, tables: Int) -> (Int, Double) {
        let position = min(Double(tables - 1), max(0, (value - low) / step))
        let index = min(tables - 2, Int(position))
        return (index, position - Double(index))
    }

    private static func stage(_ start: Int, _ value: Double, low: Double, step: Double, tables: Int) -> CameraRawStage {
        let (index, fraction) = between(value, low: low, step: step, tables: tables)
        return blend([(table(start + index), 1 - fraction), (table(start + index + 1), fraction)])
    }

    /// Temperature and Tint: the four grid tables around them, blended.
    static func whiteBalance(temperature: Double, tint: Double) -> CameraRawStage {
        let (row, down) = between(temperature, low: -100, step: 25, tables: 9)
        let (column, across) = between(tint, low: -100, step: 25, tables: 9)
        return blend([(table(row * 9 + column), (1 - down) * (1 - across)), (table(row * 9 + column + 1), (1 - down) * across),
                      (table((row + 1) * 9 + column), down * (1 - across)), (table((row + 1) * 9 + column + 1), down * across)])
    }

    /// What the adaptive sliders read from the picture before any of them: the mean of each pixel's brightest channel
    /// (Contrast), the mean luminance (Shadows) and the log-average of the brightest channel (Highlights), all in
    /// linear light and given as sRGB levels, 0…255.
    struct Brightness: Sendable {
        var brightest = 128.0, luminance = 128.0, logBrightest = 128.0
    }

    static func brightness(of image: CGImage) -> Brightness {
        guard let context = try? BrushRaster.context(width: image.width, height: image.height, mask: false),
              let data = context.data else { return Brightness() }
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), mask: false, context: context)
        return brightness(data.assumingMemoryBound(to: UInt8.self), width: image.width, height: image.height, stride: context.bytesPerRow)
    }

    static func brightness(_ pixels: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int) -> Brightness {
        var out = [0.0, 0.0, 0.0]
        camera_raw_statistics(pixels, width, height, stride, &out)
        return Brightness(brightest: out[0] * 255, luminance: out[1] * 255, logBrightest: out[2] * 255)
    }

    private static func fifty(_ start: Int, _ value: Double) -> CameraRawStage {
        stage(start, value, low: -100, step: 50, tables: 5)
    }

    /// The stages in Camera Raw's order, leaving out sliders at zero: Calibration, then Light and Color, then the
    /// parametric curve while its dividers are where Photoshop's are measured (with them moved, the curve pass draws it).
    static func stages(for settings: CameraRawSettings, brightness: Brightness) -> [CameraRawStage] {
        var stages: [CameraRawStage] = []
        let calibration = settings.calibration
        for (index, value) in [calibration.redHue, calibration.redSaturation, calibration.greenHue, calibration.greenSaturation,
                               calibration.blueHue, calibration.blueSaturation].enumerated() where value != 0 {
            stages.append(fifty(calibrationStart + index * 5, value))
        }
        if settings.exposure != 0 { stages.append(stage(exposureStart, settings.exposure, low: -5, step: 0.5, tables: 21)) }
        if settings.temperature != 0 || settings.tint != 0 {
            stages.append(whiteBalance(temperature: settings.temperature, tint: settings.tint))
        }
        if settings.contrast != 0 { stages.append(adaptive(contrastStart, settings.contrast, brightness: brightness.brightest)) }
        if settings.highlights != 0 {
            stages.append(adaptive(highlightsStart, settings.highlights, brightness: brightness.logBrightest))
        }
        if settings.shadows != 0 { stages.append(adaptive(shadowsStart, settings.shadows, brightness: brightness.luminance)) }
        if settings.whites != 0 { stages.append(stage(whitesStart, settings.whites, low: -100, step: 25, tables: 9)) }
        if settings.blacks != 0 { stages.append(stage(blacksStart, settings.blacks, low: -100, step: 25, tables: 9)) }
        if settings.saturation != 0 { stages.append(stage(saturationStart, settings.saturation, low: -100, step: 25, tables: 9)) }
        if settings.vibrance != 0 { stages.append(stage(vibranceStart, settings.vibrance, low: -100, step: 25, tables: 9)) }
        let curve = settings.curve
        if curve.hasMeasuredDividers {
            for (index, value) in [curve.shadows, curve.darks, curve.lights, curve.highlights].enumerated() where value != 0 {
                stages.append(fifty(parametricStart + index * 5, value))
            }
        }
        return stages
    }

    /// Color Grading as Photoshop's draws it, in the order that composes like its own: the luminance sliders, then the
    /// global and midtone wheels, then highlights, then shadows. Each wheel blends the tables either side of its hue
    /// and saturation (below 25 the lower one is no change), and the shadow and highlight wheels between the Blending
    /// values measured; the midtone and global wheels, measured at Photoshop's default Blending, keep to that. Balance
    /// strengthens one of those two wheels and weakens the other, which with these tables is a share of saturation,
    /// fitted to Photoshop's renders at ±50.
    static func gradingStages(for grading: CameraRawGradingSettings) -> [CameraRawStage] {
        var stages: [CameraRawStage] = []
        for (index, wheel) in [grading.shadows, grading.midtones, grading.highlights, grading.global].enumerated()
            where wheel.luminance != 0 {
            stages.append(fifty(gradingLuminanceStart + index * 5, wheel.luminance))
        }
        let balance = grading.balance / 100
        let highlightShare = max(0, balance < 0 ? 1 + 1.4 * balance : 1 + 2 * balance)
        let shadowShare = max(0, balance < 0 ? 1 - 1.2 * balance : 1 - 1.4 * balance)
        // Blending 0, 50 and 100, and how far between the two either side.
        let (blendLow, blendUp) = between(grading.blending, in: [0, 50, 100])
        func section(_ blendIndex: Int, _ wheel: Int) -> Int {
            switch blendIndex {
            case 0: return gradingStart + wheel * 36
            case 1: return gradingStart + 72 + wheel * 36
            default: return gradingStart + 216 + wheel * 36
            }
        }
        for (wheel, color, share, blends) in [(3, grading.global, 1.0, false), (2, grading.midtones, 1.0, false),
                                              (1, grading.highlights, highlightShare, true), (0, grading.shadows, shadowShare, true)]
            where color.saturation * share > 0 {
            let position = color.hue.truncatingRemainder(dividingBy: 360) / 30
            let first = Int(position) % 12, second = (first + 1) % 12, around = position - Double(Int(position))
            let (level, up) = between(color.saturation * share, in: [0, 25, 50, 100])
            var parts: [(UnsafePointer<UInt8>?, Double)] = []
            let blendings: [(Int, Double)] = blends ? [(blendLow, 1 - blendUp), (blendLow + 1, blendUp)] : [(1, 1)]
            for (blendIndex, blendWeight) in blendings {
                let base = section(blendIndex, wheel)
                for (hue, hueWeight) in [(first, 1 - around), (second, around)] {
                    for (saturation, saturationWeight) in [(level, 1 - up), (level + 1, up)] {
                        parts.append((saturation == 0 ? nil : table(base + hue * 3 + saturation - 1), blendWeight * hueWeight * saturationWeight))
                    }
                }
            }
            stages.append(blend(parts))
        }
        return stages
    }

    /// The Color Mixer's stages: luminance, then saturation, then hue, the order that composes like Photoshop's.
    static func mixerStages(for mixer: CameraRawMixerSettings) -> [CameraRawStage] {
        var stages: [CameraRawStage] = []
        for (kind, values) in [mixer.luminance, mixer.saturation, mixer.hue].enumerated() {
            for (color, value) in values.enumerated() where value != 0 {
                stages.append(fifty(mixerStart + (kind * 8 + color) * 5, value))
            }
        }
        return stages
    }

    /// No change, on the composing grid.
    static func identity() -> [Float]? {
        guard tables != nil else { return nil }
        var out = [Float](repeating: 0, count: grid * grid * grid * 3)
        camera_raw_compose(&out, Int32(grid), nil, 0, Int32(size))
        return out
    }

    /// The stages run over the composing grid, or nil when there are none.
    static func compose(_ stages: [CameraRawStage]) -> [Float]? {
        guard !stages.isEmpty, tables != nil else { return nil }
        var out = [Float](repeating: 0, count: grid * grid * grid * 3)
        stages.withUnsafeBufferPointer { camera_raw_compose(&out, Int32(grid), $0.baseAddress, Int32($0.count), Int32(size)) }
        return out
    }

    /// The Temperature and Tint that turn a straight sRGB color (0…1) most nearly gray: a coarse search over both
    /// sliders, then a finer one around the best. Nil when the tables aren't there or the color has no channel to
    /// balance from.
    static func neutralize(red: Double, green: Double, blue: Double) -> (temperature: Double, tint: Double)? {
        guard tables != nil, min(red, green, blue) > 1e-4 else { return nil }
        func cast(_ temperature: Double, _ tint: Double) -> Double {
            var stage = whiteBalance(temperature: temperature, tint: tint)
            var color = [red, green, blue]
            camera_raw_stage_color(&stage, Int32(size), &color)
            return color.max()! - color.min()!
        }
        var best = (temperature: 0.0, tint: 0.0, cast: cast(0, 0))
        for (step, reach) in [(10.0, 100.0), (2.0, 10.0), (0.5, 2.0)] {
            let center = best
            for temperature in stride(from: center.temperature - reach, through: center.temperature + reach, by: step) {
                for tint in stride(from: center.tint - reach, through: center.tint + reach, by: step) {
                    guard abs(temperature) <= 100, abs(tint) <= 100 else { continue }
                    let found = cast(temperature, tint)
                    if found < best.cast { best = (temperature, tint, found) }
                }
            }
        }
        return (best.temperature, best.tint)
    }
}
