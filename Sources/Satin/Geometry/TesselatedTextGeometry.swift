//
//  TextGeometry.swift
//  Satin
//
//  Created by Reza Ali on 1/10/22.
//

import CoreText
import Foundation
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

extension CTTextAlignment: @retroactive Codable {}

struct TesselatedTextGlyphCacheKey: Hashable {
    let glyph: CGGlyph
    // Variation instances of a font share a PostScript name, so the font itself, size included, identifies the glyph
    let font: CTFont
    let angleLimit: Float
    let distanceLimit: Float
}

private struct TesselatedTextLayoutCacheKey: Hashable {
    let text: String
    let fontName: String
    let fontSize: Float
    let kern: Float
    let lineSpacing: Float
    let textAlignment: UInt8
    let verticalAlignment: Int
    let textBoundsWidth: CGFloat
    let textBoundsHeight: CGFloat
    let pivotX: Float
    let pivotY: Float
}

private struct TesselatedTextGlyphLayout {
    // UTF-16 offset of the first character the glyph draws
    let stringOffset: Int
    // Differs from the geometry's font where CoreText substituted a fallback, such as for SF Symbols in Helvetica
    let font: CTFont
    let glyph: CGGlyph
    let glyphPosition: CGPoint
    let origin: CGPoint
}

private struct TesselatedTextLayoutData {
    let glyphs: [TesselatedTextGlyphLayout]
    let suggestFrameSize: CGSize?
    let framePivot: CGPoint
    let verticalOffset: CGFloat
}

public class TesselatedTextGeometry: SatinGeometry {
    public enum VerticalAlignment: Int, Codable {
        case top = 0
        case center = 1
        case bottom = 2
    }

    public var verticalAlignment: VerticalAlignment = .center {
        didSet {
            if verticalAlignment != oldValue {
                _updateData = true
            }
        }
    }

    public var textAlignment: CTTextAlignment = .natural {
        didSet {
            if textAlignment != oldValue {
                _updateData = true
            }
        }
    }

    public var text = "" {
        didSet {
            if text != oldValue {
                _updateData = true
            }
        }
    }

    public var pivot = simd_float2(repeating: 0.0) {
        didSet {
            if pivot != oldValue {
                _updateData = true
            }
        }
    }

    public var textBounds = CGSize(width: -1, height: -1) {
        didSet {
            if textBounds != oldValue {
                _updateData = true
            }
        }
    }

    public var kern: Float = 0.0 {
        didSet {
            if oldValue != kern {
                _updateData = true
            }
        }
    }

    public var lineSpacing: Float = 0.0 {
        didSet {
            if oldValue != lineSpacing {
                _updateData = true
            }
        }
    }

    public var fontName = "Helvetica" {
        didSet {
            if fontName != oldValue {
                ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
                needsClear = true
                _updateData = true
            }
        }
    }

    public var fontSize: Float = 1 {
        didSet {
            if fontSize != oldValue {
                ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
                needsClear = true
                _updateData = true
            }
        }
    }

    public var lineHeight: Float {
        ascent + descent + leading
    }

    public var ascent: Float {
        Float(CTFontGetAscent(ctFont))
    }

    public var descent: Float {
        Float(CTFontGetDescent(ctFont))
    }

    public var leading: Float {
        Float(CTFontGetLeading(ctFont))
    }

    public var unitsPerEm: Float {
        Float(CTFontGetUnitsPerEm(ctFont))
    }

    public var glyphCount: Float {
        Float(CTFontGetGlyphCount(ctFont))
    }

    public var underlinePosition: Float {
        Float(CTFontGetUnderlinePosition(ctFont))
    }

    public var underlineThickness: Float {
        Float(CTFontGetUnderlineThickness(ctFont))
    }

    public var slantAngle: Float {
        Float(CTFontGetSlantAngle(ctFont))
    }

    public var capHeight: Float {
        Float(CTFontGetCapHeight(ctFont))
    }

    public var xHeight: Float {
        Float(CTFontGetXHeight(ctFont))
    }

    public var suggestFrameSize: CGSize? {
        if needsSuggestFrameSizeSetup {
            _suggestFrameSize = getSuggestFrameSize()
            needsSuggestFrameSizeSetup = false
        }
        return _suggestFrameSize
    }

    var _suggestFrameSize: CGSize?

