//
//  ExtrudedTextGeometry.swift
//  Satin
//
//  Created by Reza Ali on 7/19/20.
//

import CoreGraphics
import CoreText
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class ExtrudedTextGeometry: TesselatedTextGeometry {
    public var distance: Float {
        didSet {
            if oldValue != distance {
                _updateData = true
            }
        }
    }

    var geometryExtrudeCache: [TesselatedTextGlyphCacheKey: GeometryData] = [:]
    var geometryReverseCache: [TesselatedTextGlyphCacheKey: GeometryData] = [:]

    public init(context: Context, text: String, fontName: String = "Helvetica", fontSize: Float, distance: Float = 1.0, bounds: CGSize = .zero, pivot: simd_float2 = .zero, textAlignment: CTTextAlignment = .natural, verticalAlignment: VerticalAlignment = .center, kern: Float = 0.0, lineSpacing: Float = 0) {
        self.distance = distance
        super.init(context: context, text: text, fontName: fontName, fontSize: fontSize, bounds: bounds, pivot: pivot, textAlignment: textAlignment, verticalAlignment: verticalAlignment, kern: kern, lineSpacing: lineSpacing)
    }

    override func addGlyphGeometryData(_ gData: inout GeometryData, _ charIndex: String.Index, _ font: CTFont, _ glyph: CGGlyph, _ glyphPosition: CGPoint, _ origin: CGPoint) {
        guard let framePivot = framePivot, let verticalOffset = verticalOffset else { return }

        addGlyphGeometryData(
            &gData,
            charIndex,
            font,
            glyph,
            glyphPosition,
            origin,
            framePivot: framePivot,
            verticalOffset: verticalOffset
        )
    }

    override func addGlyphGeometryData(
        _ gData: inout GeometryData,
        _ charIndex: String.Index,
        _ font: CTFont,
        _ glyph: CGGlyph,
        _ glyphPosition: CGPoint,
        _ origin: CGPoint,
        framePivot: CGPoint,
        verticalOffset: CGFloat
    ) {
        let cacheKey = glyphCacheKey(for: glyph, in: font)
        var glyphPaths: [Polyline2D] = []

        // front face character data
        var cData = GeometryData(vertexCount: 0, vertexData: nil, indexCount: 0, indexData: nil)
        // back face character data
        var bData = GeometryData(vertexCount: 0, vertexData: nil, indexCount: 0, indexData: nil)
        // side faces character data
        var sData = GeometryData(vertexCount: 0, vertexData: nil, indexCount: 0, indexData: nil)

        if let cacheData = geometryCache[cacheKey],
           let cacheReverseData = geometryReverseCache[cacheKey],
           let cacheExtrudeData = geometryExtrudeCache[cacheKey],
           let charPaths = characterPathsCache[cacheKey]
        {
            cData = cacheData
            bData = cacheReverseData
            sData = cacheExtrudeData
            glyphPaths = charPaths
        }
        else if let outline = makeGlyphOutline(font, glyph) {
            glyphPaths = outline.polylines
            cData = makeFaceGeometryData(outline, font, text[charIndex])

            copyGeometryData(&bData, &cData)
            reverseFacesOfGeometryData(&bData)
            geometryReverseCache[cacheKey] = bData

            var (contourPoints, contourLengths) = contourBuffers(glyphPaths)
            if extrudePaths(&contourPoints, &contourLengths, Int32(contourLengths.count), &sData) == 0 {
                computeNormalsOfGeometryData(&sData)
            }
            else {
                print("PATH EXTRUSION FOR \(text[charIndex]) FAILED!")
            }

            geometryCache[cacheKey] = cData
            geometryExtrudeCache[cacheKey] = sData
            characterPathsCache[cacheKey] = glyphPaths
        }

        let glyphOffset = simd_make_float2(Float(glyphPosition.x + origin.x - framePivot.x), Float(glyphPosition.y + origin.y - framePivot.y - verticalOffset))
        recordCharacterGlyph(glyphPaths, at: glyphOffset, for: charIndex)

        combineAndOffsetGeometryData(&gData, &cData, simd_make_float3(glyphOffset, distance * 0.5))
        combineAndOffsetGeometryData(&gData, &bData, simd_make_float3(glyphOffset, -distance * 0.5))
        combineAndScaleAndOffsetGeometryData(&gData, &sData, simd_make_float3(1.0, 1.0, distance * 0.5), simd_make_float3(glyphOffset, 0.0))
    }

    override func clearGeometryCache() {
        super.clearGeometryCache()

        for var (_, data) in geometryReverseCache {
            freeGeometryData(&data)
        }
        geometryReverseCache = [:]

        for var (_, data) in geometryExtrudeCache {
            freeGeometryData(&data)
        }
        geometryExtrudeCache = [:]
    }
}
