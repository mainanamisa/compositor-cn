import Foundation
import Metal
import Synchronization

/// The existing composed color table on Metal. Values close to an 8-bit rounding boundary are repaired by
/// the CPU's double-precision lookup, so a precision difference cannot accumulate through later effects.
nonisolated final class MetalCameraRawLookup: Sendable {
    static let shared: MetalCameraRawLookup? = try? MetalCameraRawLookup()
    static let minimumPixels = 8_000_001
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private struct Buffers {
        let pixels: MTLBuffer
        let uncertain: MTLBuffer
        let lookup: MTLBuffer
    }
    private let buffers = Mutex<Buffers?>(nil)

    /// Called on a worker when a Camera Raw session closes, so large scratch buffers don't remain resident.
    func discardBuffers() { buffers.withLock { $0 = nil } }

    private struct Parameters {
        var width: UInt32
        var height: UInt32
        var rowBytes: UInt32
        var grid: UInt32
    }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw ExportError.render }
        let options = MTLCompileOptions()
        options.fastMathEnabled = false
        let library = try device.makeLibrary(source: Self.source, options: options)
        guard let function = library.makeFunction(name: "camera_raw_lookup") else { throw ExportError.render }
        self.device = device
        self.queue = queue
        pipeline = try device.makeComputePipelineState(function: function)
    }

    /// Leaves `pixels` untouched on failure, so the original CPU pass can always take over.
    /// Reuse shared buffers during a slider drag instead of allocating full-image storage every update.
    func apply(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, rowBytes: Int, table: [Float], grid: Int) -> Bool {
        guard width > 0, height > 0, grid == 33, rowBytes >= width * 4,
              rowBytes <= Int(UInt32.max), height <= Int(UInt32.max),
              table.count == grid * grid * grid * 3,
              table.withUnsafeBufferPointer({ camera_raw_lookup_is_valid($0.baseAddress, Int32(grid)) != 0 }) else { return false }
        let bytes = rowBytes * height
        guard bytes <= Int(UInt32.max), bytes <= device.maxBufferLength, width * height <= device.maxBufferLength else { return false }
        return buffers.withLock { storage in
            let lookupBytes = table.count * MemoryLayout<Float>.stride
            if storage == nil || storage!.pixels.length < bytes || storage!.uncertain.length < width * height {
                guard let input = device.makeBuffer(length: bytes, options: .storageModeShared),
                      let uncertain = device.makeBuffer(length: width * height, options: .storageModeShared),
                      let lookup = device.makeBuffer(length: lookupBytes, options: .storageModeShared) else { return false }
                storage = Buffers(pixels: input, uncertain: uncertain, lookup: lookup)
            }
            guard let ready = storage, let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else { return false }
            memcpy(ready.pixels.contents(), pixels, bytes)
            table.withUnsafeBytes { memcpy(ready.lookup.contents(), $0.baseAddress!, lookupBytes) }
            var parameters = Parameters(width: UInt32(width), height: UInt32(height), rowBytes: UInt32(rowBytes), grid: UInt32(grid))
            encoder.setComputePipelineState(pipeline)
            for (index, buffer) in [ready.pixels, ready.uncertain, ready.lookup].enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
            encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 3)
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { return false }
            let result = ready.pixels.contents().assumingMemoryBound(to: UInt8.self)
            table.withUnsafeBufferPointer {
                camera_raw_repair_lookup(result, pixels, ready.uncertain.contents().assumingMemoryBound(to: UInt8.self),
                                         width, height, rowBytes, $0.baseAddress, Int32(grid))
            }
            // The pointwise kernel preserves row padding as well as alpha.
            memcpy(pixels, result, bytes)
            return true
        }
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Parameters { uint width; uint height; uint rowBytes; uint grid; };
    kernel void camera_raw_lookup(device uchar *pixels [[buffer(0)]], device uchar *uncertain [[buffer(1)]],
                                  device const float *table [[buffer(2)]], constant Parameters &p [[buffer(3)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.width || gid.y >= p.height) return;
        uint at = gid.y * p.rowBytes + gid.x * 4;
        uchar4 pixel = uchar4(pixels[at], pixels[at+1], pixels[at+2], pixels[at+3]);
        float alpha = float(pixel.a);
        uchar4 result = pixel;
        bool repair = false;
        if (pixel.a != 0) {
            // Integer cell selection avoids moving to the wrong cell at an exact lattice boundary.
            uint3 numerator = min(uint3(pixel.rgb), uint3(pixel.a)) * (p.grid - 1);
            uint3 cell = min(numerator / uint(pixel.a), uint3(p.grid - 2));
            float3 f = float3(numerator - cell * uint(pixel.a)) / alpha;
            float3 color = 0.0f;
            for (uint corner = 0; corner < 8; ++corner) {
                uint3 delta = uint3(corner >> 2, (corner >> 1) & 1, corner & 1);
                float3 weights = select(1.0f - f, f, delta != uint3(0));
                float w = weights.x * weights.y * weights.z;
                if (w == 0.0f) continue;
                uint3 node = cell + delta;
                uint index = ((node.x * p.grid + node.y) * p.grid + node.z) * 3;
                color += w * float3(table[index], table[index+1], table[index+2]);
            }
            float3 scaled = clamp(color, 0.0f, 1.0f) * alpha;
            // With a 33³ table bounded to [0,1], this conservative guard is much wider than float roundoff.
            // The CPU resolves these pixels using the original double arithmetic and rounding rules.
            repair = any(abs(scaled - (floor(scaled) + 0.5f)) <= 0.01f);
            result.rgb = uchar3(clamp(floor(scaled + 0.5f), 0.0f, alpha));
        }
        pixels[at] = result.r; pixels[at+1] = result.g; pixels[at+2] = result.b; pixels[at+3] = result.a;
        uncertain[gid.y * p.width + gid.x] = repair ? 1 : 0;
    }
    """
}
