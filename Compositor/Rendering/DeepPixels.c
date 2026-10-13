#include "DeepPixels.h"
#include <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>

// Runs `body` over rows split into a few bands a core, all at once.
static void deep_rows(size_t height, void (^body)(size_t first, size_t last)) {
    size_t bands = height < 64 ? 1 : 32, size = (height + bands - 1) / bands;
    dispatch_apply(bands, DISPATCH_APPLY_AUTO, ^(size_t band) {
        size_t first = band * size, last = first + size < height ? first + size : height;
        if (first < last) body(first, last);
    });
}

static inline long deep_alpha8(uint16_t alpha) { return lroundf((float)alpha * (255.0f / 65535.0f)); }

// A fixed noise for each pixel and channel, 0 up to 1, the same in every run so they all start from the same `low`.
static inline float deep_noise(size_t x, size_t y, int channel) {
    uint32_t h = (uint32_t)x * 0x9E3779B1u ^ (uint32_t)y * 0x85EBCA77u ^ (uint32_t)(channel + 1) * 0xC2B2AE3Du;
    h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
    return (float)(h >> 8) / (float)(1u << 24);
}

// A channel's `low`: a step below its 8-bit value rounded as dither rounds (down or up at random, more often towards the
// nearer), so the color lies 0 to 2 steps above it; kept within the pixel's alpha (premultiplied colors never pass it).
// Rounded straight down, every pixel starting from one 8-bit value took the operation's rounding of that value, the
// same error across a whole band: up to half a step, which a steep Levels afterwards showed as bands. Dithered, where
// a band starts falls at random from pixel to pixel, and its edges come out as fine noise instead.
static inline long deep_low(uint16_t value, long alpha, size_t x, size_t y, int channel) {
    long low = (long)floorf((float)value * (255.0f / 65535.0f) + deep_noise(x, y, channel)) - 1;
    return low < 0 ? 0 : low > alpha ? alpha : low;
}

// How far the color is above `low`, in 8-bit steps: 0 up to 2.
static inline float deep_past(uint16_t value, long low) {
    return fminf(2, fmaxf(0, (float)value * (255.0f / 65535.0f) - (float)low));
}

// How an input channel moves an output one, from the runs with it at `low` (`l`), one, two and four steps up (`s1`, `s2`,
// `s4`), the color `past` steps above `low`, and the steps alpha left room for (`room`).
//
// A straight line fitted through all four runs, where they lie near one: the operation's results being 8-bit too say
// little across one step, and one that works at 8 bits inside (Camera Raw) wobbles from one 8-bit value to the next,
// which read step by step came out as faint bands. Where they don't (a bend: a steep Levels clipping to white), read off
// the straight line between the steps the color lies between, exact wherever the operation is straight across one step.
// The fit gives the change, and `offset`: where it puts `low`'s result against that run's own rounded one.
typedef struct { float change; float offset; int fitted; } DeepChange;

static inline DeepChange deep_change(float l, float s1, float s2, float s4, float past, long room) {
    DeepChange none = { 0, 0, 0 };
    if (room <= 0) return none;
    DeepChange steps = { room == 1 || past < 1 ? (s1 - l) * fminf(past, 1) : (s1 - l) + (s2 - s1) * (past - 1), 0, 0 };
    // Too near alpha for the far runs: the steps there are.
    if (room < 4) return steps;
    // Least squares through (0, l), (1, s1), (2, s2), (4, s4): the steps' mean is 1.75, their spread 8.75.
    float mean = (l + s1 + s2 + s4) / 4;
    float slope = (-1.75f * l - 0.75f * s1 + 0.25f * s2 + 2.25f * s4) / 8.75f;
    float start = mean - slope * 1.75f;
    // A run more than a step off the line (8-bit rounding and wobble stay under one) is a bend.
    float off = fmaxf(fmaxf(fabsf(l - start), fabsf(s1 - start - slope)), fmaxf(fabsf(s2 - start - 2 * slope), fabsf(s4 - start - 4 * slope)));
    if (off > 1) return steps;
    DeepChange fit = { slope * past, start - l, 1 };
    return fit;
}
void deep_split(const uint16_t *deep, size_t deepStride, uint8_t *out, size_t stride, size_t width, size_t height,
                int step, int channel) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)deep + y * deepStride);
            uint8_t *o = out + y * stride;
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                long alpha = deep_alpha8(p[3]);
                for (int c = 0; c < 3; ++c) {
                    long value = deep_low(p[c], alpha, x, y, c) + (channel < 0 || channel == c ? step : 0);
                    o[x * 4 + c] = (uint8_t)(value > alpha ? alpha : value);
                }
                o[x * 4 + 3] = (uint8_t)alpha;
            }
        }
    });
}

