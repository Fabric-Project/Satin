//
//  SlugTextGeometry.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import CoreText
import Foundation
import simd

public final class SlugTextGeometry: Geometry {
    public enum VerticalAlignment: Int, Codable {
        case top = 0
        case center = 1
        case bottom = 2
    }

    public var font: SlugFontAtlas {
        didSet {
            _updateData = true
        }
    }

    public var text: String {
        didSet {
            if text != oldValue {
                _updateData = true
            }
        }
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
            if kern != oldValue {
                _updateData = true
            }
        }
    }

    public var lineSpacing: Float = 0.0 {
        didSet {
            if lineSpacing != oldValue {
                _updateData = true
            }
        }
    }

    private var _updateData = true

    private var positions: [simd_float3] = []
    private let positionBuffer = Float3BufferAttribute(defaultValue: .zero, data: [])

    private var glyphData: [simd_float4] = []
    private let glyphDataBuffer = Float4BufferAttribute(defaultValue: .zero, data: [])

    private var glyphBounds: [simd_float4] = []
    private let glyphBoundsBuffer = Float4BufferAttribute(defaultValue: .zero, data: [])

    private var inverseJacobians: [simd_float4] = []
    private let inverseJacobianBuffer = Float4BufferAttribute(defaultValue: .zero, data: [])

    private var bandTransforms: [simd_float4] = []
    private let bandTransformBuffer = Float4BufferAttribute(defaultValue: .zero, data: [])

    private var indices: [UInt32] = []
    private let indexElementBuffer = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)

    private let quadMargin: Float = 0.02

    public init(
        context: Context,
        text: String,
        font: SlugFontAtlas,
        bounds: CGSize = .zero,
        pivot: simd_float2 = .zero,
        textAlignment: CTTextAlignment = .natural,
        verticalAlignment: VerticalAlignment = .center,
        kern: Float = 0.0,
        lineSpacing: Float = 0.0
    ) {
        self.text = text
        self.font = font
        textBounds = bounds
        self.pivot = pivot
        self.textAlignment = textAlignment
        self.verticalAlignment = verticalAlignment
        self.kern = kern
        self.lineSpacing = lineSpacing
        super.init(context: context)

        addAttribute(positionBuffer, for: .Position)
        addAttribute(glyphDataBuffer, for: .Custom0)
        addAttribute(glyphBoundsBuffer, for: .Custom1)
        addAttribute(inverseJacobianBuffer, for: .Custom2)
        addAttribute(bandTransformBuffer, for: .Custom3)
        setElements(indexElementBuffer)

        updateGeometryData()
    }

    public func updateData() {
        indices.removeAll(keepingCapacity: true)
        positions.removeAll(keepingCapacity: true)
        glyphData.removeAll(keepingCapacity: true)
        glyphBounds.removeAll(keepingCapacity: true)
        inverseJacobians.removeAll(keepingCapacity: true)
        bandTransforms.removeAll(keepingCapacity: true)

        guard !text.isEmpty else {
            assignBuffers()
            return
        }

        guard let layoutContext = getLayoutContext() else {
            assignBuffers()
            return
        }

        var vertexIndex: UInt32 = 0

        for (lineIndex, line) in layoutContext.lines.enumerated() {
            let origin = layoutContext.origins[lineIndex]
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []

            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                if let runFontValue = attributes[kCTFontAttributeName] {
                    let runFont = runFontValue as! CTFont
                    let runFontName = CTFontCopyPostScriptName(runFont) as String
                    if runFontName != font.postScriptName {
                        continue
                    }
                }

                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
                var glyphPositions = Array(repeating: CGPoint.zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, 0), &glyphPositions)

                font.ensureGlyphs(glyphs)

                for glyphIndex in 0 ..< glyphCount {
                    let glyph = glyphs[glyphIndex]
                    let info = font.glyphInfo(for: glyph)

                    guard info.curveCount > 0 else { continue }

                    let position = glyphPositions[glyphIndex]
                    let posX = Float(position.x + origin.x - layoutContext.framePivot.x)
                    let posY = Float(position.y + origin.y - layoutContext.framePivot.y - layoutContext.verticalOffset)

                    let ex0 = info.xMin - quadMargin
                    let ex1 = info.xMax + quadMargin
                    let ey0 = info.yMin - quadMargin
                    let ey1 = info.yMax + quadMargin

                    let texZ = pack(info.bandTexX, info.bandTexY)
                    let texW = pack(info.numVertBands - 1, info.numHorizBands - 1)

                    let bandTransform = simd_make_float4(
                        info.bandScaleX,
                        info.bandScaleY,
                        info.bandOffsetX,
                        info.bandOffsetY
                    )

                    let invJacobian = simd_make_float4(1.0, 0.0, 0.0, 1.0)

                    let corners: [(Float, Float, Float, Float)] = [
                        (posX + ex0, posY + ey0, ex0, ey0),
                        (posX + ex1, posY + ey0, ex1, ey0),
                        (posX + ex1, posY + ey1, ex1, ey1),
                        (posX + ex0, posY + ey1, ex0, ey1),
                    ]

                    let cornerNormals: [simd_float2] = [
                        simd_normalize(simd_make_float2(-1.0, -1.0)),
                        simd_normalize(simd_make_float2(1.0, -1.0)),
                        simd_normalize(simd_make_float2(1.0, 1.0)),
                        simd_normalize(simd_make_float2(-1.0, 1.0)),
                    ]

                    for (cornerIndex, corner) in corners.enumerated() {
                        positions.append(simd_make_float3(corner.0, corner.1, 0.0))
                        glyphData.append(simd_make_float4(corner.2, corner.3, texZ, texW))
                        glyphBounds.append(simd_make_float4(cornerNormals[cornerIndex].x, cornerNormals[cornerIndex].y, 0.0, 0.0))
                        inverseJacobians.append(invJacobian)
                        bandTransforms.append(bandTransform)
                    }

                    indices.append(contentsOf: [
                        vertexIndex,
                        vertexIndex + 1,
                        vertexIndex + 2,
                        vertexIndex,
                        vertexIndex + 2,
                        vertexIndex + 3,
                    ])
                    vertexIndex += 4
                }
            }
        }

        assignBuffers()
    }

    func updateGeometryData() {
        if _updateData {
            updateData()
            _updateData = false
        }
    }

    override public func setup() {
        updateGeometryData()
        super.setup()
    }

    override public func update() {
        updateGeometryData()
        super.update()
    }

    private func assignBuffers() {
        positionBuffer.data = positions
        glyphDataBuffer.data = glyphData
        glyphBoundsBuffer.data = glyphBounds
        inverseJacobianBuffer.data = inverseJacobians
        bandTransformBuffer.data = bandTransforms
        indexElementBuffer.updateData(data: &indices, count: indices.count, source: indices)
    }

    private func pack(_ x: Int, _ y: Int) -> Float {
        let packed = UInt32(truncatingIfNeeded: x) | (UInt32(truncatingIfNeeded: y) << 16)
        return Float(bitPattern: packed)
    }

    private struct LayoutContext {
        var lines: [CTLine]
        var origins: [CGPoint]
        var framePivot: CGPoint
        var verticalOffset: CGFloat
    }

    private func getLayoutContext() -> LayoutContext? {
        guard let attributedText = getAttributedText() else { return nil }
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedText)
        guard let suggestFrameSize = getSuggestFrameSize(frameSetter) else { return nil }
        let frame = getFrame(frameSetter, suggestFrameSize)
        let lines = getLines(frame)
        let origins = getOrigins(frame, lines.count)
        let framePivot = getFramePivot(suggestFrameSize)
        let verticalOffset = getVerticalOffset(suggestFrameSize)
        return LayoutContext(
            lines: lines,
            origins: origins,
            framePivot: framePivot,
            verticalOffset: verticalOffset
        )
    }

    private func getAttributedText() -> CFAttributedString? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font.ctFont,
            .kern: NSNumber(value: kern),
        ]

        let attributedText = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)
        CFAttributedStringReplaceString(attributedText, CFRangeMake(0, 0), text as CFString)
        CFAttributedStringSetAttributes(attributedText, CFRangeMake(0, text.count), attributes as CFDictionary, false)

        let alignment = UnsafeMutablePointer<CTTextAlignment>.allocate(capacity: 1)
        alignment.pointee = textAlignment

        let spacing = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        spacing.pointee = lineSpacing

        let settings = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: alignment
            ),
            CTParagraphStyleSetting(
                spec: .lineSpacingAdjustment,
                valueSize: MemoryLayout<Float>.size,
                value: spacing
            ),
        ]

        let style = CTParagraphStyleCreate(settings, settings.count)
        CFAttributedStringSetAttribute(
            attributedText,
            CFRangeMake(0, text.count),
            kCTParagraphStyleAttributeName,
            style
        )

        alignment.deallocate()
        spacing.deallocate()

        return attributedText
    }

    private func getSuggestFrameSize(_ frameSetter: CTFramesetter) -> CGSize? {
        var bounds = textBounds
        if bounds.width <= 0 {
            bounds.width = .greatestFiniteMagnitude
        }
        if bounds.height <= 0 {
            bounds.height = .greatestFiniteMagnitude
        }
        return CTFramesetterSuggestFrameSizeWithConstraints(
            frameSetter,
            CFRangeMake(0, text.count),
            nil,
            bounds,
            nil
        )
    }

    private func getFrame(_ frameSetter: CTFramesetter, _ suggestFrameSize: CGSize) -> CTFrame {
        let framePath = CGMutablePath()
        let constraints = CGRect(
            x: 0.0,
            y: 0.0,
            width: textBounds.width <= 0.0 ? suggestFrameSize.width : textBounds.width,
            height: textBounds.height <= 0.0 ? suggestFrameSize.height : textBounds.height
        )
        framePath.addRect(constraints)
        return CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, text.count), framePath, nil)
    }

    private func getLines(_ frame: CTFrame) -> [CTLine] {
        CTFrameGetLines(frame) as? [CTLine] ?? []
    }

    private func getOrigins(_ frame: CTFrame, _ lineCount: Int) -> [CGPoint] {
        guard lineCount > 0 else { return [] }
        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        return origins
    }

    private func getFramePivot(_ suggestFrameSize: CGSize) -> CGPoint {
        let point = pivot * 0.5 + 0.5
        let x = (textBounds.width <= 0 ? suggestFrameSize.width : textBounds.width) * CGFloat(point.x)
        let y = (textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) * CGFloat(point.y)
        return CGPoint(x: x, y: y)
    }

    private func getVerticalOffset(_ suggestFrameSize: CGSize) -> CGFloat {
        switch verticalAlignment {
        case .top:
            return 0
        case .center:
            return ((textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) - suggestFrameSize.height) * 0.5
        case .bottom:
            return (textBounds.height <= 0 ? suggestFrameSize.height : textBounds.height) - suggestFrameSize.height
        }
    }
}
