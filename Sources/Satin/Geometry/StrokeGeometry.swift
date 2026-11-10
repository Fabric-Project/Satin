//
//  StrokeGeometry.swift
//  Satin
//
//  Created by Anton Marini on 10/3/25.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

import simd

/// One line to draw as a ribbon: points or a sampled `BezierPath`, open or closed, with its own
/// style and optional per-point widths and colors. Strokes in one `StrokeGeometry` are not
/// connected, so an array of them draws lines with gaps between them.
public struct Stroke: Equatable {
    /// Mirrors `appendStrokeGeometryData`'s `joinStyle` integer convention.
    public enum Join: Int32 {
        case miter = 0
        case bevel = 1
        case round = 2
    }

    /// Mirrors `appendStrokeGeometryData`'s `capStyle` integer convention
    /// (ignored when the stroke is closed).
    public enum Cap: Int32 {
        case butt = 0
        case square = 1
        case round = 2
    }

    /// How a stroke is drawn as a ribbon: its width, the shape of its joins and caps, and
    /// the plane it lies in (perpendicular to `up`).
    public struct Style: Equatable {
        public var width: Float
        public var join: Join
        /// Ignored when the stroke is closed.
        public var cap: Cap
        /// How far a miter may reach, in half-widths, before the join falls back to a bevel.
        public var miterLimit: Float
        /// Segments in each round join's fan and each round cap's half circle.
        public var roundResolution: Int
        public var up: simd_float3

        public init(width: Float = 0.1, join: Join = .miter, cap: Cap = .butt,
                    miterLimit: Float = 4, roundResolution: Int = 8, up: simd_float3 = [0, 0, 1]) {
            self.width = width
            self.join = join
            self.cap = cap
            self.miterLimit = miterLimit
            self.roundResolution = roundResolution
            self.up = up
        }
    }

    public var points: ContiguousArray<simd_float3>
    public var closed: Bool
    public var style: Style
    /// Multiplies `style.width` per point. May be shorter than `points` (its last value repeats)
    /// or empty (1).
    public var widthScales: ContiguousArray<Float>
    /// Colors each point. May be shorter than `points` (its last value repeats) or empty (opaque white).
    public var colors: ContiguousArray<simd_float4>
    /// Texture u at this stroke's first and last tips. A cut made with `revealingTexture` sets it so
    /// the texture stays where it was on the whole line.
    public var textureRange: simd_float2 = [0, 1]

    /// A stroke of one color.
    public init(points: ContiguousArray<simd_float3>, closed: Bool = false, color: simd_float4 = [1, 1, 1, 1],
                style: Style = Style(), widthScales: ContiguousArray<Float> = []) {
        self.init(points: points, closed: closed, colors: [color], style: style, widthScales: widthScales)
    }

    /// A stroke colored per point.
    public init(points: ContiguousArray<simd_float3>, closed: Bool = false, colors: ContiguousArray<simd_float4>,
                style: Style = Style(), widthScales: ContiguousArray<Float> = []) {
        self.points = points
        self.closed = closed
        self.colors = colors
        self.style = style
        self.widthScales = widthScales
    }

    /// A stroke along `path`, closed when the path is. The path is sampled here with `angleLimit`
    /// (see `BezierPath.sampledPoints(angleLimit:)`), then thinned with
    /// `simplifyPolyline(_:tolerance:closed:)` when `simplifyTolerance` is above 0.
    public init(path: BezierPath, color: simd_float4 = [1, 1, 1, 1], style: Style = Style(),
                angleLimit: Float = .pi / 36, simplifyTolerance: Float = 0) {
        let points = simplifyPolyline(path.sampledPoints(angleLimit: angleLimit), tolerance: simplifyTolerance, closed: path.isClosed)
        self.init(points: points, closed: path.isClosed, color: color, style: style)
    }
}

