import AppKit
import Testing
@testable import Compositor

@MainActor
struct CameraRawGPUPerformanceTests {
    @Test func pairedCPUAndGPUPreviewLatency() async throws {
        guard ProcessInfo.processInfo.environment["CAMERA_RAW_GPU_BENCHMARK"] == "1" else { return }
        let results = try await Task.detached(priority: .userInitiated) { () throws -> [[String: Any]] in
            let metal = try #require(MetalCameraRawLookup.shared)
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
            for (width, height) in [(2000, 1000), (3000, 2000), (4000, 3000), (6000, 4000), (8000, 6000)] {
                try autoreleasepool {
                    let source = try fixture(width: width, height: height)
                    let brightness = CameraRawTables.brightness(of: source)
                    for profile in ["Temperature", "Light", "Light + Shadows + Clarity"] {
                        if profile == "Light + Shadows + Clarity", width != 6000 { continue }
                        var settings = FilterSettings()
                        settings.cameraRaw.temperature = 35
                        settings.cameraRaw.tint = -12
                        if profile != "Temperature" {
                            settings.cameraRaw.exposure = 0.5
                            settings.cameraRaw.contrast = 15
                            settings.cameraRaw.highlights = -20
                        }
                        if profile == "Light + Shadows + Clarity" {
                            settings.cameraRaw.shadows = 25; settings.cameraRaw.clarity = 15
                        }
                        var cpu = FilterJob(kind: .cameraRaw, image: source, settings: settings, scale: 1,
                                            selection: nil, mapping: .identity, seed: 1)
                        cpu.cameraRawBrightness = brightness
                        var gpu = cpu
                        gpu.cameraRawUsesGPU = true
                        // Verify pixel identity for each measured workload before timing either path.
                        let reference = try CameraRawScope.preview(cpu).image
                        let accelerated = try CameraRawScope.preview(gpu).image
                        #expect(reference.dataProvider?.data == accelerated.dataProvider?.data)
                        for _ in 0..<2 {
                            try autoreleasepool { _ = try CameraRawScope.preview(cpu) }
                            try autoreleasepool { _ = try CameraRawScope.preview(gpu) }
                        }
                        var cpuTimes: [Double] = [], gpuTimes: [Double] = []
                        for index in 0..<11 {
                            for useGPU in (index % 2 == 0 ? [false, true] : [true, false]) {
                                let time = try elapsed {
                                    let made = try CameraRawScope.preview(useGPU ? gpu : cpu)
                                    #expect(made.image.width == width)
                                }
                                if useGPU { gpuTimes.append(time) } else { cpuTimes.append(time) }
                            }
                        }
                        var row: [String: Any] = ["width": width, "height": height, "profile": profile,
                                                 "cpu_preview_ms": cpuTimes, "gpu_preview_ms": gpuTimes]
                        if profile == "Temperature" {
                            let lookup = try #require(CameraRawTables.compose(CameraRawTables.stages(for: settings.cameraRaw, brightness: brightness)))
                            let bitmap = try BrushRaster.context(width: width, height: height, mask: false)
                            let pixels = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
                            let bytes = try #require(source.dataProvider?.data)
                            var cpuLookup: [Double] = [], gpuLookup: [Double] = []
                            for index in 0..<11 {
                                for useGPU in (index % 2 == 0 ? [false, true] : [true, false]) {
                                    memcpy(pixels, CFDataGetBytePtr(bytes)!, bitmap.bytesPerRow * height)
                                    let time = try elapsed {
                                        if useGPU {
                                            #expect(metal.apply(pixels, width: width, height: height, rowBytes: bitmap.bytesPerRow,
                                                                table: lookup, grid: CameraRawTables.grid))
                                        } else {
                                            adjust_camera_raw(pixels, width, height, bitmap.bytesPerRow, lookup, Int32(CameraRawTables.grid), 0)
                                        }
                                    }
                                    if useGPU { gpuLookup.append(time) } else { cpuLookup.append(time) }
                                }
                            }
                            row["cpu_lookup_ms"] = cpuLookup; row["gpu_lookup_ms"] = gpuLookup
                        }
                        rows.append(row)
                    }
                }
            }
            return rows
        }.value
        let data = try JSONSerialization.data(withJSONObject: ["configuration": "Release", "warmups_per_variant": 2,
            "pairs": 11, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/compositor-camera-raw-gpu.json"))
    }
}