void deep_merge(const uint16_t *deep, size_t deepStride, const uint8_t *lowResult, const uint8_t *const nearResults[3],
                const uint8_t *const midResults[3], const uint8_t *const farResults[3], size_t stride, uint16_t *out,
                size_t outStride, size_t width, size_t height, int mixes) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)deep + y * deepStride);
            const uint8_t *lo = lowResult + y * stride;
            uint16_t *o = (uint16_t *)((uint8_t *)out + y * outStride);
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                long alpha = deep_alpha8(p[3]);
                float outAlpha = (float)lo[x * 4 + 3] * 257.0f;
                float past[3];
                long room[3];
                for (int k = 0; k < 3; ++k) {
                    long low = deep_low(p[k], alpha, x, y, k);
                    past[k] = deep_past(p[k], low);
                    room[k] = alpha - low;
                }
                size_t i = y * stride + x * 4;
                for (int c = 0; c < 3; ++c) {
                    float l = lo[x * 4 + c], value = l, offset = 0;
                    int fits = 0;
                    // Each input channel's own runs move this output channel (only its own, unless they mix). Each fit
                    // also says where `low`'s result really lies; they all say it of the same run, so averaged.
                    for (int k = mixes ? 0 : c; k < (mixes ? 3 : c + 1); ++k) {
                        int r = mixes ? k : 0;
                        DeepChange change = deep_change(l, nearResults[r][i + c], midResults[r][i + c], farResults[r][i + c],
                                                        past[k], room[k]);
                        value += change.change;
                        if (change.fitted) { offset += change.offset; fits += 1; }
                    }
                    if (fits) value += offset / (float)fits;
                    float scaled = value * 257.0f;
                    o[x * 4 + c] = (uint16_t)lroundf(scaled < 0 ? 0 : scaled > outAlpha ? outAlpha : scaled);
                }
                o[x * 4 + 3] = (uint16_t)lroundf(outAlpha);
            }
        }
    });
}

void deep_take_painted(uint16_t *deep, size_t deepStride, const uint8_t *painted, const uint8_t *base, size_t stride,
                       size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *d = (uint16_t *)((uint8_t *)deep + y * deepStride);
            const uint8_t *p = painted + y * stride, *b = base + y * stride;
            for (size_t x = 0; x < width * 4; x += 4) {
                if (p[x] == b[x] && p[x + 1] == b[x + 1] && p[x + 2] == b[x + 2] && p[x + 3] == b[x + 3]) continue;
                for (int c = 0; c < 4; ++c) d[x + c] = (uint16_t)(p[x + c] * 257);
            }
        }
    });
}

void deep_extract_alpha(uint16_t *rgba, size_t stride, uint16_t *alpha, size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)rgba + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                uint32_t a = p[3];
                alpha[y * width + x] = (uint16_t)a;
                for (int c = 0; c < 3; ++c) {
                    uint32_t v = a ? (p[c] * 65535u + a / 2) / a : 0;
                    p[c] = (uint16_t)(v > 65535 ? 65535 : v);
                }
                p[3] = 65535;
            }
        }
    });
}

void deep_restore_alpha(uint16_t *rgba, size_t stride, const uint16_t *alpha, size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)rgba + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                uint32_t a = alpha[y * width + x];
                for (int c = 0; c < 3; ++c) p[c] = (uint16_t)((p[c] * a + 32767u) / 65535u);
                p[3] = (uint16_t)a;
            }
        }
    });
}

