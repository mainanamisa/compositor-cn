import Foundation

/// Camera Raw's Shadows as Photoshop's Camera Raw Filter draws it. Photoshop's adapts to the picture region by region: a
/// dark region below brighter ones is lifted far more than the same tone in a picture that is dark all over, and the
/// texture within it is stretched. So it isn't a color table but a pass of its own (`adjust_camera_raw_shadows`), run on
/// coefficients fitted to Photoshop's renders of some 260 photos at several exposures (Resources/CameraRawShadows.bin).
/// Measured on photos it wasn't fitted to, it lands within a few levels of Photoshop's on most, and on all of them
/// nearer than the color tables it replaced.
///
/// Photoshop works a picture under about 1020 pixels on its long side differently, lifting much less, so there are two
/// sets of coefficients. Which one applies goes by the layer's own size, so a preview drawn smaller matches the result.
nonisolated enum CameraRawShadows {
    struct Tables {
        /// The long side, in pixels, from which a picture takes the second set.
        let normalFrom: Double
        let amounts: [Double]
        /// By set (small, then normal), then by amount.
        let coefficients: [[[Float]]]
        let xCount: Int, kCount: Int
        let xLow: Float, xStep: Float, kLow: Float, kStep: Float
    }

    /// "CRS2"; then, as 16-bit integers, the number of sets, amounts, x columns, K rows and terms; as 32-bit floats, the
    /// long side the second set starts at, x's low end and step, K's low end and step, the amounts, and each set's
    /// coefficients amount by amount.
    static let tables: Tables? = {
        guard let url = Bundle.main.url(forResource: "CameraRawShadows", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 34, data.prefix(4) == Data("CRS2".utf8) else { return nil }
        let bytes = [UInt8](data)
        func int16(_ at: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)) }
        func float(_ at: Int) -> Float {
            Float(bitPattern: UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24)
        }
        let sets = int16(4), amounts = int16(6), xCount = int16(8), kCount = int16(10), terms = int16(12)
        let per = xCount * kCount * terms, header = 34
        guard sets == 2, amounts > 0, terms == 3, data.count == header + amounts * 4 + sets * amounts * per * 4 else { return nil }
        let values = (0..<amounts).map { Double(float(header + $0 * 4)) }
        let start = header + amounts * 4
        let coefficients = (0..<sets).map { s in
            (0..<amounts).map { a in (0..<per).map { float(start + ((s * amounts + a) * per + $0) * 4) } }
        }
        return Tables(normalFrom: Double(float(14)), amounts: values, coefficients: coefficients, xCount: xCount, kCount: kCount,
                      xLow: float(18), xStep: float(22), kLow: float(26), kStep: float(30))
    }()

    /// The coefficients at `amount` (−100…100) for one set: the fitted amounts either side blended, zero itself being no
    /// change.
    static func coefficients(for amount: Double, set: Int, in tables: Tables) -> [Float] {
        var points: [(Double, [Float]?)] = zip(tables.amounts, tables.coefficients[set]).map { ($0, $1) }
        points.append((0, nil))
        points.sort { $0.0 < $1.0 }
        let value = min(points.last!.0, max(points.first!.0, amount))
        var index = 0
        while index < points.count - 2 && value > points[index + 1].0 { index += 1 }
        let (low, lower) = points[index], (high, upper) = points[index + 1]
        let t = Float((value - low) / (high - low))
        let count = tables.coefficients[set][0].count
        return (0..<count).map { i in (lower?[i] ?? 0) * (1 - t) + (upper?[i] ?? 0) * t }
    }

    /// Runs Shadows at `amount` over 8-bit premultiplied RGBA. `scale` is pixels here per layer pixel, so a preview
    /// picks the set its layer would. Does nothing when the tables are missing.
    static func apply(_ amount: Double, pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, stride: Int, scale: Double) {
        guard amount != 0, let tables else { return }
        let longSide = Double(max(width, height)) / (scale > 0 ? scale : 1)
        let coefficients = coefficients(for: amount, set: longSide >= tables.normalFrom ? 1 : 0, in: tables)
        coefficients.withUnsafeBufferPointer {
            adjust_camera_raw_shadows(pixels, width, height, stride, $0.baseAddress, Int32(tables.xCount), tables.xLow, tables.xStep,
                                      Int32(tables.kCount), tables.kLow, tables.kStep)
        }
    }
}
