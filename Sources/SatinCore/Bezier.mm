//
//  Bezier.c
//  Satin
//
//  Created by Reza Ali on 6/28/20.
//

#include <algorithm>
#include <malloc/_malloc.h>
#include <string.h>

#include "Bezier.h"

Polyline2D createEmptyPolyline2D() { return (Polyline2D) { .count = 0, .data = NULL }; }
Polylines2D createEmptyPolylines2D() { return (Polylines2D) { .count = 0, .data = NULL }; }

void freePolyline2D(Polyline2D *line) {
    if (line->capacity > 0 && line->data != NULL) {
        free(line->data);
        line->data = NULL;
        line->count = 0;
        line->capacity = 0;
    }
}

void freePolylines2D(Polylines2D *lines) {
    if (lines->count > 0 && lines->data != NULL) {
        for (int i = 0; i < lines->count; i++) {
            freePolyline2D(&lines->data[i]);
        }

        free(lines->data);
        lines->data = NULL;
        lines->count = 0;
    }
}

Polyline3D createEmptyPolyline3D() { return (Polyline3D) { .count = 0, .data = NULL }; }
Polylines3D createEmptyPolylines3D() { return (Polylines3D) { .count = 0, .data = NULL }; }

void freePolyline3D(Polyline3D *line) {
    if (line->capacity > 0 && line->data != NULL) {
        free(line->data);
        line->data = NULL;
        line->count = 0;
        line->capacity = 0;
    }
}

void freePolylines3D(Polylines3D *lines) {
    if (lines->count > 0 && lines->data != NULL) {
        for (int i = 0; i < lines->count; i++) {
            freePolyline3D(&lines->data[i]);
        }

        free(lines->data);
        lines->data = NULL;
        lines->count = 0;
    }
}

void addPointToPolyline2D(simd_float2 p, Polyline2D *line) {
    if (line->data == nullptr) {
        line->capacity = (line->capacity + 1) * 2;
        line->data = (simd_float2 *)malloc(line->capacity * sizeof(simd_float2));
    } else if ((line->count + 1) >= line->capacity) {
        line->capacity = (line->capacity + 1) * 2;
        line->data = (simd_float2 *)realloc(line->data, line->capacity * sizeof(simd_float2));
    }

    line->data[line->count] = p;
    line->count++;
}

void removeFirstPointInPolyline2D(Polyline2D *line) {
    if (line->count > 0 && line->data != NULL) {
        line->count--;
        if (line->count > 0) {
            memmove(line->data, line->data + 1, line->count * sizeof(simd_float2));
        } else {
            freePolyline2D(line);
        }
    }
}

void removeLastPointInPolyline2D(Polyline2D *line) {
    if (line->count > 0 && line->data != NULL) {
        line->count--;
        if (line->count == 0) { freePolyline2D(line); }
    }
}

void appendPolyline2D(Polyline2D *dst, Polyline2D *src) {
    if ((dst->capacity - dst->count) > src->count) {
        memcpy(dst->data + dst->count, src->data, src->count * sizeof(simd_float2));
    } else {
        dst->capacity += src->count;
        dst->data = (simd_float2 *)realloc(dst->data, dst->capacity * sizeof(simd_float2));
        memcpy(dst->data + dst->count, src->data, src->count * sizeof(simd_float2));
    }
    dst->count += src->count;
}

void addPointToPolyline3D(simd_float3 p, Polyline3D *line) {
    if (line->data == nullptr) {
        line->capacity = (line->capacity + 1) * 2;
        line->data = (simd_float3 *)malloc(line->capacity * sizeof(simd_float3));
    } else if ((line->count + 1) >= line->capacity) {
        line->capacity = (line->capacity + 1) * 2;
        line->data = (simd_float3 *)realloc(line->data, line->capacity * sizeof(simd_float3));
    }

    line->data[line->count] = p;
    line->count++;
}

void removeFirstPointInPolyline3D(Polyline3D *line) {
    if (line->count > 0 && line->data != NULL) {
        line->count--;
        if (line->count > 0) {
            memmove(line->data, line->data + 1, line->count * sizeof(simd_float3));
        } else {
            freePolyline3D(line);
        }
    }
}

