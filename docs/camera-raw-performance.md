# Camera Raw scope sampling benchmark

Measured October 14, 2026 on this Mac (Apple silicon, 10 logical processors), macOS 27.0.1. Release configuration, code coverage and parallel test execution disabled.

Only histogram/vectorscope sampling changes: every second pixel in both directions becomes every fourth through 4,000,000 pixels and every eighth above that. Image effects, their order, clipping overlays and preview resolution stay unchanged.

## Method

Deterministic opaque RGBA fixtures contain gradients and seeded color noise, at 2, 4, 6, 24 and 48 megapixels. These are synthetic images, not a representative photo corpus. Each variant uses the same source, settings and cached brightness measurement. Light uses Exposure +0.5, Contrast +15 and Highlights −20. The heavier 24 MP case additionally uses Shadows +25 and Clarity +15.

Scope timing includes both RGB histogram and vectorscope construction. Preview timing measures `CameraRawScope.preview`, including image filtering and scope generation. It excludes fixture creation, initial brightness measurement, UI event queueing, canvas composition, texture upload and display presentation. These are warmed render timings, not input-to-screen latency.

## Separate before/after runs

The baseline was measured before editing production code. The identical benchmark was then rerun after changing the sampling rule. Two warm-ups precede 15 scope trials and seven preview trials per case. Values below are medians.

| Image / settings | Scope before | Scope after | Preview before | Preview after | Preview time reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 MP / Light | 2.03 ms | 0.52 ms | 11.73 ms | 10.66 ms | 9.1% |
| 4 MP / Light | 2.83 ms | 0.76 ms | 18.62 ms | 17.16 ms | 7.8% |
| 6 MP / Light | 4.83 ms | 0.36 ms | 27.87 ms | 22.86 ms | 18.0% |
| 24 MP / Light | 18.58 ms | 1.17 ms | 98.74 ms | 77.75 ms | 21.3% |
| 24 MP / Light + Shadows + Clarity | 18.58 ms | 1.17 ms | 604.24 ms | 556.01 ms | 8.0% |
| 48 MP / Light | 38.87 ms | 2.39 ms | 198.96 ms | 176.31 ms | 11.4% |

The larger apparent improvement in the heavy case exceeds the isolated scope savings. Separate-run results include system-load, cache and CPU-frequency variation; the paired check below helps distinguish that variation from the sampling benefit.

## Paired confirmation

Two warm-ups per variant, then 15 alternating scope pairs and 11 alternating preview pairs in the same process. Old/new order reverses each pair. The original reference uses the unchanged effect renderer plus the original step-2 C scope kernel; the new path uses the production preview renderer. These ordinary jobs have no clipping or masking overlays.

| Image / settings | Scope before | Scope after | Preview before | Preview after | Preview time reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 MP / Light | 1.69 ms | 0.46 ms | 11.75 ms | 10.49 ms | 10.7% |
| 4 MP / Light | 2.85 ms | 0.74 ms | 18.83 ms | 16.68 ms | 11.4% |
| 6 MP / Light | 4.79 ms | 0.35 ms | 27.16 ms | 22.14 ms | 18.5% |
| 24 MP / Light | 18.71 ms | 1.35 ms | 122.24 ms | 106.79 ms | 12.6% |
| 24 MP / Light + Shadows + Clarity | 20.08 ms | 1.44 ms | 622.56 ms | 603.68 ms | 3.0% |
| 48 MP / Light | 38.38 ms | 2.69 ms | 194.55 ms | 157.18 ms | 19.2% |

The isolated scope calculation is about 93% cheaper on large fixtures. The overall benefit is useful for Light-only updates (roughly 11–19% lower median render time here), but modest with Shadows and Clarity (3%). Image effects dominate the heavy case. These measurements do not establish a GPU migration benefit or an input-to-screen frame rate.

The 24 MP Light trials varied substantially: original 108.17–153.24 ms, new 90.00–149.75 ms. The heavier trials also overlap: original 588.36–635.78 ms, new 568.72–647.19 ms. Treat the medians as workload-specific observations, not guaranteed speedups.

Functional checks cover the 4 MP threshold, histogram and vectorscope sample counts, color-bin placement, and the existing Camera Raw slider accuracy and preview tests.

## Reproduce

The opt-in benchmark is `CompositorTests/CameraRawScopePerformanceTests.swift`. Run it alone, using the same Release configuration as the measurements:

```sh
TEST_RUNNER_CAMERA_RAW_BENCHMARK=1 xcodebuild \
  -project Compositor.xcodeproj -scheme Compositor -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/CompositorScopeBenchmarkBuild \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -enableCodeCoverage NO -parallel-testing-enabled NO \
  -only-testing:CompositorTests/CameraRawScopePerformanceTests test
```

It writes `/tmp/compositor-scope-paired.json`. Normal test runs return immediately unless the benchmark variable is set. Scope counts and displayed color distributions can differ slightly with sparser sampling; the image pixels, clipping overlays, and effect math do not change.

## Raw results

All original trials are retained in [camera-raw-scope-sampling.json](benchmarks/camera-raw-scope-sampling.json).

- `/tmp/compositor-scope-baseline.json`: baseline sampling, measured before the edit.
- `/tmp/compositor-scope-after.json`: new sampling, measured after the edit.
- `/tmp/compositor-scope-paired.json`: alternating original/new sampling within one process.
- `/tmp/CompositorScopeBenchmarkBefore.log`, `/tmp/CompositorScopeBenchmarkAfter.log`, `/tmp/CompositorScopeBenchmarkPaired.log`: Xcode run logs.