void deep_cube_apply(uint16_t *pixels, size_t stride, size_t width, size_t height, const float *cube, int dimension) {
    const float scale = (dimension - 1) / 65535.0f;
    const size_t dy = dimension, dz = (size_t)dimension * dimension;
    const size_t sx = 4, sy = dy * 4, sz = dz * 4;
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)pixels + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                float alpha = p[3];
                if (!alpha) continue;
                float fraction[3];
                int lo[3];
                for (int channel = 0; channel < 3; ++channel) {
                    float position = fminf(65535, p[channel] * 65535.0f / alpha) * scale;
                    lo[channel] = (int)position;
                    if (lo[channel] > dimension - 2) lo[channel] = dimension - 2;
                    fraction[channel] = position - lo[channel];
                }
                const float *base = cube + ((size_t)lo[0] + lo[1] * dy + lo[2] * dz) * 4;
                for (int channel = 0; channel < 3; ++channel) {
                    const float *c = base + channel;
                    float x00 = c[0] + (c[sx] - c[0]) * fraction[0];
                    float x10 = c[sy] + (c[sy + sx] - c[sy]) * fraction[0];
                    float x01 = c[sz] + (c[sz + sx] - c[sz]) * fraction[0];
                    float x11 = c[sz + sy] + (c[sz + sy + sx] - c[sz + sy]) * fraction[0];
                    float y0 = x00 + (x10 - x00) * fraction[1];
                    float y1 = x01 + (x11 - x01) * fraction[1];
                    float result = y0 + (y1 - y0) * fraction[2];
                    p[channel] = (uint16_t)fminf(alpha, fmaxf(0, roundf(result * alpha)));
                }
            }
        }
    });
}

// A half float's value (IEEE 754 binary16), portably: Intel builds have no half type to lean on.
static inline float deep_half(uint16_t bits) {
    uint32_t sign = (uint32_t)(bits >> 15) << 31, exponent = (bits >> 10) & 0x1f, mantissa = bits & 0x3ff;
    union { uint32_t u; float f; } out;
    if (exponent == 0) {
        // Zero or subnormal: mantissa × 2⁻²⁴.
        float value = (float)mantissa * (1.0f / 16777216.0f);
        return sign ? -value : value;
    }
    if (exponent == 31) out.u = sign | 0x7f800000u | (mantissa << 13);
    else out.u = sign | ((exponent + 112) << 23) | (mantissa << 13);
    return out.f;
}

float deep_half_peak(const uint16_t *pixels, size_t stride, size_t width, size_t height) {
    float peak = 0;
    for (size_t y = 0; y < height; ++y) {
        const uint16_t *row = (const uint16_t *)((const uint8_t *)pixels + y * stride);
        for (size_t x = 0; x < width; ++x) {
            const uint16_t *p = row + x * 4;
            float alpha = deep_half(p[3]);
            if (!(alpha > 0)) continue;
            for (int c = 0; c < 3; ++c) {
                float value = deep_half(p[c]) / alpha;
                if (value > peak && value < INFINITY) peak = value;
            }
        }
    }
    return peak;
}

// A float as a half float's bits (IEEE 754 binary16, rounded to nearest), portably.
static inline uint16_t deep_to_half(float value) {
    union { float f; uint32_t u; } in = { value };
    uint32_t sign = (in.u >> 16) & 0x8000, exponent = (in.u >> 23) & 0xff, mantissa = in.u & 0x7fffff;
    if (exponent == 0xff) return (uint16_t)(sign | 0x7c00 | (mantissa ? 0x200 : 0));
    int e = (int)exponent - 127 + 15;
    if (e >= 31) return (uint16_t)(sign | 0x7c00);
    if (e <= 0) {
        // Subnormal or zero.
        if (e < -10) return (uint16_t)sign;
        mantissa |= 0x800000;
        uint32_t shift = (uint32_t)(14 - e);
        uint32_t half = mantissa >> shift, rest = mantissa & ((1u << shift) - 1), halfway = 1u << (shift - 1);
        if (rest > halfway || (rest == halfway && (half & 1))) half += 1;
        return (uint16_t)(sign | half);
    }
    uint32_t half = sign | ((uint32_t)e << 10) | (mantissa >> 13), rest = mantissa & 0x1fff;
    if (rest > 0x1000 || (rest == 0x1000 && (half & 1))) half += 1;
    return (uint16_t)half;
}

