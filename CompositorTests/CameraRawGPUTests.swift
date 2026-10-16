import AppKit
import Metal
import Testing
@testable import Compositor

@MainActor
@Suite(.serialized, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct CameraRawGPUTests {
    private func profiles() -> [CameraRawSettings] {
        var warm = CameraRawSettings()
        warm.temperature = 37; warm.tint = -19
        var light = warm
        light.exposure = 0.7; light.contrast = 23; light.highlights = -45
        light.whites = 12; light.blacks = -18; light.vibrance = 37; light.saturation = -12
        var extreme = light
        extreme.temperature = -100; extreme.tint = 100; extreme.exposure = 5
        extreme.contrast = 100; extreme.highlights = -100; extreme.whites = 100; extreme.blacks = -100
        var color = light
        color.curve.rgb = CameraRawCurveSettings.strongContrast
        color.curve.shadows = 30
        color.mixer.hue[0] = 45; color.mixer.saturation[2] = -25; color.mixer.luminance[4] = 30
        color.grading.shadows.hue = 220; color.grading.shadows.saturation = 35
        color.grading.highlights.hue = 40; color.grading.highlights.saturation = 20
        return [CameraRawSettings(), warm, light, extreme, color]
    }

    private func table(_ settings: CameraRawSettings) throws -> [Float] {
        var composed = CameraRawTables.compose(CameraRawTables.stages(for: settings, brightness: .init()))
        if settings.adjustsCurve || settings.adjustsMixer || settings.adjustsGrading {
            composed = settings.foldingColor(into: composed)
        }
        return try #require(composed ?? CameraRawTables.identity())
    }

    @Test func composedLookupMatchesEveryOpaqueEightBitColorExactly() throws {
        let metal = try #require(MetalCameraRawLookup.shared)
        let width = 4096, height = 4096, rowBytes = width * 4
        let pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)
        defer { pixels.deallocate() }
        for settings in profiles() {
            for index in 0..<(width * height) { pixels[index] = UInt32(index) | 0xFF000000 }
            var expected = Data(bytes: pixels, count: rowBytes * height)
            let lookup = try table(settings)
            expected.withUnsafeMutableBytes {
                adjust_camera_raw($0.baseAddress!.assumingMemoryBound(to: UInt8.self), width, height, rowBytes,
                                  lookup, Int32(CameraRawTables.grid), 0)
            }
            #expect(metal.apply(UnsafeMutableRawPointer(pixels).assumingMemoryBound(to: UInt8.self), width: width,
                                height: height, rowBytes: rowBytes, table: lookup, grid: CameraRawTables.grid))
            #expect(Data(bytes: pixels, count: rowBytes * height) == expected,
                    "all 16,777,216 opaque colors must match byte for byte")
        }
    }

    @Test func composedLookupPreservesAllAlphaValuesAndPaddedRowsExactly() throws {
        let metal = try #require(MetalCameraRawLookup.shared)
        let width = 1031, height = 1024, rowBytes = width * 4 + 28
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: rowBytes * height)
        defer { pixels.deallocate() }
        var initial = Data(count: rowBytes * height)
        initial.withUnsafeMutableBytes { raw in
            let bytes = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let key = UInt32(x + y * width) &* 2654435761
                    let alpha = Int(key & 255), at = y * rowBytes + x * 4
                    bytes[at] = UInt8(Int((key >> 8) & 255) % (alpha + 1))
                    bytes[at + 1] = UInt8(Int((key >> 16) & 255) % (alpha + 1))
                    bytes[at + 2] = UInt8(Int((key >> 24) & 255) % (alpha + 1))
                    bytes[at + 3] = UInt8(alpha)
                }
                for x in width * 4..<rowBytes { bytes[y * rowBytes + x] = 173 }
            }
        }
        for settings in profiles() {
            initial.withUnsafeBytes { memcpy(pixels, $0.baseAddress!, rowBytes * height) }
            var expected = initial
            let lookup = try table(settings)
            expected.withUnsafeMutableBytes {
                adjust_camera_raw($0.baseAddress!.assumingMemoryBound(to: UInt8.self), width, height, rowBytes,
                                  lookup, Int32(CameraRawTables.grid), 0)
            }
            #expect(metal.apply(pixels, width: width, height: height, rowBytes: rowBytes,
                                table: lookup, grid: CameraRawTables.grid))
            #expect(Data(bytes: pixels, count: rowBytes * height) == expected)
        }
    }

    @Test func discontinuousTablesMatchTheCPUAndInvalidTablesLeaveTheInputAlone() throws {
        let metal = try #require(MetalCameraRawLookup.shared)
        let width = 1024, height = 1024, rowBytes = width * 4
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for index in 0..<(width * height) {
            let key = UInt32(index) &* 2654435761
            let alpha = Int(key & 255)
            for channel in 0..<3 { pixels[index * 4 + channel] = UInt8(Int((key >> (8 * channel)) & 255) % (alpha + 1)) }
            pixels[index * 4 + 3] = UInt8(alpha)
        }
        let original = Data(bytes: pixels, count: rowBytes * height)
        var lookup = (0..<(33 * 33 * 33 * 3)).map { Float((UInt32($0) &* 2654435761) >> 8) / 16777215 }
        var expected = original
        expected.withUnsafeMutableBytes {
            adjust_camera_raw($0.baseAddress!.assumingMemoryBound(to: UInt8.self), width, height, rowBytes, lookup, 33, 0)
        }
        #expect(metal.apply(pixels, width: width, height: height, rowBytes: rowBytes, table: lookup, grid: 33))
        #expect(Data(bytes: pixels, count: rowBytes * height) == expected)
        let beforeFailure = Data(bytes: pixels, count: rowBytes * height)
        lookup[0] = .nan
        #expect(!metal.apply(pixels, width: width, height: height, rowBytes: rowBytes, table: lookup, grid: 33))
        #expect(Data(bytes: pixels, count: rowBytes * height) == beforeFailure)
    }

    @Test func mixedEffectsAndClippingMatchTheCPUReferenceExactly() throws {
        _ = try #require(MetalCameraRawLookup.shared)
        let width = 1024, height = 1024
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let at = y * context.bytesPerRow + x * 4
                pixels[at] = UInt8((x * 131 + y * 17) % 256)
                pixels[at + 1] = UInt8((x * 31 + y * 71) % 256)
                pixels[at + 2] = UInt8((x * 59 + y * 13) % 256)
                pixels[at + 3] = 255
            }
        }
        let input = try #require(context.makeImage())
        var mixed = profiles()[2]
        mixed.shadows = 25; mixed.clarity = 15; mixed.texture = 12; mixed.grainAmount = 10
        mixed.detail.sharpenAmount = 25
        for settings in profiles().dropFirst() + [mixed] {
            let cpu = try settings.apply(input, seed: 123)
            let gpu = try settings.apply(input, seed: 123, usesGPU: true)
            #expect(cpu.dataProvider?.data == gpu.dataProvider?.data)
        }
        for clipping in [CameraRawClipping.highlights, .shadows] {
            let cpu = try mixed.apply(input, clipping: clipping)
            let gpu = try mixed.apply(input, clipping: clipping, usesGPU: true)
            #expect(cpu.dataProvider?.data == gpu.dataProvider?.data)
        }
    }

    @Test func largePreviewsUseMetalAndOKStillMatchesTheCPU() async throws {
        let session = EditorSession()
        session.createDocument(width: 4000, height: 3000, emptyLayer: true)
        let context = try BrushRaster.context(width: 4000, height: 3000, mask: false)
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let input = try #require(context.makeImage())
        session.insert(ImportedImage(image: input, thumbnail: input, name: "GPU preview"))
        session.beginFilter(.cameraRaw)
        let edit = try #require(session.filterEdit)
        #expect(edit.previewJob.cameraRawUsesGPU && edit.previewScale == 1)
        var settings = edit.settings
        settings.cameraRaw.temperature = 37
        settings.cameraRaw.tint = -19
        session.updateFilter(settings, preview: true)
        while let task = edit.previewTask { await task.value }
        let shown = try #require(edit.preparedPreview)
        let reference = try settings.cameraRaw.apply(input)
        #expect(shown.dataProvider?.data == reference.dataProvider?.data)
        await session.commitFilter()
        let committed = try #require(session.activeLayer?.asset?.image)
        #expect(committed.dataProvider?.data == reference.dataProvider?.data)
        #expect(!FilterJob(kind: .cameraRaw, image: input, settings: settings, scale: 1,
                          selection: nil, mapping: .identity).cameraRawUsesGPU)

        let small = EditorSession()
        small.createDocument(width: 100, height: 80)
        let smallImage = try #require(input.cropping(to: CGRect(x: 0, y: 0, width: 100, height: 80)))
        small.insert(ImportedImage(image: smallImage, thumbnail: smallImage, name: "Small preview"))
        small.beginFilter(.cameraRaw)
        #expect(small.filterEdit?.previewJob.cameraRawUsesGPU == false)
        small.cancelFilter()
    }

    @Test func hdrPreviewKeepsTheExistingNormalizationAndPixels() throws {
        _ = try #require(MetalCameraRawLookup.shared)
        let width = 1024, height = 1024
        let context = try DeepLayer.context(width: width, height: height, hdr: true)
        let pixels = try #require(context.data).assumingMemoryBound(to: Float16.self)
        for index in 0..<(width * height) {
            pixels[index * 4] = Float16(Float(index % 1024) / 256)
            pixels[index * 4 + 1] = Float16(Float(index % 512) / 256)
            pixels[index * 4 + 2] = Float16(0.3)
            pixels[index * 4 + 3] = 1
        }
        let hdr = try #require(context.makeImage())
        var settings = FilterSettings()
        settings.cameraRaw = profiles()[2]
        var cpu = FilterJob(kind: .cameraRaw, image: hdr, settings: settings, scale: 1, selection: nil, mapping: .identity)
        cpu.cameraRawUsesGPU = false
        var gpu = cpu
        gpu.cameraRawUsesGPU = true
        let reference = try PixelFilter.previewHDR(cpu, from: hdr)
        let accelerated = try PixelFilter.previewHDR(gpu, from: hdr)
        #expect(reference.dataProvider?.data == accelerated.dataProvider?.data)
    }

}
