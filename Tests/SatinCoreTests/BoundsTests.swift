//
//  BoundsTests.swift
//
//
//  Created by Taylor Holliday on 8/3/22.
//

#if SWIFT_PACKAGE
import SatinCore
#else
#endif

import Satin
import simd
import XCTest

class BoundsTests: XCTestCase {
    func testComputeBoundsFromVertices() {
        var vertices0: [SatinVertex] = []

        XCTAssert(
            computeBoundsFromVertices(&vertices0, 0).equals(createBounds())
        )

        var vertices1 = [
            SatinVertex(position: .zero, normal: .zero, uv: .zero)
        ]

        XCTAssert(
            computeBoundsFromVertices(&vertices1, 1).equals(Bounds(min: .init(0, 0, 0), max: .init(0, 0, 0)))
        )

        var vertices2 = [
            SatinVertex(position: .init(0, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(1, 0, 0), normal: .zero, uv: .zero)
        ]

        XCTAssert(
            computeBoundsFromVertices(&vertices2, 2).equals(Bounds(min: .init(0, 0, 0), max: .init(1, 0, 0)))
        )

        var vertices3 = [
            SatinVertex(position: .init(0, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(1, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(0, 1, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(0, 0, 1), normal: .zero, uv: .zero)
        ]

        XCTAssert(
            computeBoundsFromVertices(&vertices3, 4).equals(Bounds(min: .zero, max: .one))
        )
    }

    func testComputeBoundsFromVerticesAndTransform() {
        let xform = translationMatrixf(1, 1, 1)

        var vertices0: [SatinVertex] = []
        XCTAssert(
            computeBoundsFromVerticesAndTransform(&vertices0, 0, xform).equals(createBounds())
        )

        var vertices1 = [
            SatinVertex(position: .init(0, 0, 0), normal: .init(0, 0, 0), uv: .init(0, 0))
        ]
        XCTAssert(
            computeBoundsFromVerticesAndTransform(&vertices1, 1, xform).equals(Bounds(min: .init(1, 1, 1), max: .init(1, 1, 1)))
        )

        var vertices2 = [
            SatinVertex(position: .init(0, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(1, 0, 0), normal: .zero, uv: .zero)
        ]

        XCTAssert(
            computeBoundsFromVerticesAndTransform(&vertices2, 2, xform).equals(Bounds(min: .init(1, 1, 1), max: .init(2, 1, 1)))
        )

        var vertices3 = [
            SatinVertex(position: .init(0, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(1, 0, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(0, 1, 0), normal: .zero, uv: .zero),
            SatinVertex(position: .init(0, 0, 1), normal: .zero, uv: .zero)
        ]
        XCTAssert(
            computeBoundsFromVerticesAndTransform(&vertices3, 4, xform).equals(Bounds(min: .init(1, 1, 1), max: .init(2, 2, 2)))
        )
    }

    func testTransformBounds() {
        let xform0 = translationMatrixf(1, 1, 1)

        XCTAssert(
            transformBounds(Bounds(min: .init(1, 1, 1), max: .init(2, 2, 2)), xform0).equals(Bounds(min: .init(2, 2, 2), max: .init(3, 3, 3)))
        )

        let xform1 = translationMatrixf(1, 0, 0)

        XCTAssert(
            transformBounds(Bounds(min: .init(1, 1, 1), max: .init(2, 2, 2)), xform1).equals(Bounds(min: .init(2, 1, 1), max: .init(3, 2, 2)))
        )

        let xform2 = scaleMatrixf(2, 2, 2)

        XCTAssert(
            transformBounds(Bounds(min: .init(1, 1, 1), max: .init(2, 2, 2)), xform2).equals(
                Bounds(min: .init(2, 2, 2), max: .init(4, 4, 4)))
        )
    }
}