public extension Stroke {
    /// One stroke per strip of `points` (one for points without strips), in `style`, closed where the
    /// strip is or `closesAll`. Each point's `.size` multiplies the width and its `.color` colors it.
    /// Nil when the CPU can't read the points: they must have been written by the CPU (see
    /// `PublishedAttribute.isCPUWritten`), as a GPU pass's points can't be without a readback.
    static func strokes(from points: Points, style: Style, closesAll: Bool) -> [Stroke]? {
        guard let positionFloats = points.position.cpuFloats(components: 3) else { return nil }
        var colorFloats: ContiguousArray<Float>?
        if let color = points.attribute(.color) {
            guard let floats = color.cpuFloats(components: 4) else { return nil }
            colorFloats = floats
        }
        var sizes: ContiguousArray<Float>?
        if let size = points.attribute(.size) {
            guard let floats = size.cpuFloats(components: 1) else { return nil }
            sizes = floats
        }

        let ranges: [(range: Range<Int>, closed: Bool)]
        switch points.topology {
            case let .strips(strips): ranges = strips.map { ($0.range, closesAll || $0.closed) }
            case .implicit, .indexed: ranges = [(0 ..< points.count, closesAll)]
        }
        return ranges.compactMap { strip in
            guard !strip.range.isEmpty else { return nil }
            let strokePoints = ContiguousArray(strip.range.map {
                simd_float3(positionFloats[$0 * 3], positionFloats[$0 * 3 + 1], positionFloats[$0 * 3 + 2])
            })
            let colors = colorFloats.map { floats in
                ContiguousArray(strip.range.map { simd_float4(floats[$0 * 4], floats[$0 * 4 + 1], floats[$0 * 4 + 2], floats[$0 * 4 + 3]) })
            } ?? []
            let widthScales = sizes.map { values in ContiguousArray(strip.range.map { values[$0] }) } ?? []
            return Stroke(points: strokePoints, closed: strip.closed, colors: colors, style: style, widthScales: widthScales)
        }
    }

    /// The distance along the line, including a closed stroke's closing side.
    var totalLength: Float {
        guard points.count >= 2 else { return 0 }
        let path = closed ? points + [points[0]] : points
        return zip(path, path.dropFirst()).reduce(Float(0)) { $0 + simd_distance($1.0, $1.1) }
    }

    /// The part of this stroke between `start` and `end`, as fractions of its length from 0 to 1, in
    /// either order. It has real caps and joins, and widths and colors are interpolated at each cut.
    /// The whole range returns this stroke unchanged; any less of a closed stroke is open. An empty
    /// range has no points. A stroke of one point has no length to cut, so it stays whole otherwise.
    /// With `revealingTexture` the texture stays put on the line instead of fitting to what is left.
    func trimmed(start: Float, end: Float, revealingTexture: Bool = false) -> Stroke {
        let first = min(max(min(start, end), 0), 1)
        let last = min(max(max(start, end), 0), 1)
        if first == 0, last == 1 { return self }

        let nothing = Stroke(points: [], closed: false, colors: [], style: style)
        guard last > first else { return nothing }
        let length = totalLength
        guard length > 0 else { return self }
        // One dash, with a gap too long for a second to fit.
        return dashed(length: (last - first) * length, gap: length, offset: first * length, revealingTexture: revealingTexture).first ?? nothing
    }

    /// How far the cap at the first or last point reaches past it, which texture u includes.
    private func capReach(atEnd: Bool) -> Float {
        guard style.cap != .butt, !closed, !points.isEmpty else { return 0 }
        let widthScale = widthScales.isEmpty ? 1 : widthScales[atEnd ? min(points.count, widthScales.count) - 1 : 0]
        return style.width * 0.5 * widthScale
    }

    /// `textureRange` for `piece`, cut from this stroke between two distances along it: this stroke's
    /// texture u at the piece's tips.
    private func revealedTextureRange(of piece: Stroke, from start: Float, to end: Float) -> simd_float2 {
        let startReach = capReach(atEnd: false)
        let span = max(startReach + totalLength + capReach(atEnd: true), 1e-6)
        func textureU(at distance: Float) -> Float {
            simd_mix(textureRange.x, textureRange.y, (startReach + distance) / span)
        }
        return [textureU(at: start - piece.capReach(atEnd: false)), textureU(at: end + piece.capReach(atEnd: true))]
    }