    var verticalOffset: CGFloat? {
        if needsVerticalOffsetSetup {
            _verticalOffset = getVerticalOffset()
            needsVerticalOffsetSetup = false
        }
        return _verticalOffset
    }

    var _verticalOffset: CGFloat?

    var framePivot: CGPoint? {
        if needsFramePivotSetup {
            _framePivot = getFramePivot()
            needsFramePivotSetup = false
        }
        return _framePivot
    }

    var _framePivot: CGPoint?

    var frameSetter: CTFramesetter? {
        if needsFrameSetterSetup {
            _frameSetter = getFrameSetter()
            needsFrameSetterSetup = false
        }
        return _frameSetter
    }

    var _frameSetter: CTFramesetter?

    var frame: CTFrame? {
        if needsFrameSetup {
            _frame = getFrame()
            needsFrameSetup = false
        }
        return _frame
    }

    var _frame: CTFrame?

    var lines: [CTLine] {
        if needsLinesSetup {
            _lines = getLines()
            needsLinesSetup = false
        }
        return _lines
    }

    var _lines: [CTLine] = []

    var origins: [CGPoint] {
        if needsOriginsSetup {
            _origins = getOrigins()
            needsOriginsSetup = false
        }
        return _origins
    }

    var _origins: [CGPoint] = []

    var attributedText: CFAttributedString? {
        if needsTextSetup {
            _attributedText = getAttributedText()
            needsTextSetup = false
        }
        return _attributedText
    }

    var _attributedText: CFAttributedString?

    var ctFont: CTFont

    var needsVerticalOffsetSetup = true
    var needsFramePivotSetup = true

    var needsTextSetup = true {
        didSet {
            if needsTextSetup {
                needsFrameSetterSetup = true
                needsSuggestFrameSizeSetup = true
                needsVerticalOffsetSetup = true
                needsFramePivotSetup = true
            }
        }
    }

    var needsSuggestFrameSizeSetup = true

    var needsFrameSetterSetup = true {
        didSet {
            if needsFrameSetterSetup {
                needsFrameSetup = true
            }
        }
    }

    var needsFrameSetup = true {
        didSet {
            if needsFrameSetup {
                needsLinesSetup = true
            }
        }
    }

    var needsLinesSetup = true {
        didSet {
            if needsLinesSetup {
                needsOriginsSetup = true
            }
        }
    }

    var needsOriginsSetup = true

    var needsClear = false

    override public var _updateData: Bool {
        didSet {
            if _updateData {
                needsTextSetup = true
            }
        }
    }

    var geometryCache: [TesselatedTextGlyphCacheKey: GeometryData] = [:]
    var characterPathsCache: [TesselatedTextGlyphCacheKey: [Polyline2D]] = [:]
    private var layoutCache: [TesselatedTextLayoutCacheKey: TesselatedTextLayoutData] = [:]
    private var layoutCacheOrder: [TesselatedTextLayoutCacheKey] = []
    private let layoutCacheLimit = 64

    // A Character drawn as several glyphs, such as Devanagari "कि", holds all of their outlines, offset from its first glyph
    public var characterPaths: [Character: [Polyline2D]] = [:]
    // The position of the first glyph CoreText draws for each Character that has one
    public var characterOffsets: [String.Index: simd_float2] = [:]
    // Outlines of a Character's later glyphs, translated into its first glyph's frame and owned here, not by characterPathsCache
    private var clusterPolylines: [Polyline2D] = []

    public init(context: Context, text: String, fontName: String = "Helvetica", fontSize: Float, bounds: CGSize = .zero, pivot: simd_float2 = .zero, textAlignment: CTTextAlignment = .natural, verticalAlignment: VerticalAlignment = .center, kern: Float = 0.0, lineSpacing: Float = 0.0) {
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        textBounds = bounds
        self.pivot = pivot
        self.textAlignment = textAlignment
        self.verticalAlignment = verticalAlignment
        self.kern = kern
        self.lineSpacing = lineSpacing
        ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
        super.init(context: context)
    }

    var angleLimit: Float = degToRad(7.5)

