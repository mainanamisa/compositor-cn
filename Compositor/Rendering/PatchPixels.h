#ifndef PatchPixels_h
#define PatchPixels_h
#include <stdint.h>
#include <stddef.h>
// Fills a hole in premultiplied RGBA (4 bytes per pixel, `stride` bytes per row) from the rest of the image, the way
// Content-Aware Fill works: every small patch over the hole is matched to the patch of the image it most resembles
// (PatchMatch), the overlapping matches are blended into each pixel, and that's repeated until it settles, first on
// a small copy for the hole's overall structure and then at each larger size for its detail.
//   `hole` (width * height bytes, `holeStride` per row): nonzero marks a pixel to fill.
// Opaque pixels outside the hole are what's matched and copied; transparent ones outside it are left alone and
// ignored. Returns 1 when the hole is filled, 0 when there's no image to fill it from, -1 when memory runs out.
int patch_fill(uint8_t *rgba, size_t stride, const uint8_t *hole, size_t holeStride, int width, int height, uint32_t seed);
#endif