    /// This stroke cut into dashes of `length` with gaps of `gap`, measured along the line, each a
    /// stroke of its own with this stroke's style, so it has real caps and joins. `offset` slides the
    /// pattern along the line. Widths and colors are interpolated at each cut. A closed stroke dashes
    /// around its loop. A length or gap of 0, or a stroke of fewer than two points, stays whole. Each
    /// dash fits the whole texture, or with `revealingTexture` shows its part of this stroke's.
    func dashed(length: Float, gap: Float, offset: Float = 0, revealingTexture: Bool = false) -> [Stroke] {
        let period = length + gap
        guard length > 0, gap > 0, points.count >= 2 else { return [self] }

        // Too small a pattern to see would only cost memory.
        guard totalLength / period <= 100_000 else { return [self] }

        let path = closed ? points + [points[0]] : points

        func value<Value>(_ values: ContiguousArray<Value>, at index: Int) -> Value {
            values[min(index % points.count, values.count - 1)]
        }

        var dashes: [Stroke] = []
        var current = Stroke(points: [], closed: false, colors: [], style: style)
        func appendPoint(segment: Int, fraction: Float) {
            let next = segment + 1
            let point = simd_mix(path[segment], path[next], simd_float3(repeating: fraction))
            // A dash ending exactly on a corner reaches that point twice.
            if current.points.last == point { return }
            current.points.append(point)
            if !widthScales.isEmpty {
                current.widthScales.append(simd_mix(value(widthScales, at: segment), value(widthScales, at: next), fraction))
            }
            if !colors.isEmpty {
                current.colors.append(simd_mix(value(colors, at: segment), value(colors, at: next), simd_float4(repeating: fraction)))
            }
        }
        var dashStart: Float = 0
        func finishDash(at distance: Float) {
            if current.points.count >= 2 {
                if revealingTexture { current.textureRange = revealedTextureRange(of: current, from: dashStart, to: distance) }
                dashes.append(current)
            }
            current = Stroke(points: [], closed: false, colors: [], style: style)
        }

        // Where the line's start falls in the pattern: in a dash below `length`, in a gap above it.
        var phase = (-offset).truncatingRemainder(dividingBy: period)
        if phase < 0 { phase += period }
        var inDash = phase < length
        var remaining = inDash ? length - phase : period - phase
        if inDash { appendPoint(segment: 0, fraction: 0) }

        var walked: Float = 0
        for segment in 0 ..< path.count - 1 {
            let segmentLength = simd_distance(path[segment], path[segment + 1])
            guard segmentLength > 0 else { continue }
            var travelled: Float = 0
            while segmentLength - travelled > remaining {
                travelled += remaining
                appendPoint(segment: segment, fraction: travelled / segmentLength)
                if inDash { finishDash(at: walked + travelled) } else { dashStart = walked + travelled }
                inDash.toggle()
                remaining = inDash ? length : gap
            }
            remaining -= segmentLength - travelled
            if inDash { appendPoint(segment: segment, fraction: 1) }
            walked += segmentLength
        }
        finishDash(at: walked)
        return dashes
    }
}

/// How a `StrokeGeometry` divides into pieces (see `GeometryPieces`).
public enum StrokePieces: Equatable {
    /// No pieces: the geometry carries no joint attributes.
    case none
    /// One piece per stroke, in order. A stroke that draws nothing keeps its index with no vertices.
    case strokes
    /// One piece per stroke with `groups` naming each stroke's group, one value per stroke, and a
    /// parent piece for each run of equal values, before its children.
    case groups([Int])
    /// One piece for each run of equal values in `groups`, covering all of its strokes.
    case mergedGroups([Int])
}