void removeLastPointInPolyline3D(Polyline3D *line) {
    if (line->count > 0 && line->data != NULL) {
        line->count--;
        if (line->count == 0) { freePolyline3D(line); }
    }
}

void appendPolyline3D(Polyline3D *dst, Polyline3D *src) {
    if ((dst->capacity - dst->count) > src->count) {
        memcpy(dst->data + dst->count, src->data, src->count * sizeof(simd_float3));
    } else {
        dst->capacity += src->count;
        dst->data = (simd_float3 *)realloc(dst->data, dst->capacity * sizeof(simd_float3));
        memcpy(dst->data + dst->count, src->data, src->count * sizeof(simd_float3));
    }
    dst->count += src->count;
}

#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))

Polyline2D getLinearPath2(simd_float2 a, simd_float2 b, int res) {
    simd_float2 *data = (simd_float2 *)malloc(res * sizeof(simd_float2));
    const float resMinusOne = res - 1;
    for (int i = 0; i < res; i++) {
        const float t = (float)i / resMinusOne;
        data[i] = simd_mix(a, b, t);
    }

    return (Polyline2D) { .count = res, .capacity = res, .data = data };
}

Polyline2D getAdaptiveLinearPath2(simd_float2 a, simd_float2 b, float distanceLimit) {
    const float length = simd_length(b - a);
    if (length > distanceLimit) {
        const int sections = MAX(ceilf(length / distanceLimit), 2);
        const float inc = 1.0 / (float)(sections - 1);
        simd_float2 *data = (simd_float2 *)malloc(sections * sizeof(simd_float2));
        simd_float2 t = 0.0;
        for (int i = 0; i < sections; i++) {
            data[i] = simd_mix(a, b, t);
            t += inc;
            t = MIN(MAX(t, 0.0), 1.0);
        }

        return (Polyline2D) { .count = sections, .capacity = sections, .data = data };
    } else {
        simd_float2 *data = (simd_float2 *)malloc(2 * sizeof(simd_float2));
        data[0] = a;
        data[1] = b;

        return (Polyline2D) { .count = 2, .capacity = 2, .data = data };
    }
}

simd_float2 quadraticBezier2(simd_float2 a, simd_float2 b, simd_float2 c, float t) {
    float oneMinusT = 1.0 - t;
    return oneMinusT * oneMinusT * a + 2.0 * oneMinusT * t * b + t * t * c;
}

simd_float2 quadraticBezierVelocity2(simd_float2 a, simd_float2 b, simd_float2 c, float t) {
    float oneMinusT = 1.0 - t;
    return 2.0 * oneMinusT * (b - a) + 2 * t * (c - b);
}

simd_float2 quadraticBezierAcceleration2(simd_float2 a, simd_float2 b, simd_float2 c, float t) {
    return 2.0 * (c - 2.0 * b + a);
}

float quadraticBezierCurvature2(simd_float2 a, simd_float2 b, simd_float2 c, float t) {
    simd_float3 vel = simd_make_float3(quadraticBezierVelocity2(a, b, c, t), 0.0);
    simd_float3 acc = simd_make_float3(quadraticBezierAcceleration2(a, b, c, t), 0.0);
    return simd_length(simd_cross(vel, acc)) / pow(simd_length(vel), 3.0);
}

Polyline2D getQuadraticBezierPath2(simd_float2 a, simd_float2 b, simd_float2 c, int res) {
    simd_float2 *data = (simd_float2 *)malloc(res * sizeof(simd_float2));
    const float resMinusOne = res - 1;
    for (int i = 0; i < res; i++) {
        const float t = (float)i / resMinusOne;
        data[i] = quadraticBezier2(a, b, c, t);
    }
    return (Polyline2D) { .count = res, .capacity = res, .data = data };
}