void deep_hdr_normalize(const uint16_t *hdr, size_t hdrStride, uint16_t *out, size_t outStride, float *scales,
                        size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)hdr + y * hdrStride);
            uint16_t *o = (uint16_t *)((uint8_t *)out + y * outStride);
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                float alpha = fminf(1, fmaxf(0, deep_half(p[3]))), color[3], brightest = 0;
                for (int c = 0; c < 3; ++c) {
                    color[c] = alpha > 0 ? fmaxf(0, deep_half(p[c]) / alpha) : 0;
                    if (color[c] > brightest && color[c] < INFINITY) brightest = color[c];
                }
                float scale = brightest > 1 ? brightest : 1;
                scales[y * width + x] = scale;
                for (int c = 0; c < 3; ++c) o[x * 4 + c] = (uint16_t)lroundf(fminf(1, color[c] / scale) * alpha * 65535.0f);
                o[x * 4 + 3] = (uint16_t)lroundf(alpha * 65535.0f);
            }
        }
    });
}

void deep_hdr_restore(const uint16_t *normal, size_t normalStride, const float *scales, uint16_t *hdr, size_t hdrStride,
                      size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            const uint16_t *in = (const uint16_t *)((const uint8_t *)normal + y * normalStride);
            uint16_t *o = (uint16_t *)((uint8_t *)hdr + y * hdrStride);
            for (size_t x = 0; x < width; ++x) {
                const uint16_t *p = in + x * 4;
                // Premultiplied colors scale with their alpha: the brightness factor applies to them as they are.
                float scale = scales[y * width + x];
                for (int c = 0; c < 3; ++c) o[x * 4 + c] = deep_to_half((float)p[c] / 65535.0f * scale);
                o[x * 4 + 3] = deep_to_half((float)p[3] / 65535.0f);
            }
        }
    });
}

// sRGB's curve, carried on past white (and mirrored below black) as extended sRGB does.
static inline float deep_linear(float encoded) {
    float magnitude = fabsf(encoded);
    float linear = magnitude <= 0.04045f ? magnitude / 12.92f : powf((magnitude + 0.055f) / 1.055f, 2.4f);
    return encoded < 0 ? -linear : linear;
}
static inline float deep_encoded(float linear) {
    float magnitude = fabsf(linear);
    float encoded = magnitude <= 0.0031308f ? magnitude * 12.92f : 1.055f * powf(magnitude, 1 / 2.4f) - 0.055f;
    return linear < 0 ? -encoded : encoded;
}

void deep_hdr_exposure(uint16_t *hdr, size_t stride, size_t width, size_t height, float scale, float offset, float inverseGamma) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)hdr + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                float alpha = deep_half(p[3]);
                if (!(alpha > 0)) continue;
                for (int c = 0; c < 3; ++c) {
                    float linear = fmaxf(0, deep_linear(deep_half(p[c]) / alpha) * scale + offset);
                    p[c] = deep_to_half(deep_encoded(powf(linear, inverseGamma)) * alpha);
                }
            }
        }
    });
}

void deep_take_painted_hdr(uint16_t *hdr, size_t hdrStride, const uint8_t *painted, const uint8_t *base, size_t stride,
                           size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *d = (uint16_t *)((uint8_t *)hdr + y * hdrStride);
            const uint8_t *p = painted + y * stride, *b = base + y * stride;
            for (size_t x = 0; x < width * 4; x += 4) {
                if (p[x] == b[x] && p[x + 1] == b[x + 1] && p[x + 2] == b[x + 2] && p[x + 3] == b[x + 3]) continue;
                for (int c = 0; c < 4; ++c) d[x + c] = deep_to_half((float)p[x + c] / 255.0f);
            }
        }
    });
}

void deep_extract_alpha_hdr(uint16_t *rgba, size_t stride, float *alpha, size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)rgba + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                float a = deep_half(p[3]);
                alpha[y * width + x] = a;
                for (int c = 0; c < 3; ++c) p[c] = deep_to_half(a > 0 ? deep_half(p[c]) / a : 0);
                p[3] = deep_to_half(1);
            }
        }
    });
}

void deep_restore_alpha_hdr(uint16_t *rgba, size_t stride, const float *alpha, size_t width, size_t height) {
    deep_rows(height, ^(size_t first, size_t last) {
        for (size_t y = first; y < last; ++y) {
            uint16_t *p = (uint16_t *)((uint8_t *)rgba + y * stride);
            for (size_t x = 0; x < width; ++x, p += 4) {
                float a = alpha[y * width + x];
                for (int c = 0; c < 3; ++c) p[c] = deep_to_half(deep_half(p[c]) * a);
                p[3] = deep_to_half(a);
            }
        }
    });
}