/// A triangulated ribbon mesh tessellated from one or more `Stroke`s, with joins
/// (miter/bevel/round), caps (butt/square/round), and optional per-point width scales
/// and colors. Beyond the usual Position/Normal/Texcoord/Color, each vertex carries
/// `.Custom0` (side, width scale relative to its stroke's `style.width`, corner type, reserved),
/// `.Custom1` (core point) and `.Custom2` (neighbor point), so a shader can rebuild a
/// camera-facing offset instead of trusting Position outright. Texcoord's u runs from 0 to 1 by
/// length along each stroke.
///
/// Tessellation runs in SatinCore (`appendStrokeGeometryData`) for performance, straight
/// into C-allocated memory this geometry owns and reuses, growing it only when strokes need
/// more. The vertex and index buffers, and their attributes, are made once. Each update uploads
/// into a new Metal buffer, so a draw already recorded keeps the ribbon it was recorded with.
public final class StrokeGeometry: Geometry {
    private var geometryData: StrokeGeometryData = createStrokeGeometryData()
    private let ribbonVertexBuffer = InterleavedBuffer(index: .Vertices, data: nil, stride: MemoryLayout<StrokeVertex>.stride, count: 0, source: nil)
    private let ribbonIndexBuffer = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)

    public init(context: Context) {
        super.init(context: context, primitiveType: .triangle, windingOrder: .counterClockwise)
        mutability = .dynamicData
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.position)!), for: .Position)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.normal)!), for: .Normal)
        addAttribute(Float2InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.uv)!), for: .Texcoord)
        addAttribute(Float4InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.custom0)!), for: .Custom0)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.custom1)!), for: .Custom1)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.custom2)!), for: .Custom2)
        addAttribute(Float4InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<StrokeVertex>.offset(of: \.color)!), for: .Color)
        setElements(ribbonIndexBuffer)
    }

    deinit {
        freeStrokeGeometryData(&geometryData)
    }

    /// Rebuilds the geometry as one line of one color.
    public func update(points: ContiguousArray<simd_float3>, closed: Bool = false, color: simd_float4 = [1, 1, 1, 1],
                       style: Stroke.Style = Stroke.Style(), widthScales: ContiguousArray<Float> = []) {
        update(strokes: [Stroke(points: points, closed: closed, color: color, style: style, widthScales: widthScales)])
    }

    /// Rebuilds the geometry as one line colored per point.
    public func update(points: ContiguousArray<simd_float3>, closed: Bool = false, colors: ContiguousArray<simd_float4>,
                       style: Stroke.Style = Stroke.Style(), widthScales: ContiguousArray<Float> = []) {
        update(strokes: [Stroke(points: points, closed: closed, colors: colors, style: style, widthScales: widthScales)])
    }

    /// Rebuilds the geometry from separate strokes, in order. A stroke of one distinct point draws
    /// a dot when its cap is round and nothing otherwise, and no strokes clear the geometry.
    ///
    /// `pieces` divides the result for animating with a joint palette. Each update makes new pieces,
    /// and too many for `GeometryPieces` draws whole. `bend` (0 to 1) tilts each normal toward its
    /// edge, so a flat ribbon lights like a tube, as `GPUStrokeTessellation` does.
    public func update(strokes: [Stroke], pieces: StrokePieces = .none, bend: Float = 0) {
        let bendAngle = min(max(bend, 0), 1) * .pi / 2
        resetStrokeGeometryData(&geometryData)
        var strokeEnds: [Int] = []
        if pieces != .none { strokeEnds.reserveCapacity(strokes.count) }
        for stroke in strokes {
            let firstVertex = Int(geometryData.vertexCount)
            stroke.points.withUnsafeBufferPointer { pointsBuffer in
                stroke.widthScales.withUnsafeBufferPointer { widthScalesBuffer in
                    stroke.colors.withUnsafeBufferPointer { colorsBuffer in
                        appendStrokeGeometryData(
                            &geometryData,
                            pointsBuffer.baseAddress,
                            Int32(pointsBuffer.count),
                            stroke.closed,
                            stroke.style.width,
                            stroke.style.join.rawValue,
                            stroke.style.cap.rawValue,
                            stroke.style.miterLimit,
                            stroke.style.up,
                            Int32(stroke.style.roundResolution),
                            widthScalesBuffer.baseAddress,
                            Int32(widthScalesBuffer.count),
                            colorsBuffer.baseAddress,
                            Int32(colorsBuffer.count)
                        )
                    }
                }
            }
            if bendAngle > 0, let vertices = geometryData.vertexData {
                Self.bendNormals(vertices, range: firstVertex ..< Int(geometryData.vertexCount),
                                 up: simd_normalize(stroke.style.up), angle: bendAngle)
            }
            if stroke.textureRange != [0, 1], let vertices = geometryData.vertexData {
                for vertexIndex in firstVertex ..< Int(geometryData.vertexCount) {
                    vertices[vertexIndex].uv.x = simd_mix(stroke.textureRange.x, stroke.textureRange.y, vertices[vertexIndex].uv.x)
                }
            }
            if pieces != .none { strokeEnds.append(Int(geometryData.vertexCount)) }
        }

        // The storage moves only when it grows; the buffers copy from it at upload either way.
        ribbonVertexBuffer.updateData(data: UnsafeMutableRawPointer(geometryData.vertexData), stride: MemoryLayout<StrokeVertex>.stride,
                                      count: Int(geometryData.vertexCount), source: nil)
        ribbonIndexBuffer.updateData(data: UnsafeMutableRawPointer(geometryData.indexData), count: Int(geometryData.indexCount) * 3, source: nil)

        if pieces != .none {
            setPieces(Self.makePieces(pieces, strokes: strokes, strokeEnds: strokeEnds))
        } else if self.pieces != nil {
            setPieces(nil)
        }
    }

    /// Each normal tilted by `angle` from `up` toward its vertex's offset from its core point
    /// (`custom1`); a vertex on the line itself keeps facing `up`.
    private static func bendNormals(_ vertices: UnsafeMutablePointer<StrokeVertex>, range: Range<Int>, up: simd_float3, angle: Float) {
        let upAmount = cos(angle)
        let outAmount = sin(angle)
        for index in range {
            var radial = vertices[index].position - vertices[index].custom1
            radial -= simd_dot(radial, up) * up
            let length = simd_length(radial)
            vertices[index].normal = length > 1e-6 ? simd_normalize(up * upAmount + radial / length * outAmount) : up
        }
    }

    private static func makePieces(_ pieces: StrokePieces, strokes: [Stroke], strokeEnds: [Int]) -> GeometryPieces? {
        guard let vertexEnd = strokeEnds.last, vertexEnd > 0 else { return nil }

        var parentIndices: [Int] = []
        var centers: [simd_float3] = []
        var sizes: [Float] = []
        var vertexRanges: [Range<Int>] = []

        // A stroke's piece: the middle of its points' bounds, and its ribbon's approximate area.
        func appendStroke(_ index: Int, parent: Int) {
            let stroke = strokes[index]
            parentIndices.append(parent)
            centers.append(boundsCenter(of: stroke.points[...]))
            sizes.append(ribbonArea(of: stroke))
            vertexRanges.append((index > 0 ? strokeEnds[index - 1] : 0) ..< strokeEnds[index])
        }

        switch pieces {
        case .none:
            return nil
        case .strokes:
            for index in strokes.indices { appendStroke(index, parent: -1) }
        case let .groups(groups), let .mergedGroups(groups):
            guard groups.count == strokes.count else { return nil }
            var hasChildren = true
            if case .mergedGroups = pieces { hasChildren = false }
            var index = 0
            while index < strokes.count {
                var runEnd = index + 1
                while runEnd < strokes.count, groups[runEnd] == groups[index] { runEnd += 1 }

                let parent = parentIndices.count
                let allPoints = strokes[index ..< runEnd].flatMap(\.points)
                parentIndices.append(-1)
                centers.append(boundsCenter(of: allPoints[...]))
                sizes.append(strokes[index ..< runEnd].reduce(Float(0)) { $0 + ribbonArea(of: $1) })
                vertexRanges.append((index > 0 ? strokeEnds[index - 1] : 0) ..< strokeEnds[runEnd - 1])
                if hasChildren {
                    for child in index ..< runEnd { appendStroke(child, parent: parent) }
                }
                index = runEnd
            }
        }

        return try? GeometryPieces(parentIndices: parentIndices, centers: centers, sizes: sizes, sizeMeasure: .area, vertexRanges: vertexRanges)
    }

    private static func boundsCenter<Points: Collection>(of points: Points) -> simd_float3 where Points.Element == simd_float3 {
        guard let first = points.first else { return .zero }
        var lower = first
        var upper = first
        for point in points {
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
        }
        return (lower + upper) / 2
    }

    /// Its length times its mean width, or a disc's area for a dot. Enough to weigh pieces by.
    private static func ribbonArea(of stroke: Stroke) -> Float {
        let meanScale = stroke.widthScales.isEmpty ? 1 : stroke.widthScales.reduce(0, +) / Float(stroke.widthScales.count)
        let width = stroke.style.width * meanScale
        guard stroke.points.count >= 2 else { return stroke.points.isEmpty ? 0 : .pi * width * width / 4 }
        var length: Float = 0
        for (start, end) in zip(stroke.points, stroke.points.dropFirst()) { length += simd_distance(start, end) }
        if stroke.closed, let first = stroke.points.first, let last = stroke.points.last { length += simd_distance(last, first) }
        return length * max(width, 0)
    }
}