void _adaptiveQuadraticBezierCurve2(
    simd_float2 a,
    simd_float2 b,
    simd_float2 c,
    simd_float2 aVel,
    simd_float2 bVel,
    simd_float2 cVel,
    float angleLimit,
    int depth,
    Polyline2D *line) {
    if (depth > 8) { return; }

    const float startMiddleAngle = acos(simd_dot(aVel, bVel));
    const float middleEndAngle = acos(simd_dot(bVel, cVel));

    if ((startMiddleAngle + middleEndAngle) > angleLimit) {
        // Split curve into two curves (start, end)

        const simd_float2 ab = (a + b) * 0.5;
        const simd_float2 bc = (b + c) * 0.5;
        const simd_float2 abc = (ab + bc) * 0.5;

        // Start Curve:  a,      ab,     abc
        // End Curve:    abc,    bc,     c

        const simd_float2 sVel = simd_normalize(quadraticBezierVelocity2(a, ab, abc, 0.5));
        _adaptiveQuadraticBezierCurve2(a, ab, abc, aVel, sVel, bVel, angleLimit, depth + 1, line);

        addPointToPolyline2D(abc, line);

        const simd_float2 eVel = simd_normalize(quadraticBezierVelocity2(abc, bc, c, 0.5));
        _adaptiveQuadraticBezierCurve2(abc, bc, c, bVel, eVel, cVel, angleLimit, depth + 1, line);
    }
}

Polyline2D
getAdaptiveQuadraticBezierPath2(simd_float2 a, simd_float2 b, simd_float2 c, float angleLimit) {
    const simd_float2 aVel = simd_normalize(quadraticBezierVelocity2(a, b, c, 0.0));
    const simd_float2 bVel = simd_normalize(quadraticBezierVelocity2(a, b, c, 0.5));
    const simd_float2 cVel = simd_normalize(quadraticBezierVelocity2(a, b, c, 1.0));

    Polyline2D line = {};
    addPointToPolyline2D(a, &line);
    _adaptiveQuadraticBezierCurve2(a, b, c, aVel, bVel, cVel, angleLimit, 0, &line);
    addPointToPolyline2D(c, &line);

    return line;
}

float cubicBezier1(float a, float b, float c, float d, float t) {
    float oneMinusT = 1.0 - t;
    float oneMinusT2 = oneMinusT * oneMinusT;
    float oneMinusT3 = oneMinusT2 * oneMinusT;
    return oneMinusT3 * a + 3.0 * oneMinusT2 * t * b + 3.0 * oneMinusT * t * t * c + t * t * t * d;
}

simd_float2 cubicBezier2(simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, float t) {
    float oneMinusT = 1.0 - t;
    float oneMinusT2 = oneMinusT * oneMinusT;
    float oneMinusT3 = oneMinusT2 * oneMinusT;
    return oneMinusT3 * a + 3.0 * oneMinusT2 * t * b + 3.0 * oneMinusT * t * t * c + t * t * t * d;
}

simd_float2
cubicBezierVelocity2(simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, float t) {
    float oneMinusT = 1.0 - t;
    float oneMinusT2 = oneMinusT * oneMinusT;
    return 3.0 * oneMinusT2 * (b - a) + 6.0 * oneMinusT * t * (c - b) + 3.0 * t * t * (d - c);
}

simd_float2
cubicBezierAcceleration2(simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, float t) {
    return 6.0 * (1.0 - t) * (c - 2.0 * b + a) + 6.0 * t * (d - 2.0 * c + b);
}

float cubicBezierCurvature2(simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, float t) {
    const simd_float3 vel = simd_make_float3(cubicBezierVelocity2(a, b, c, d, t), 0.0);
    const simd_float3 acc = simd_make_float3(cubicBezierAcceleration2(a, b, c, d, t), 0.0);
    return simd_length(simd_cross(vel, acc)) / pow(simd_length(vel), 3.0);
}

Polyline2D
getCubicBezierPath2(simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, int res) {
    simd_float2 *data = (simd_float2 *)malloc(res * sizeof(simd_float2));
    const float resMinusOne = res - 1;
    for (int i = 0; i < res; i++) {
        const float t = (float)i / resMinusOne;
        data[i] = cubicBezier2(a, b, c, d, t);
    }
    return (Polyline2D) { .count = res, .capacity = res, .data = data };
}

