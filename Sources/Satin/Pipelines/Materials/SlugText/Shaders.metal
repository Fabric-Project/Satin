#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 color;
} SlugTextUniforms;

typedef struct {
    float4 position [[position]];
    float2 texcoord;
    float2 cornerNormal;
    float4 bandTransform [[flat]];
    int4 glyph [[flat]];
} SlugTextVertexData;

constexpr constant int kLogBandTextureWidth = 12;
constexpr constant int kBandTextureWidth = 1 << kLogBandTextureWidth;

static float2x2 make_float2x2(float4 value) {
    return float2x2(value.xy, value.zw);
}

static float2 dilate(
    float2 position,
    float2 cornerNormal,
    float2 texcoord,
    float2x2 inverseJacobian,
    float4x4 mvpTranspose,
    float2 viewportSize,
    thread float2 &outDilatedPosition
) {
    float4 m0 = mvpTranspose[0];
    float4 m1 = mvpTranspose[1];
    float4 m3 = mvpTranspose[3];

    float2 normal = normalize(cornerNormal);
    float s = dot(m3.xy, position) + m3.w;
    float t = dot(m3.xy, normal);

    float u = (s * dot(m0.xy, normal) - t * (dot(m0.xy, position) + m0.w)) * viewportSize.x;
    float v = (s * dot(m1.xy, normal) - t * (dot(m1.xy, position) + m1.w)) * viewportSize.y;

    float s2 = s * s;
    float st = s * t;
    float uv = u * u + v * v;
    float2 direction = cornerNormal * (s2 * (st + sqrt(uv)) / (uv - st * st));

    outDilatedPosition = position + direction;
    return texcoord + inverseJacobian * direction;
}

static inline int4 unpackGlyph(float2 packed) {
    uint2 values = as_type<uint2>(packed);
    return int4(
        int(values.x & 0xFFFFu),
        int(values.x >> 16u),
        int(values.y & 0xFFFFu),
        int(values.y >> 16u)
    );
}

vertex SlugTextVertexData slugTextVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]
) {
    const float2 viewportSize = max(vertexUniforms[amp_id].viewport.zw, float2(1.0));
    const float4x4 transform =
#if INSTANCING
        vertexUniforms[amp_id].viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix;
#else
        vertexUniforms[amp_id].modelViewProjectionMatrix;
#endif

    float2 dilatedPosition = 0.0;
    float2 dilatedUV = dilate(
        in.position.xy,
        in.custom1.xy,
        in.custom0.xy,
        make_float2x2(in.custom2),
        transpose(transform),
        viewportSize,
        dilatedPosition
    );

    SlugTextVertexData out;
    out.position = transform * float4(dilatedPosition, 0.0, 1.0);
    out.texcoord = dilatedUV;
    out.cornerNormal = in.custom1.xy;
    out.bandTransform = in.custom3;
    out.glyph = unpackGlyph(in.custom0.zw);
    return out;
}

