#ifndef HealPixels_h
#define HealPixels_h
#include <stdint.h>
#include <stddef.h>
// Half-open bounds of nonzero bytes in a gray bitmap; all zero when empty.
void heal_coverage_bounds(const uint8_t *gray, size_t width, size_t height, size_t stride, long bounds[4]);
// Spot healing, in place, over premultiplied RGBA (4 bytes per pixel, `stride` bytes per row).
// `coverage` (width * height bytes, 0–255) marks what to heal.
//   mode 0, Content-Aware: rebuilds the spot pixel by pixel from the image around it (PatchPixels.h);
//   mode 1, Create Texture: fills smoothly from the spot's edges and adds grain matching the
//           detail around it;
//   mode 2, Proximity Match: copies texture from the nearby patch whose surrounding ring of pixels
//           best matches the ring around the spot, the closest good one.
// Modes 1 and 2: copied texture is blended so it meets the surrounding tone exactly: the difference along the
// spot's edge is spread smoothly across it (a membrane fill). The result replaces the original
// by coverage × opacity. Returns 0, or -1 when memory runs out.
// Smooth values over the pixels marked 2, fixed to the values of those marked 1 around them (0: neither): the
// membrane that makes healed texture meet its surroundings' tone. `value` is 4 floats a pixel; pass depth 0. A
// coarser copy is solved first and used as the starting point, so a large area settles in few passes.
void heal_membrane(float *value, const uint8_t *role, long w, long h, int depth);
int spot_heal(uint8_t *rgba, const uint8_t *coverage, size_t width, size_t height, size_t stride,
              float opacity, int mode, uint32_t seed);
#endif