void _adaptiveCubicBezierCurve2(
    simd_float2 a,
    simd_float2 b,
    simd_float2 c,
    simd_float2 d,
    simd_float2 aVel,
    simd_float2 bVel,
    simd_float2 cVel,
    float angleLimit,
    int depth,
    Polyline2D *line) {
    if (depth > 8) { return; }

    const float startMiddleAngle = acos(simd_dot(aVel, bVel));
    const float middleEndAngle = acos(simd_dot(bVel, cVel));

    if ((startMiddleAngle + middleEndAngle) > angleLimit) {
        // Split curve into two curves (start, end)

        const simd_float2 ab = (a + b) * 0.5;
        const simd_float2 bc = (b + c) * 0.5;
        const simd_float2 cd = (c + d) * 0.5;
        const simd_float2 abc = (ab + bc) * 0.5;
        const simd_float2 bcd = (bc + cd) * 0.5;
        const simd_float2 abcd = (abc + bcd) * 0.5;

        // Start Curve:  a,      ab,     abc,    abcd
        // End Curve:    abcd,   bcd,    cd,     d

        const simd_float2 sVel = simd_normalize(cubicBezierVelocity2(a, ab, abc, abcd, 0.5));
        _adaptiveCubicBezierCurve2(a, ab, abc, abcd, aVel, sVel, bVel, angleLimit, depth + 1, line);

        addPointToPolyline2D(abcd, line);

        const simd_float2 eVel = simd_normalize(cubicBezierVelocity2(abcd, bcd, cd, d, 0.5));
        _adaptiveCubicBezierCurve2(abcd, bcd, cd, d, bVel, eVel, cVel, angleLimit, depth + 1, line);
    }
}

void _adaptiveCubicBezierCurve3(
    simd_float3 a,
    simd_float3 b,
    simd_float3 c,
    simd_float3 d,
    simd_float3 aVel,
    simd_float3 bVel,
    simd_float3 cVel,
    float angleLimit,
    int depth,
    Polyline3D *line) {
    if (depth > 8) { return; }

    // Clamped: rounding can push a dot product of unit vectors past 1, and acos of that is NaN.
    const float startMiddleAngle = acos(simd_clamp(simd_dot(aVel, bVel), -1.0f, 1.0f));
    const float middleEndAngle = acos(simd_clamp(simd_dot(bVel, cVel), -1.0f, 1.0f));

    if ((startMiddleAngle + middleEndAngle) > angleLimit) {
        // Split curve into two curves (start, end)

        const simd_float3 ab = (a + b) * 0.5;
        const simd_float3 bc = (b + c) * 0.5;
        const simd_float3 cd = (c + d) * 0.5;
        const simd_float3 abc = (ab + bc) * 0.5;
        const simd_float3 bcd = (bc + cd) * 0.5;
        const simd_float3 abcd = (abc + bcd) * 0.5;

        // Start Curve:  a,      ab,     abc,    abcd
        // End Curve:    abcd,   bcd,    cd,     d

        const simd_float3 sVel = simd_normalize(cubicBezierVelocity3(a, ab, abc, abcd, 0.5));
        _adaptiveCubicBezierCurve3(a, ab, abc, abcd, aVel, sVel, bVel, angleLimit, depth + 1, line);

        addPointToPolyline3D(abcd, line);

        const simd_float3 eVel = simd_normalize(cubicBezierVelocity3(abcd, bcd, cd, d, 0.5));
        _adaptiveCubicBezierCurve3(abcd, bcd, cd, d, bVel, eVel, cVel, angleLimit, depth + 1, line);
    }
}

// The direction a cubic leaves `a`: toward its first control point or, when that point sits on
// `a` (a collapsed handle, zero velocity), toward the next one that does not. The direction it
// arrives at `d` mirrors this. Normalizing a zero velocity instead gives NaN, which stops the
// adaptive split and draws the curve as a straight line. A handle counts as collapsed when it is
// shorter than a millionth of the curve's own extent, so the test does not depend on its units.
// Only the 3D sampler (BezierPath) does this: text samples glyphs with the 2D ones, whose
// triangulation depends on their existing output.
static simd_float3 cubicStartDirection3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float collapsedSquared) {
    if (simd_distance_squared(a, b) > collapsedSquared) { return simd_normalize(b - a); }
    if (simd_distance_squared(a, c) > collapsedSquared) { return simd_normalize(c - a); }
    return simd_normalize(d - a);
}

static simd_float3 cubicEndDirection3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float collapsedSquared) {
    if (simd_distance_squared(c, d) > collapsedSquared) { return simd_normalize(d - c); }
    if (simd_distance_squared(b, d) > collapsedSquared) { return simd_normalize(d - b); }
    return simd_normalize(d - a);
}

