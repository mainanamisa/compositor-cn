import AppKit
import Testing
@testable import Compositor

@MainActor
struct CameraRawScopePerformanceTests {
    nonisolated private static func scopeAtStep(_ image: CGImage, step: Int32) -> CameraRawScope? {
        var bins = Array(repeating: 0.0, count: 256 * 3)
        var scope = Array(repeating: 0.0, count: 64 * 64)
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        camera_raw_scope(bytes, image.width, image.height, image.bytesPerRow, step, &bins, &scope, 64)
        return CameraRawScope(red: Array(bins[0..<256]), green: Array(bins[256..<512]),
                              blue: Array(bins[512..<768]), vectorscope: scope)
    }

    /// Run alone with TEST_RUNNER_CAMERA_RAW_BENCHMARK=1; ordinary test runs skip the benchmark.
    @Test func pairedScopeAndPreviewLatency() async throws {
        guard ProcessInfo.processInfo.environment["CAMERA_RAW_BENCHMARK"] == "1" else { return }
        let results = try await Task.detached(priority: .userInitiated) { () throws -> [[String: Any]] in
            func fixture(width: Int, height: Int) throws -> CGImage {
                let context = try BrushRaster.context(width: width, height: height, mask: false)
                let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
                var state: UInt32 = 0x12345678
                for y in 0..<height {
                    for x in 0..<width {
                        state ^= state << 13; state ^= state >> 17; state ^= state << 5
                        let index = y * context.bytesPerRow + x * 4
                        bytes[index] = UInt8((x * 190 / width + Int(state & 63)))
                        bytes[index + 1] = UInt8((y * 190 / height + Int((state >> 8) & 63)))
                        bytes[index + 2] = UInt8(((x + y) * 190 / (width + height) + Int((state >> 16) & 63)))
                        bytes[index + 3] = 255
                    }
                }
                return try #require(context.makeImage())
            }

            func elapsed(_ body: () throws -> Void) throws -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                try autoreleasepool { try body() }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }
            var rows: [[String: Any]] = []
            for (width, height) in [(2000, 1000), (2000, 2000), (3000, 2000), (6000, 4000), (8000, 6000)] {
                try autoreleasepool {
                    let source = try fixture(width: width, height: height)
                    let brightness = CameraRawTables.brightness(of: source)
                    let step: Int32 = width * height <= 4_000_000 ? 4 : 8
                    for heavy in (width == 6000 ? [false, true] : [false]) {
                        var settings = FilterSettings()
                        settings.cameraRaw.exposure = 0.5
                        settings.cameraRaw.contrast = 15
                        settings.cameraRaw.highlights = -20
                        if heavy { settings.cameraRaw.shadows = 25; settings.cameraRaw.clarity = 15 }
                        var job = FilterJob(kind: .cameraRaw, image: source, settings: settings, scale: 1,
                                            selection: nil, mapping: .identity, seed: 1)
                        job.cameraRawBrightness = brightness
                        func render(old: Bool) throws {
                            if old {
                                let graded = try PixelFilter.run(job)
                                let scope = try #require(Self.scopeAtStep(graded, step: 2))
                                #expect(graded.width == width && scope.red.reduce(0, +) > 0)
                            } else {
                                let made = try CameraRawScope.preview(job)
                                #expect(made.image.width == width && made.scope.red.reduce(0, +) > 0)
                            }
                        }
                        for _ in 0..<2 {
                            try autoreleasepool { try render(old: true) }
                            try autoreleasepool { try render(old: false) }
                        }
                        var oldScope: [Double] = [], newScope: [Double] = []
                        for index in 0..<15 {
                            for old in (index % 2 == 0 ? [true, false] : [false, true]) {
                                let time = try elapsed {
                                    let scope = try #require(Self.scopeAtStep(source, step: old ? 2 : step))
                                    #expect(scope.red.reduce(0, +) > 0)
                                }
                                if old { oldScope.append(time) } else { newScope.append(time) }
                            }
                        }
                        var oldPreview: [Double] = [], newPreview: [Double] = []
                        for index in 0..<11 {
                            for old in (index % 2 == 0 ? [true, false] : [false, true]) {
                                let time = try elapsed { try render(old: old) }
                                if old { oldPreview.append(time) } else { newPreview.append(time) }
                            }
                        }
                        rows.append(["width": width, "height": height, "profile": heavy ? "Light + Shadows + Clarity" : "Light",
                                     "before_scope_ms": oldScope, "after_scope_ms": newScope,
                                     "before_preview_ms": oldPreview, "after_preview_ms": newPreview])
                    }
                }
            }
            return rows
        }.value
        let data = try JSONSerialization.data(withJSONObject: ["configuration": "Release", "warmups_per_variant": 2,
            "scope_pairs": 15, "preview_pairs": 11, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/compositor-scope-paired.json"))
    }
}