    override public func generateGeometryData() -> GeometryData {
        var gData = GeometryData(vertexCount: 0, vertexData: nil, indexCount: 0, indexData: nil)

        if needsClear {
            clearCache()
            needsClear = false
        }

        characterPaths.removeAll(keepingCapacity: true)
        freePolylines(&clusterPolylines)
        clusterPolylines.removeAll(keepingCapacity: true)
        characterOffsets.removeAll(keepingCapacity: true)
        characterOffsets.reserveCapacity(text.count)

        let layoutData = textLayoutData()
        let characterIndices = characterIndicesByUTF16Offset()
        for glyphLayout in layoutData.glyphs where characterIndices.indices.contains(glyphLayout.stringOffset) {
            addGlyphGeometryData(
                &gData,
                characterIndices[glyphLayout.stringOffset],
                glyphLayout.font,
                glyphLayout.glyph,
                glyphLayout.glyphPosition,
                glyphLayout.origin,
                framePivot: layoutData.framePivot,
                verticalOffset: layoutData.verticalOffset
            )
        }

        return gData
    }

    // For each UTF-16 offset (CoreText's unit for string positions), the index of the Character containing it
    func characterIndicesByUTF16Offset() -> [String.Index] {
        var characterIndices: [String.Index] = []
        characterIndices.reserveCapacity(text.utf16.count)
        for characterIndex in text.indices {
            characterIndices.append(contentsOf: repeatElement(characterIndex, count: text[characterIndex].utf16.count))
        }
        return characterIndices
    }

    func addGlyphGeometryData(_ gData: inout GeometryData, _ charIndex: String.Index, _ font: CTFont, _ glyph: CGGlyph, _ glyphPosition: CGPoint, _ origin: CGPoint) {
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

    func addGlyphGeometryData(
        _ gData: inout GeometryData,
        _ charIndex: String.Index,
        _ font: CTFont,
        _ glyph: CGGlyph,
        _ glyphPosition: CGPoint,
        _ origin: CGPoint,
        framePivot: CGPoint,
        verticalOffset: CGFloat
    ) {
        var cData = createGeometryData()
        let cacheKey = glyphCacheKey(for: glyph, in: font)
        var glyphPaths: [Polyline2D] = []

        if let cacheData = geometryCache[cacheKey], let charPaths = characterPathsCache[cacheKey] {
            cData = cacheData
            glyphPaths = charPaths
        } else if let outline = makeGlyphOutline(font, glyph) {
            glyphPaths = outline.polylines
            cData = makeFaceGeometryData(outline, font, text[charIndex])
            geometryCache[cacheKey] = cData
            characterPathsCache[cacheKey] = glyphPaths
        }

        let glyphOffset = simd_make_float2(Float(glyphPosition.x + origin.x - framePivot.x), Float(glyphPosition.y + origin.y - framePivot.y - verticalOffset))
        recordCharacterGlyph(glyphPaths, at: glyphOffset, for: charIndex)
        combineAndOffsetGeometryData(&gData, &cData, simd_make_float3(glyphOffset, 0.0))
    }

    func recordCharacterGlyph(_ glyphPaths: [Polyline2D], at glyphOffset: simd_float2, for charIndex: String.Index) {
        let character = text[charIndex]
        guard let characterOffset = characterOffsets[charIndex] else {
            characterOffsets[charIndex] = glyphOffset
            characterPaths[character] = glyphPaths
            return
        }

        let translation = glyphOffset - characterOffset
        for glyphPath in glyphPaths {
            var translatedPath = createEmptyPolyline2D()
            for pointIndex in 0 ..< Int(glyphPath.count) {
                addPointToPolyline2D(glyphPath.data[pointIndex] + translation, &translatedPath)
            }
            clusterPolylines.append(translatedPath)
            characterPaths[character, default: []].append(translatedPath)
        }
    }

    // The outline's front face, which takes ownership of its triangles
    func makeFaceGeometryData(_ outline: GlyphOutline, _ font: CTFont, _ character: Character) -> GeometryData {
        var faceData = createGeometryData()
        var (contourPoints, contourLengths) = contourBuffers(outline.polylines)

        if var triangles = outline.triangles {
            let glyphBounds = outline.path.boundingBoxOfPath
            let bounds = simd_float4(Float(glyphBounds.minX),
                                     Float(glyphBounds.minY),
                                     Float(glyphBounds.maxX),
                                     Float(glyphBounds.maxY))
            createGeometryDataFromPaths(&contourPoints, &contourLengths, Int32(contourLengths.count), &faceData, bounds)
            copyTriangleDataToGeometryData(&triangles, &faceData)
            freeTriangleData(&triangles)
        } else {
            printTriangulationFailure(character, font, contourPoints, contourLengths)
        }

        return faceData
    }

    func contourBuffers(_ polylines: [Polyline2D]) -> (points: [UnsafeMutablePointer<simd_float2>?], lengths: [Int32]) {
        (polylines.map { $0.data }, polylines.map { $0.count })
    }

    private func printTriangulationFailure(_ char: Character, _ font: CTFont, _ _paths: [UnsafeMutablePointer<simd_float2>?], _ _lengths: [Int32]) {
        print("⚠️ Triangulation FAILED: '\(char)' font=\(CTFontCopyPostScriptName(font)) contours=\(_lengths.count)")
        func cross(_ a: simd_float2, _ b: simd_float2, _ c: simd_float2) -> Float {
            (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        }

        func onSeg(_ p: simd_float2, _ a: simd_float2, _ b: simd_float2, eps: Float = 1e-5) -> Bool {
            if abs(cross(a, b, p)) > eps { return false }
            return p.x >= min(a.x, b.x) - eps && p.x <= max(a.x, b.x) + eps &&
                   p.y >= min(a.y, b.y) - eps && p.y <= max(a.y, b.y) + eps
        }

        func segHit(_ a1: simd_float2, _ a2: simd_float2, _ b1: simd_float2, _ b2: simd_float2, eps: Float = 1e-5) -> Bool {
            let d1 = cross(a1, a2, b1)
            let d2 = cross(a1, a2, b2)
            let d3 = cross(b1, b2, a1)
            let d4 = cross(b1, b2, a2)

            if ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps)) &&
               ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps)) {
                return true
            }

