//
//  TriangleGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/6/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import SatinCore

public final class TriangleGeometry: Geometry {
    public init(size: Float = 1) {
        super.init()
        setupData(size: size)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    func setupData(size: Float) {
        var geometryData = generateTriangleGeometryData(size)
        setFrom(&geometryData)
        freeGeometryData(&geometryData)
    }
}