static uint classifyRoots(float y1, float y2, float y3) {
    uint i1 = as_type<uint>(y1) >> 31u;
    uint i2 = as_type<uint>(y2) >> 30u;
    uint i3 = as_type<uint>(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return (0x2E74u >> shift) & 0x0101u;
}

static float2 solvePolynomial(float2 p1, float2 p2, float2 p3, int axis) {
    float2 a = p1 - p2 * 2.0f + p3;
    float2 b = p1 - p2;
    float discriminant = sqrt(max(b[1 - axis] * b[1 - axis] - a[1 - axis] * p1[1 - axis], 0.0f));
    float reciprocalA = 1.0f / a[1 - axis];
    float t1 = (b[1 - axis] - discriminant) * reciprocalA;
    float t2 = (b[1 - axis] + discriminant) * reciprocalA;
    if (abs(a[1 - axis]) < 1e-5) {
        float reciprocal2B = 1.0f / (b[1 - axis] * 2.0f);
        t1 = p1[1 - axis] * reciprocal2B;
        t2 = p1[1 - axis] * reciprocal2B;
    }
    return float2(
        (a[axis] * t1 - b[axis] * 2.0f) * t1 + p1[axis],
        (a[axis] * t2 - b[axis] * 2.0f) * t2 + p1[axis]
    );
}

static int2 lookupBand(int2 glyphLocation, uint offset) {
    int2 location = int2(glyphLocation.x + int(offset), glyphLocation.y);
    location.y += location.x >> kLogBandTextureWidth;
    location.x &= kBandTextureWidth - 1;
    return location;
}

static int2 advanceBand(int2 location) {
    location.x += 1;
    if (location.x == kBandTextureWidth) {
        location.x = 0;
        location.y += 1;
    }
    return location;
}

fragment half4 slugTextFragment(
    SlugTextVertexData in [[stage_in]],
    constant SlugTextUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float> curveData [[texture(FragmentTextureCustom0)]],
    texture2d<uint> bandData [[texture(FragmentTextureCustom1)]]
) {
    float2 emUV = in.texcoord;
    float2 emsPerPixel = fwidth(emUV);
    float2 pixelsPerEm = 1.0f / emsPerPixel;

    int2 glyphLocation = in.glyph.xy;
    int2 bandMax = in.glyph.zw;
    bandMax.y &= 0x00FF;

    float2 bandScale = in.bandTransform.xy;
    float2 bandOffset = in.bandTransform.zw;
    int2 bandIndex = clamp(int2(emUV * bandScale + bandOffset), int2(0), bandMax);

    uint2 horizontalBand = bandData.read(uint2(lookupBand(glyphLocation, uint(bandIndex.y)))).xy;
    int2 horizontalLocation = lookupBand(glyphLocation, horizontalBand.y);
    float xCoverage = 0.0f;
    float xWeight = 0.0f;
    int2 horizontalListLocation = horizontalLocation;
    for (int curveIndex = 0; curveIndex < int(horizontalBand.x); curveIndex++) {
        int2 curveLocation = int2(bandData.read(uint2(horizontalListLocation)).xy);
        horizontalListLocation = advanceBand(horizontalListLocation);

        float4 p12 = curveData.read(uint2(curveLocation)) - float4(emUV, emUV);
        float2 p1 = p12.xy;
        float2 p2 = p12.zw;
        float2 p3 = curveData.read(uint2(curveLocation.x + 1, curveLocation.y)).xy - emUV;

        if (max(max(p1.x, p2.x), p3.x) * pixelsPerEm.x < -0.5f) {
            break;
        }

        uint code = classifyRoots(p1.y, p2.y, p3.y);
        if (code != 0u) {
            float2 roots = solvePolynomial(p12.xy, p12.zw, p3, 0) * pixelsPerEm.x;
            if ((code & 1u) != 0u) {
                xCoverage += saturate(roots.x + 0.5f);
                xWeight = max(xWeight, saturate(1.0f - abs(roots.x) * 2.0f));
            }
            if (code > 1u) {
                xCoverage -= saturate(roots.y + 0.5f);
                xWeight = max(xWeight, saturate(1.0f - abs(roots.y) * 2.0f));
            }
        }
    }

    uint2 verticalBand = bandData.read(uint2(lookupBand(glyphLocation, uint(bandMax.y + 1 + bandIndex.x)))).xy;
    int2 verticalLocation = lookupBand(glyphLocation, verticalBand.y);
    float yCoverage = 0.0f;
    float yWeight = 0.0f;
    int2 verticalListLocation = verticalLocation;
    for (int curveIndex = 0; curveIndex < int(verticalBand.x); curveIndex++) {
        int2 curveLocation = int2(bandData.read(uint2(verticalListLocation)).xy);
        verticalListLocation = advanceBand(verticalListLocation);

        float4 p12 = curveData.read(uint2(curveLocation)) - float4(emUV, emUV);
        float2 p1 = p12.xy;
        float2 p2 = p12.zw;
        float2 p3 = curveData.read(uint2(curveLocation.x + 1, curveLocation.y)).xy - emUV;

        if (max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5f) {
            break;
        }

        uint code = classifyRoots(p1.x, p2.x, p3.x);
        if (code != 0u) {
            float2 roots = solvePolynomial(p1, p2, p3, 1) * pixelsPerEm.y;
            if ((code & 1u) != 0u) {
                yCoverage -= saturate(roots.x + 0.5f);
                yWeight = max(yWeight, saturate(1.0f - abs(roots.x) * 2.0f));
            }
            if (code > 1u) {
                yCoverage += saturate(roots.y + 0.5f);
                yWeight = max(yWeight, saturate(1.0f - abs(roots.y) * 2.0f));
            }
        }
    }

    float denominator = max(xWeight + yWeight, 1.0f / 65536.0f);
    float coverage = max(
        abs(xCoverage * xWeight + yCoverage * yWeight) / denominator,
        min(abs(xCoverage), abs(yCoverage))
    );
    coverage = saturate(coverage);

    float4 color = uniforms.color;
    color.a *= coverage;
    return half4(color);
}