Polyline2D getAdaptiveCubicBezierPath2(
    simd_float2 a, simd_float2 b, simd_float2 c, simd_float2 d, float angleLimit) {
    const simd_float2 aVel = simd_normalize(cubicBezierVelocity2(a, b, c, d, 0.0));
    const simd_float2 bVel = simd_normalize(cubicBezierVelocity2(a, b, c, d, 0.5));
    const simd_float2 cVel = simd_normalize(cubicBezierVelocity2(a, b, c, d, 1.0));

    Polyline2D line = {};
    addPointToPolyline2D(a, &line);
    _adaptiveCubicBezierCurve2(a, b, c, d, aVel, bVel, cVel, angleLimit, 0, &line);
    addPointToPolyline2D(d, &line);

    return line;
}

simd_float3 cubicBezier3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float t) {
    float oneMinusT = 1.0 - t;
    return oneMinusT * oneMinusT * oneMinusT * a + 3.0 * oneMinusT * oneMinusT * t * b +
           3.0 * oneMinusT * t * t * c + t * t * t * d;
}

simd_float3
cubicBezierVelocity3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float t) {
    float oneMinusT = 1.0 - t;
    float oneMinusT2 = oneMinusT * oneMinusT;
    return 3.0 * oneMinusT2 * (b - a) + 6.0 * oneMinusT * t * (c - b) + 3.0 * t * t * (d - c);
}

simd_float3
cubicBezierAcceleration3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float t) {
    return 6.0 * (1.0 - t) * (c - 2.0 * b + a) + 6.0 * t * (d - 2.0 * c + b);
}

simd_float3 cubicBezierJerk3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float t) {
    return 6.0 * (d - c - b + a);
}

float cubicBezierCurvature3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float t) {
    const simd_float3 vel = cubicBezierVelocity3(a, b, c, d, t);
    const simd_float3 acc = cubicBezierAcceleration3(a, b, c, d, t);
    return simd_length(simd_cross(vel, acc)) / pow(simd_length(vel), 3.0);
}

Polyline3D
getCubicBezierPath3(simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, int res) {
    simd_float3 *data = (simd_float3 *)malloc(res * sizeof(simd_float3));
    const float resMinusOne = res - 1;
    for (int i = 0; i < res; i++) {
        const float t = (float)i / resMinusOne;
        data[i] = cubicBezier3(a, b, c, d, t);
    }
    return (Polyline3D) { .count = res, .capacity = res, .data = data };
}

Polyline3D getAdaptiveCubicBezierPath3(
    simd_float3 a, simd_float3 b, simd_float3 c, simd_float3 d, float angleLimit) {
    Polyline3D line = createEmptyPolyline3D();
    addPointToPolyline3D(a, &line);
    // The curve's extent: how far its control points spread from `a`.
    const float extentSquared = std::max({ simd_distance_squared(a, b), simd_distance_squared(a, c), simd_distance_squared(a, d) });
    // All four points coincide: a point, with no direction to measure turns by.
    if (extentSquared > 0.0f) {
        const float collapsedSquared = extentSquared * 1e-12f;
        const simd_float3 aVel = cubicStartDirection3(a, b, c, d, collapsedSquared);
        const simd_float3 bVel = simd_normalize(cubicBezierVelocity3(a, b, c, d, 0.5));
        const simd_float3 cVel = cubicEndDirection3(a, b, c, d, collapsedSquared);
        _adaptiveCubicBezierCurve3(a, b, c, d, aVel, bVel, cVel, angleLimit, 0, &line);
    }
    addPointToPolyline3D(d, &line);

    return line;
}

simd_float3 quadraticBezier3(simd_float3 a, simd_float3 b, simd_float3 c, float t) {
    float oneMinusT = 1.0 - t;
    return oneMinusT * oneMinusT * a + 2.0 * oneMinusT * t * b + t * t * c;
}

Polyline3D convertPolyline2DToPolyline3D(Polyline2D *line) {
    const int count = line->count;

    Polyline3D result;
    result.capacity = count;
    result.count = count;
    result.data = (simd_float3 *)malloc(count * sizeof(simd_float3));
    for (int i = 0; i < count; i++) {
        result.data[i] = simd_make_float3(line->data[i], 0.0);
    }

    return result;
}