            return (abs(d1) <= eps && onSeg(b1, a1, a2, eps: eps)) ||
                   (abs(d2) <= eps && onSeg(b2, a1, a2, eps: eps)) ||
                   (abs(d3) <= eps && onSeg(a1, b1, b2, eps: eps)) ||
                   (abs(d4) <= eps && onSeg(a2, b1, b2, eps: eps))
        }

        for (i, len) in _lengths.enumerated() {
            guard let pts = _paths[i] else { continue }
            let n = Int(len)

            var colinear = 0
            for j in 0 ..< n {
                let a = pts[(j + n - 1) % n]
                let b = pts[j]
                let c = pts[(j + 1) % n]
                if abs(cross(a, b, c)) < 1e-5 { colinear += 1 }
            }

            var hits: [String] = []
            outer: for a in 0 ..< n {
                let a0 = pts[a]
                let a1 = pts[(a + 1) % n]
                for b in (a + 1) ..< n {
                    if b == a || b == (a + 1) % n || (b + 1) % n == a { continue }
                    if a == 0 && b == n - 1 { continue }
                    let b0 = pts[b]
                    let b1 = pts[(b + 1) % n]
                    if segHit(a0, a1, b0, b1) {
                        hits.append("\(a)-\(b)")
                        if hits.count == 8 { break outer }
                    }
                }
            }

            print("   contour[\(i)]: colinearTriples=\(colinear) selfIntersections=\(hits.count) sample=\(hits)")
        }
    }

    func glyphCacheKey(for glyph: CGGlyph, in font: CTFont) -> TesselatedTextGlyphCacheKey {
        TesselatedTextGlyphCacheKey(
            glyph: glyph,
            font: font,
            angleLimit: angleLimit,
            distanceLimit: fontSize / 10.0
        )
    }

    struct GlyphOutline {
        // The outline the polylines came from
        let path: CGPath
        let polylines: [Polyline2D]
        // Nil when the polylines could not be triangulated
        let triangles: TriangleData?
    }

    // Overlapping or self-intersecting contours, common in variable fonts such as SF Pro, triangulate with
    // the wrong fill or not at all, and merging them fixes that. Merging also re-splits curves in ways that
    // can defeat the triangulator, so the merged outline is used only where the original one falls short.
    func makeGlyphOutline(_ font: CTFont, _ glyph: CGGlyph) -> GlyphOutline? {
        guard let originalPath = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let distanceLimit = fontSize / 10.0

        let original = triangulateOutline(originalPath, getPolylines(originalPath, angleLimit, distanceLimit))
        let mergedPath = originalPath.normalized(using: .winding)
        var mergedPolylines = getPolylines(mergedPath, angleLimit, distanceLimit)

        // Merged contours wind consistently, so their signed area is the filled area.
        let filledArea = abs(signedArea(of: mergedPolylines))
        let originalError = original.triangles.map { abs(area(of: $0, over: original.polylines) - filledArea) }
        if let originalError, originalError <= filledArea * 0.02 {
            freePolylines(&mergedPolylines)
            return original
        }

        let merged = triangulateOutline(mergedPath, mergedPolylines)
        guard let mergedTriangles = merged.triangles,
              originalError.map({ abs(area(of: mergedTriangles, over: merged.polylines) - filledArea) < $0 }) ?? true
        else {
            freeGlyphOutline(merged)
            return original
        }

        freeGlyphOutline(original)
        return merged
    }

    func triangulateOutline(_ path: CGPath, _ polylines: [Polyline2D]) -> GlyphOutline {
        var (contourPoints, contourLengths) = contourBuffers(polylines)
        var triangles = createTriangleData()
        if triangulate(&contourPoints, &contourLengths, Int32(contourLengths.count), &triangles) == 0 {
            return GlyphOutline(path: path, polylines: polylines, triangles: triangles)
        }
        freeTriangleData(&triangles)
        return GlyphOutline(path: path, polylines: polylines, triangles: nil)
    }

    func freeGlyphOutline(_ outline: GlyphOutline) {
        var polylines = outline.polylines
        freePolylines(&polylines)
        if var triangles = outline.triangles {
            freeTriangleData(&triangles)
        }
    }

    func freePolylines(_ polylines: inout [Polyline2D]) {
        for index in polylines.indices {
            freePolyline2D(&polylines[index])
        }
    }

    private func signedArea(of polylines: [Polyline2D]) -> Float {
        var doubledArea: Float = 0
        for polyline in polylines {
            let pointCount = Int(polyline.count)
            for pointIndex in 0 ..< pointCount {
                let point = polyline.data[pointIndex], nextPoint = polyline.data[(pointIndex + 1) % pointCount]
                doubledArea += point.x * nextPoint.y - nextPoint.x * point.y
            }
        }
        return doubledArea * 0.5
    }

    // Triangle indices address the polylines' points in order.
    private func area(of triangles: TriangleData, over polylines: [Polyline2D]) -> Float {
        var points: [simd_float2] = []
        points.reserveCapacity(polylines.reduce(0) { $0 + Int($1.count) })
        for polyline in polylines {
            points.append(contentsOf: UnsafeBufferPointer(start: polyline.data, count: Int(polyline.count)))
        }
        var doubledArea: Float = 0
        for triangleIndex in 0 ..< Int(triangles.count) {
            let triangle = triangles.indices[triangleIndex]
            let first = points[Int(triangle.i0)], second = points[Int(triangle.i1)], third = points[Int(triangle.i2)]
            doubledArea += abs((second.x - first.x) * (third.y - first.y) - (third.x - first.x) * (second.y - first.y))
        }
        return doubledArea * 0.5
    }

    private func textLayoutData() -> TesselatedTextLayoutData {
        let cacheKey = textLayoutCacheKey()
        if let cached = layoutCache[cacheKey] {
            applyCachedLayoutMetadata(cached)
            return cached
        }

        guard let framePivot, let verticalOffset else {
            return TesselatedTextLayoutData(
                glyphs: [],
                suggestFrameSize: suggestFrameSize,
                framePivot: .zero,
                verticalOffset: 0
            )
        }

        var glyphLayouts: [TesselatedTextGlyphLayout] = []
        glyphLayouts.reserveCapacity(text.count)

        for (lineIndex, line) in lines.enumerated() {
            let origin = origins[lineIndex]
            let runs: [CTRun] = CTLineGetGlyphRuns(line) as! [CTRun]
            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphPositions = [CGPoint](repeating: .zero, count: glyphCount)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
                CTRunGetStringIndices(run, CFRangeMake(0, 0), &stringIndices)
                let runAttributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = runAttributes[kCTFontAttributeName].map { $0 as! CTFont } ?? ctFont

                glyphPositions.withUnsafeMutableBufferPointer { positionBuffer in
                    glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                        guard let positionBaseAddress = positionBuffer.baseAddress,
                              let glyphBaseAddress = glyphBuffer.baseAddress
                        else { return }

                        CTRunGetPositions(run, CFRangeMake(0, 0), positionBaseAddress)
                        CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphBaseAddress)

                        for glyphIndex in 0 ..< glyphCount {
                            glyphLayouts.append(
                                TesselatedTextGlyphLayout(
                                    stringOffset: stringIndices[glyphIndex],
                                    font: runFont,
                                    glyph: glyphBaseAddress[glyphIndex],
                                    glyphPosition: positionBaseAddress[glyphIndex],
                                    origin: origin
                                )
                            )
                        }
                    }
                }
            }
        }

        let layoutData = TesselatedTextLayoutData(
            glyphs: glyphLayouts,
            suggestFrameSize: suggestFrameSize,
            framePivot: framePivot,
            verticalOffset: verticalOffset
        )
        storeLayoutData(layoutData, for: cacheKey)
        return layoutData
    }

    private func textLayoutCacheKey() -> TesselatedTextLayoutCacheKey {
        TesselatedTextLayoutCacheKey(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            kern: kern,
            lineSpacing: lineSpacing,
            textAlignment: textAlignment.rawValue,
            verticalAlignment: verticalAlignment.rawValue,
            textBoundsWidth: textBounds.width,
            textBoundsHeight: textBounds.height,
            pivotX: pivot.x,
            pivotY: pivot.y
        )
    }

    private func applyCachedLayoutMetadata(_ layoutData: TesselatedTextLayoutData) {
        _suggestFrameSize = layoutData.suggestFrameSize
        _framePivot = layoutData.framePivot
        _verticalOffset = layoutData.verticalOffset
        needsSuggestFrameSizeSetup = false
        needsFramePivotSetup = false
        needsVerticalOffsetSetup = false
    }

    private func storeLayoutData(_ layoutData: TesselatedTextLayoutData, for cacheKey: TesselatedTextLayoutCacheKey) {
        if layoutCache[cacheKey] == nil {
            layoutCacheOrder.append(cacheKey)
        }
        layoutCache[cacheKey] = layoutData

        while layoutCacheOrder.count > layoutCacheLimit {
            let removedKey = layoutCacheOrder.removeFirst()
            layoutCache.removeValue(forKey: removedKey)
        }
    }

    func getPolylines(_ glyphPath: CGPath, _ angleLimit: Float, _ distanceLimit: Float) -> [Polyline2D] {
        var glyphPaths = [Polyline2D]()
        var path = Polyline2D(count: 0, capacity: 0, data: nil)
        glyphPath.applyWithBlock { (elementPtr: UnsafePointer<CGPathElement>) in
            let element = elementPtr.pointee
            var pointsPtr = element.points
            let pt = simd_make_float2(Float(pointsPtr.pointee.x), Float(pointsPtr.pointee.y))

            switch element.type {
            case .moveToPoint:
                if path.count > 2 {
                    glyphPaths.append(path)
                    path = Polyline2D(count: 0, capacity: 0, data: nil)
                } else if path.count > 0 {
                    freePolyline2D(&path)
                    path = Polyline2D(count: 0, capacity: 0, data: nil)
                }
                addPointToPolyline2D(pt, &path)
            case .addLineToPoint:
                let a = path.data[Int(path.count) - 1]
                var line = getAdaptiveLinearPath2(a, pt, distanceLimit)
                removeFirstPointInPolyline2D(&line)
                appendPolyline2D(&path, &line)
                freePolyline2D(&line)
            case .addQuadCurveToPoint:
                let a = path.data[Int(path.count) - 1]
                let b = pt
                pointsPtr += 1
                let c = simd_make_float2(Float(pointsPtr.pointee.x), Float(pointsPtr.pointee.y))
                var curve = getAdaptiveQuadraticBezierPath2(a, b, c, angleLimit)
                removeFirstPointInPolyline2D(&curve)
                appendPolyline2D(&path, &curve)
                freePolyline2D(&curve)
            case .addCurveToPoint:
                let a = path.data[Int(path.count) - 1]
                let b = pt
                pointsPtr += 1
                let c = simd_make_float2(Float(pointsPtr.pointee.x), Float(pointsPtr.pointee.y))
                pointsPtr += 1
                let d = simd_make_float2(Float(pointsPtr.pointee.x), Float(pointsPtr.pointee.y))
                var curve = getAdaptiveCubicBezierPath2(a, b, c, d, angleLimit)
                removeFirstPointInPolyline2D(&curve)
                appendPolyline2D(&path, &curve)
                freePolyline2D(&curve)
            case .closeSubpath:
                if isEqual2(path.data[0], path.data[Int(path.count - 1)]) {
                    removeLastPointInPolyline2D(&path)
                }
                let first = path.data[0]
                let last = path.data[Int(path.count) - 1]
                var line = getAdaptiveLinearPath2(last, first, distanceLimit)
                removeLastPointInPolyline2D(&line)
                removeFirstPointInPolyline2D(&line)
                appendPolyline2D(&path, &line)
                freePolyline2D(&line)
                glyphPaths.append(path)
                path = Polyline2D(count: 0, capacity: 0, data: nil)
            default:
                break
            }
        }
        if path.count > 2 {
            glyphPaths.append(path)
        } else if path.count > 0 {
            freePolyline2D(&path)
        }
        return glyphPaths
    }

    func getVerticalOffset() -> CGFloat? {
        guard let suggestFrameSize else { return nil }
        var verticalOffset: CGFloat
        switch verticalAlignment {
        case .top:
            verticalOffset = 0
        case .center:
            verticalOffset = ((textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) - suggestFrameSize.height) * 0.5
        case .bottom:
            verticalOffset = (textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) - suggestFrameSize.height
        }
        return verticalOffset
    }

    func getFramePivot() -> CGPoint? {
        guard let suggestFrameSize else { return nil }
        let pt = pivot * 0.5 + 0.5
        let px: CGFloat = (textBounds.width <= 0 ? suggestFrameSize.width : textBounds.width) * CGFloat(pt.x)
        let py: CGFloat = (textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) * CGFloat(pt.y)
        return CGPoint(x: px, y: py)
    }

    func getAttributedText() -> CFAttributedString? {
        // Text Attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ctFont,
            .kern: NSNumber(value: kern),
        ]

        let attributedText = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)
        CFAttributedStringReplaceString(attributedText, CFRangeMake(0, 0), text as CFString)
        CFAttributedStringSetAttributes(attributedText, CFRangeMake(0, text.utf16.count), attributes as CFDictionary, false)

        // Paragraph Attributes
        var alignment = textAlignment
        var lineSpace = lineSpacing

        withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineSpace) { lineSpacePointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<Float>.size, value: lineSpacePointer),
                ]

                let style = settings.withUnsafeBufferPointer {
                    CTParagraphStyleCreate($0.baseAddress, settings.count)
                }
                CFAttributedStringSetAttribute(attributedText, CFRangeMake(0, text.utf16.count), kCTParagraphStyleAttributeName, style)
            }
        }

        return attributedText
    }

    func getFrameSetter() -> CTFramesetter? {
        guard let attributedText else { return nil }
        return CTFramesetterCreateWithAttributedString(attributedText)
    }

    func getSuggestFrameSize() -> CGSize? {
        guard let frameSetter else { return nil }
        var bnds = textBounds
        if bnds.width <= 0 {
            bnds.width = CGFloat.greatestFiniteMagnitude
        }
        if bnds.height <= 0 {
            bnds.height = CGFloat.greatestFiniteMagnitude
        }
        return CTFramesetterSuggestFrameSizeWithConstraints(frameSetter, CFRangeMake(0, text.utf16.count), nil, bnds, nil)
    }

    func getFrame() -> CTFrame? {
        guard let suggestFrameSize, let frameSetter else { return nil }

        let framePath = CGMutablePath()
        let constraints = CGRect(x: 0.0, y: 0.0, width: textBounds.width <= 0.0 ? suggestFrameSize.width : textBounds.width, height: textBounds.height <= 0.0 ? suggestFrameSize.height : textBounds.height)
        framePath.addRect(constraints)

        return CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, text.utf16.count), framePath, nil)
    }

    func getLines() -> [CTLine] {
        guard let frame else { return [] }
        return CTFrameGetLines(frame) as! [CTLine]
    }

    func getOrigins() -> [CGPoint] {
        guard lines.count > 0, let frame else { return [] }
        var origins: [CGPoint] = Array(repeating: CGPoint(), count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        return origins
    }

    func clearGeometryCache() {
        for var (_, data) in geometryCache {
            freeGeometryData(&data)
        }
        geometryCache = [:]
    }

    func clearCharacterPaths() {
        characterPaths = [:]
        freePolylines(&clusterPolylines)
        clusterPolylines = []
        for var (_, paths) in characterPathsCache {
            freePolylines(&paths)
        }
        characterPathsCache = [:]
    }

    func clearLayoutCache() {
        layoutCache = [:]
        layoutCacheOrder = []
    }

    func clearCache() {
        clearGeometryCache()
        clearCharacterPaths()
        clearLayoutCache()
    }

    deinit {
        clearCache()
    }
}
