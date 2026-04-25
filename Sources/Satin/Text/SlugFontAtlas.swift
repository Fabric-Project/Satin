//
//  SlugFontAtlas.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import CoreText
import Foundation
import Metal
import simd

private struct SlugQuadBezier {
    var p0: simd_float2
    var p1: simd_float2
    var p2: simd_float2

    var minX: Float { min(p0.x, min(p1.x, p2.x)) }
    var maxX: Float { max(p0.x, max(p1.x, p2.x)) }
    var minY: Float { min(p0.y, min(p1.y, p2.y)) }
    var maxY: Float { max(p0.y, max(p1.y, p2.y)) }

    var isStraightHorizontal: Bool {
        abs(p0.y - p2.y) < 1e-5 && abs(p1.y - ((p0.y + p2.y) * 0.5)) < 1e-5
    }

    var isStraightVertical: Bool {
        abs(p0.x - p2.x) < 1e-5 && abs(p1.x - ((p0.x + p2.x) * 0.5)) < 1e-5
    }
}

internal struct SlugGlyphInfo {
    var advanceWidth: Float
    var xMin: Float
    var yMin: Float
    var xMax: Float
    var yMax: Float
    var curveTexStart: Int
    var curveCount: Int
    var bandTexX: Int
    var bandTexY: Int
    var numHorizBands: Int
    var numVertBands: Int
    var bandScaleX: Float
    var bandScaleY: Float
    var bandOffsetX: Float
    var bandOffsetY: Float

    static let empty = SlugGlyphInfo(
        advanceWidth: 0.0,
        xMin: 0.0,
        yMin: 0.0,
        xMax: 0.0,
        yMax: 0.0,
        curveTexStart: 0,
        curveCount: 0,
        bandTexX: 0,
        bandTexY: 0,
        numHorizBands: 0,
        numVertBands: 0,
        bandScaleX: 0.0,
        bandScaleY: 0.0,
        bandOffsetX: 0.0,
        bandOffsetY: 0.0
    )
}

public final class SlugFontAtlas {
    private struct CacheKey: Hashable {
        let device: ObjectIdentifier
        let fontName: String
    }

    private static let cacheLock = PThreadMutex(type: .normal)
    private static var cache: [CacheKey: SlugFontAtlas] = [:]

    private static let curveTextureWidth = 4096
    private static let curveTextureHeight = 64
    private static let bandTextureWidth = 4096
    private static let bandTextureHeight = 64
    private static let maxCurveTexels = curveTextureWidth * curveTextureHeight
    private static let maxBandTexels = bandTextureWidth * bandTextureHeight

    public let context: Context
    public let fontName: String
    public let postScriptName: String

    public private(set) var curveTexture: MTLTexture?
    public private(set) var bandTexture: MTLTexture?

    internal let ctFont: CTFont

    private let lock = PThreadMutex(type: .normal)
    private var glyphCache: [CGGlyph: SlugGlyphInfo] = [:]

    private var curvePixels = Array(repeating: Float16.zero, count: maxCurveTexels * 4)
    private var bandPixels = Array(repeating: UInt16.zero, count: maxBandTexels * 2)
    private var curveTexelCursor = 0
    private var bandTexelCursor = 0

    public init(context: Context, fontName: String) {
        self.context = context
        self.fontName = fontName

        let name = fontName as CFString
        ctFont = CTFontCreateWithName(name, 1.0, nil)
        postScriptName = CTFontCopyPostScriptName(ctFont) as String

        curveTexture = Self.makeTexture(
            device: context.device,
            width: Self.curveTextureWidth,
            height: Self.curveTextureHeight,
            pixelFormat: .rgba16Float,
            label: "Slug Curve Atlas \(postScriptName)"
        )
        bandTexture = Self.makeTexture(
            device: context.device,
            width: Self.bandTextureWidth,
            height: Self.bandTextureHeight,
            pixelFormat: .rg16Uint,
            label: "Slug Band Atlas \(postScriptName)"
        )
    }

    static func shared(context: Context, fontName: String) -> SlugFontAtlas {
        let key = CacheKey(device: ObjectIdentifier(context.device), fontName: fontName)
        return cacheLock.sync {
            if let atlas = cache[key] {
                return atlas
            }

            let atlas = SlugFontAtlas(context: context, fontName: fontName)
            cache[key] = atlas
            return atlas
        }
    }