## Metal composed color lookup

The first GPU stage accelerates the existing combined 33³ color lookup in large-image Camera Raw previews. It uses the CPU-composed table unchanged, including measured white balance, Light, curves, mixer, grading and calibration stages when they are folded into that table. The same stage can run before or after Shadows; every other effect remains in its original order on the CPU. This is a staged migration, not a replacement of the entire Camera Raw pipeline.

The shader disables fast math, selects lattice cells with integer arithmetic, and preserves premultiplied RGBA and row padding. Pixels within 0.01 of an 8-bit rounding boundary are resolved by the original double-precision C lookup. This avoids allowing a tiny interpolation difference to propagate through downstream effects. The unchanged CPU renderer remains the reference and the OK/export path. Unsupported tables, unavailable Metal, failed allocations and failed GPU commands fall back to that renderer without modifying the input.

The GPU edits one shared pixel buffer in place. Pixel, uncertainty and lookup buffers are reused under a lock during a drag and released on a worker when Camera Raw closes. The pipeline is warmed in the background on opening an eligible filter. The automatic path uses CPU processing through 8 megapixels; explicit benchmarks also measure smaller GPU jobs to identify overhead. Neither path reduces preview resolution.

Accuracy checks cover all 16,777,216 opaque RGB colors for five table profiles (identity, white balance, Light, extreme settings, and combined curve/mixer/grading), all alpha values with padded rows, a discontinuous randomized lookup table, mixed spatial effects, clipping views, HDR normalization, and preview versus CPU apply. Those comparisons require byte-for-byte agreement. They are extensive reference tests on this machine, not an exhaustive proof over every possible setting combination and GPU driver.

### GPU latency measurements

All values below are medians from the final pooled-buffer implementation on the same 10-core Apple-silicon Mac as the scope benchmark.

| Image / settings | CPU preview | GPU preview | Render time reduction |
| --- | ---: | ---: | ---: |
| 2 MP / Temperature | 7.04 ms | 6.42 ms | 8.8% |
| 2 MP / Light | 11.89 ms | 11.55 ms | 2.8% |
| 6 MP / Temperature | 17.67 ms | 14.14 ms | 20.0% |
| 6 MP / Light | 22.74 ms | 17.91 ms | 21.3% |
| 12 MP / Temperature | 35.34 ms | 25.08 ms | 29.0% |
| 12 MP / Light | 40.53 ms | 32.00 ms | 21.0% |
| 24 MP / Temperature | 69.58 ms | 44.62 ms | 35.9% |
| 24 MP / Light | 75.89 ms | 52.32 ms | 31.1% |
| 24 MP / Light + Shadows + Clarity | 562.52 ms | 531.01 ms | 5.6% |
| 48 MP / Temperature | 148.54 ms | 80.41 ms | 45.9% |
| 48 MP / Light | 151.89 ms | 85.76 ms | 43.5% |

Temperature uses Temperature +35 and Tint −12. Light adds Exposure +0.5, Contrast +15 and Highlights −20. The heavier case adds Shadows +25 and Clarity +15. Smaller jobs are forced onto Metal only for benchmarking; the app retains the conservative CPU cutoff through 8 MP.

| Image | CPU lookup | GPU lookup, transfers and repair |
| --- | ---: | ---: |
| 2 MP | 4.25 ms | 2.67 ms |
| 6 MP | 12.94 ms | 7.59 ms |
| 12 MP | 26.49 ms | 14.61 ms |
| 24 MP | 55.39 ms | 26.25 ms |
| 48 MP | 118.72 ms | 48.18 ms |

This first GPU stage saves approximately 25 ms on the 24 MP Temperature fixture and 68 ms on the 48 MP fixture. Full Light previews improve by 31–44% at 24–48 MP. Shadows and Clarity remain CPU-bound: the heavy case improves by 5.6%, not by the lookup-only speedup.

Timings still vary. The 24 MP heavy GPU trials span 518.75–755.21 ms; the median is 531.01 ms. The 48 MP Temperature GPU trials span 72.37–95.53 ms. These warmed synthetic-image measurements are not a universal frame-rate or input-to-screen guarantee.

Raw final samples are retained in [camera-raw-gpu.json](benchmarks/camera-raw-gpu.json). Initial allocation-heavy trials were used to identify and remove the extra full-image buffer and per-frame allocation overhead; they are not the final numbers reported here.

The paired benchmark uses the same generated fixtures, new 4th/8th-pixel scope sampling on both paths, cached brightness and native image resolution. Two warm-ups per backend precede 11 alternating CPU/GPU pairs. Full-preview measurements include bitmap preparation, table construction, lookup, downstream effects, histogram/vectorscope generation, GPU transfers, synchronization and CPU rounding repair. They exclude UI event queueing and presentation. Lookup-only measurements include the GPU transfers and repair but exclude the common input reset. The first allocation and shader compilation are excluded by warm-up.

Run the opt-in benchmark alone:

```sh
TEST_RUNNER_CAMERA_RAW_GPU_BENCHMARK=1 xcodebuild \
  -project Compositor.xcodeproj -scheme Compositor -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/CompositorScopeBenchmarkBuild \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -enableCodeCoverage NO -parallel-testing-enabled NO \
  -only-testing:CompositorTests/CameraRawGPUPerformanceTests test
```

The benchmark writes `/tmp/compositor-camera-raw-gpu.json`. Ordinary unit runs do no timing work unless the benchmark environment variable is set. Exact parity tests are in `CameraRawGPUTests`; they are enabled when a Metal device exists, and still fail if the shader cannot compile on that device.