    internal func ensureGlyphs(_ glyphs: [CGGlyph]) {
        lock.sync {
            var updated = false
            for glyph in glyphs where glyphCache[glyph] == nil {
                glyphCache[glyph] = makeGlyphInfo(for: glyph)
                updated = true
            }

            if updated {
                uploadTextures()
            }
        }
    }

    internal func glyphInfo(for glyph: CGGlyph) -> SlugGlyphInfo {
        lock.sync {
            glyphCache[glyph] ?? .empty
        }
    }

    private static func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        label: String
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private func makeGlyphInfo(for glyph: CGGlyph) -> SlugGlyphInfo {
        var glyph = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .default, &glyph, &advance, 1)
        let advanceWidth = Float(advance.width)

        guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            return SlugGlyphInfo(
                advanceWidth: advanceWidth,
                xMin: 0.0,
                yMin: 0.0,
                xMax: advanceWidth,
                yMax: 0.0,
                curveTexStart: 0,
                curveCount: 0,
                bandTexX: 0,
                bandTexY: 0,
                numHorizBands: 0,
                numVertBands: 0,
                bandScaleX: 0.0,
                bandScaleY: 0.0,
                bandOffsetX: 0.0,
                bandOffsetY: 0.0
            )
        }

        let curves = extractQuadBeziers(from: glyphPath)
        guard !curves.isEmpty else {
            return SlugGlyphInfo(
                advanceWidth: advanceWidth,
                xMin: 0.0,
                yMin: 0.0,
                xMax: advanceWidth,
                yMax: 0.0,
                curveTexStart: 0,
                curveCount: 0,
                bandTexX: 0,
                bandTexY: 0,
                numHorizBands: 0,
                numVertBands: 0,
                bandScaleX: 0.0,
                bandScaleY: 0.0,
                bandOffsetX: 0.0,
                bandOffsetY: 0.0
            )
        }

        let xMin = curves.reduce(Float.greatestFiniteMagnitude) { min($0, $1.minX) }
        let xMax = curves.reduce(-Float.greatestFiniteMagnitude) { max($0, $1.maxX) }
        let yMin = curves.reduce(Float.greatestFiniteMagnitude) { min($0, $1.minY) }
        let yMax = curves.reduce(-Float.greatestFiniteMagnitude) { max($0, $1.maxY) }

        let curveStart = curveTexelCursor
        ensureCurveCapacity(curves.count * 2)

        var curveTextureLocations: [(UInt16, UInt16)] = []
        curveTextureLocations.reserveCapacity(curves.count)

        for curve in curves {
            let index = curveTexelCursor
            let tx = UInt16(index % Self.curveTextureWidth)
            let ty = UInt16(index / Self.curveTextureWidth)
            curveTextureLocations.append((tx, ty))

            writeCurveTexel(curve.p0.x, curve.p0.y, curve.p1.x, curve.p1.y)
            writeCurveTexel(curve.p2.x, curve.p2.y, 0.0, 0.0)
        }

        let numHorizBands = 8
        let numVertBands = 8
        let epsilon: Float = 1.0 / 1024.0

        let horizontalBandHeight = (yMax - yMin) / Float(numHorizBands)
        let verticalBandWidth = (xMax - xMin) / Float(numVertBands)

        var horizontalBands: [[Int]] = []
        horizontalBands.reserveCapacity(numHorizBands)
        for band in 0 ..< numHorizBands {
            let bandMin = yMin + Float(band) * horizontalBandHeight - epsilon
            let bandMax = yMin + Float(band + 1) * horizontalBandHeight + epsilon
            let indices = curves.indices
                .filter { index in
                    let curve = curves[index]
                    if curve.isStraightHorizontal { return false }
                    return curve.maxY >= bandMin && curve.minY <= bandMax
                }
                .sorted { curves[$0].maxX > curves[$1].maxX }
            horizontalBands.append(indices)
        }

        var verticalBands: [[Int]] = []
        verticalBands.reserveCapacity(numVertBands)
        for band in 0 ..< numVertBands {
            let bandMin = xMin + Float(band) * verticalBandWidth - epsilon
            let bandMax = xMin + Float(band + 1) * verticalBandWidth + epsilon
            let indices = curves.indices
                .filter { index in
                    let curve = curves[index]
                    if curve.isStraightVertical { return false }
                    return curve.maxX >= bandMin && curve.minX <= bandMax
                }
                .sorted { curves[$0].maxY > curves[$1].maxY }
            verticalBands.append(indices)
        }

        let headerCount = numHorizBands + numVertBands
        let curveListCount = horizontalBands.reduce(0) { $0 + $1.count } + verticalBands.reduce(0) { $0 + $1.count }
        ensureBandCapacity(headerCount + curveListCount)

        let bandStartLinear = bandTexelCursor
        let bandStartX = bandStartLinear % Self.bandTextureWidth
        let bandStartY = bandStartLinear / Self.bandTextureWidth
        let headerOffset = bandTexelCursor

        bandTexelCursor += headerCount

        var horizontalOffsets: [UInt16] = []
        horizontalOffsets.reserveCapacity(numHorizBands)
        for indices in horizontalBands {
            let relativeOffset = bandTexelCursor - bandStartLinear
            precondition(relativeOffset <= Int(UInt16.max), "SlugFontAtlas horizontal band offset overflowed UInt16 for \(postScriptName)")
            horizontalOffsets.append(UInt16(relativeOffset))

            for curveIndex in indices {
                let coordinate = curveTextureLocations[curveIndex]
                writeBandTexel(coordinate.0, coordinate.1)
            }
        }

        var verticalOffsets: [UInt16] = []
        verticalOffsets.reserveCapacity(numVertBands)
        for indices in verticalBands {
            let relativeOffset = bandTexelCursor - bandStartLinear
            precondition(relativeOffset <= Int(UInt16.max), "SlugFontAtlas vertical band offset overflowed UInt16 for \(postScriptName)")
            verticalOffsets.append(UInt16(relativeOffset))

            for curveIndex in indices {
                let coordinate = curveTextureLocations[curveIndex]
                writeBandTexel(coordinate.0, coordinate.1)
            }
        }

        var headerPointer = headerOffset
        for (band, indices) in horizontalBands.enumerated() {
            bandPixels[headerPointer * 2 + 0] = UInt16(indices.count)
            bandPixels[headerPointer * 2 + 1] = horizontalOffsets[band]
            headerPointer += 1
        }
        for (band, indices) in verticalBands.enumerated() {
            bandPixels[headerPointer * 2 + 0] = UInt16(indices.count)
            bandPixels[headerPointer * 2 + 1] = verticalOffsets[band]
            headerPointer += 1
        }

        let bandScaleX = Float(numVertBands) / max(xMax - xMin, 1e-6)
        let bandScaleY = Float(numHorizBands) / max(yMax - yMin, 1e-6)
        let bandOffsetX = -xMin * bandScaleX
        let bandOffsetY = -yMin * bandScaleY

        return SlugGlyphInfo(
            advanceWidth: advanceWidth,
            xMin: xMin,
            yMin: yMin,
            xMax: xMax,
            yMax: yMax,
            curveTexStart: curveStart,
            curveCount: curves.count,
            bandTexX: bandStartX,
            bandTexY: bandStartY,
            numHorizBands: numHorizBands,
            numVertBands: numVertBands,
            bandScaleX: bandScaleX,
            bandScaleY: bandScaleY,
            bandOffsetX: bandOffsetX,
            bandOffsetY: bandOffsetY
        )
    }

    private func ensureCurveCapacity(_ additionalTexels: Int) {
        precondition(
            curveTexelCursor + additionalTexels <= Self.maxCurveTexels,
            "SlugFontAtlas exceeded curve atlas capacity for \(postScriptName)"
        )
    }

    private func ensureBandCapacity(_ additionalTexels: Int) {
        precondition(
            bandTexelCursor + additionalTexels <= Self.maxBandTexels,
            "SlugFontAtlas exceeded band atlas capacity for \(postScriptName)"
        )
    }

    private func writeCurveTexel(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        let base = curveTexelCursor * 4
        curvePixels[base + 0] = Float16(r)
        curvePixels[base + 1] = Float16(g)
        curvePixels[base + 2] = Float16(b)
        curvePixels[base + 3] = Float16(a)
        curveTexelCursor += 1
    }

    private func writeBandTexel(_ r: UInt16, _ g: UInt16) {
        let base = bandTexelCursor * 2
        bandPixels[base + 0] = r
        bandPixels[base + 1] = g
        bandTexelCursor += 1
    }

    private func uploadTextures() {
        let curveHeight = max(1, (curveTexelCursor + Self.curveTextureWidth - 1) / Self.curveTextureWidth)
        let bandHeight = max(1, (bandTexelCursor + Self.bandTextureWidth - 1) / Self.bandTextureWidth)

        if let curveTexture {
            curvePixels.withUnsafeBytes { bytes in
                curveTexture.replace(
                    region: MTLRegionMake2D(0, 0, Self.curveTextureWidth, curveHeight),
                    mipmapLevel: 0,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: MemoryLayout<Float16>.stride * Self.curveTextureWidth * 4
                )
            }
        }

        if let bandTexture {
            bandPixels.withUnsafeBytes { bytes in
                bandTexture.replace(
                    region: MTLRegionMake2D(0, 0, Self.bandTextureWidth, bandHeight),
                    mipmapLevel: 0,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: MemoryLayout<UInt16>.stride * Self.bandTextureWidth * 2
                )
            }
        }
    }

    private func extractQuadBeziers(from path: CGPath) -> [SlugQuadBezier] {
        var result: [SlugQuadBezier] = []
        var subpathStart = CGPoint.zero
        var current = CGPoint.zero

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee

            switch element.type {
            case .moveToPoint:
                let point = element.points[0]
                subpathStart = point
                current = point
            case .addLineToPoint:
                let point = element.points[0]
                let midpoint = CGPoint(x: (current.x + point.x) * 0.5, y: (current.y + point.y) * 0.5)
                result.append(
                    SlugQuadBezier(
                        p0: simd_make_float2(Float(current.x), Float(current.y)),
                        p1: simd_make_float2(Float(midpoint.x), Float(midpoint.y)),
                        p2: simd_make_float2(Float(point.x), Float(point.y))
                    )
                )
                current = point
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let point = element.points[1]
                result.append(
                    SlugQuadBezier(
                        p0: simd_make_float2(Float(current.x), Float(current.y)),
                        p1: simd_make_float2(Float(control.x), Float(control.y)),
                        p2: simd_make_float2(Float(point.x), Float(point.y))
                    )
                )
                current = point
            case .addCurveToPoint:
                let control1 = element.points[0]
                let control2 = element.points[1]
                let point = element.points[2]
                let quadratics = cubicToQuadratics(
                    from: current,
                    control1: control1,
                    control2: control2,
                    to: point
                )
                result.append(contentsOf: quadratics)
                current = point
            case .closeSubpath:
                if distanceSquared(current, subpathStart) > 1e-10 {
                    let midpoint = CGPoint(
                        x: (current.x + subpathStart.x) * 0.5,
                        y: (current.y + subpathStart.y) * 0.5
                    )
                    result.append(
                        SlugQuadBezier(
                            p0: simd_make_float2(Float(current.x), Float(current.y)),
                            p1: simd_make_float2(Float(midpoint.x), Float(midpoint.y)),
                            p2: simd_make_float2(Float(subpathStart.x), Float(subpathStart.y))
                        )
                    )
                }
                current = subpathStart
            @unknown default:
                break
            }
        }

        return result
    }

    private func cubicToQuadratics(
        from p0: CGPoint,
        control1 c1: CGPoint,
        control2 c2: CGPoint,
        to p3: CGPoint
    ) -> [SlugQuadBezier] {
        let m01 = lerp(p0, c1, 0.5)
        let m12 = lerp(c1, c2, 0.5)
        let m23 = lerp(c2, p3, 0.5)
        let m012 = lerp(m01, m12, 0.5)
        let m123 = lerp(m12, m23, 0.5)
        let midpoint = lerp(m012, m123, 0.5)

        return [
            SlugQuadBezier(
                p0: simd_make_float2(Float(p0.x), Float(p0.y)),
                p1: simd_make_float2(Float(m012.x), Float(m012.y)),
                p2: simd_make_float2(Float(midpoint.x), Float(midpoint.y))
            ),
            SlugQuadBezier(
                p0: simd_make_float2(Float(midpoint.x), Float(midpoint.y)),
                p1: simd_make_float2(Float(m123.x), Float(m123.y)),
                p2: simd_make_float2(Float(p3.x), Float(p3.y))
            ),
        ]
    }

    private func lerp(_ lhs: CGPoint, _ rhs: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(
            x: lhs.x + (rhs.x - lhs.x) * t,
            y: lhs.y + (rhs.y - lhs.y) * t
        )
    }

    private func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}
