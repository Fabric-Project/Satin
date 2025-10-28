//
//  Transforms.c
//  Satin
//
//  Created by Reza Ali on 1/13/22.
//

#include "Conversions.h"
#include "Transforms.h"
#include <stdio.h>
#include <iostream>

simd_float4x4 translationMatrixf(float x, float y, float z) {
    simd_float4x4 result = matrix_identity_float4x4;
    result.columns[3] = simd_make_float4(x, y, z, 1.0);
    return result;
}

simd_float4x4 translationMatrix3f(simd_float3 p) {
    simd_float4x4 result = matrix_identity_float4x4;
    result.columns[3] = simd_make_float4(p, 1.0);
    return result;
}

simd_float4x4 scaleMatrixf(float x, float y, float z) {
    simd_float4x4 result = matrix_identity_float4x4;
    result.columns[0].x = x;
    result.columns[1].y = y;
    result.columns[2].z = z;
    return result;
}

simd_float4x4 scaleMatrix3f(simd_float3 p) {
    simd_float4x4 result = matrix_identity_float4x4;
    result.columns[0].x = p.x;
    result.columns[1].y = p.y;
    result.columns[2].z = p.z;
    return result;
}

// Reverse Z: Near Plane at 1, Far Plane at 0 (z comes in negative after camera view matrix is
// applied)
simd_float4x4
orthographicMatrixf(float left, float right, float bottom, float top, float near, float far) {
    const float rightMinusLeftInv = 1.0 / (right - left);
    const float topMinusBottomInv = 1.0 / (top - bottom);
    const float farMinusNearInv = 1.0 / (far - near);

    const float sx = 2.0 * rightMinusLeftInv;
    const float sy = 2.0 * topMinusBottomInv;
    const float sz = farMinusNearInv;
    const float sw = far * farMinusNearInv;

    const float px = -(right + left) * rightMinusLeftInv;
    const float py = -(bottom + top) * topMinusBottomInv;

    const simd_float4 col0 = simd_make_float4(sx, 0.0, 0.0, 0.0);
    const simd_float4 col1 = simd_make_float4(0.0, sy, 0.0, 0.0);
    const simd_float4 col2 = simd_make_float4(0.0, 0.0, sz, 0.0);
    const simd_float4 col3 = simd_make_float4(px, py, sw, 1.0);

    return simd_matrix(col0, col1, col2, col3);
}

simd_float4x4
frustrumMatrixf(float left, float right, float bottom, float top, float near, float far) {
    const float twoTimesNear = 2.0 * near;

    const float sx = twoTimesNear / (right - left);
    const float sy = twoTimesNear / (top - bottom);
    const float tx = (right + left) / (right - left);
    const float ty = (top + bottom) / (top - bottom);

    const float farMinusNear = far - near;

    const float sz = near / farMinusNear;
    const float sw = (far * near) / farMinusNear;

    const simd_float4 col0 = simd_make_float4(sx, 0.0, 0.0, 0.0);
    const simd_float4 col1 = simd_make_float4(0.0, sy, 0.0, 0.0);
    const simd_float4 col2 = simd_make_float4(tx, ty, sz, -1.0);
    const simd_float4 col3 = simd_make_float4(0.0, 0.0, sw, 0.0);

    return simd_matrix(col0, col1, col2, col3);
}

// Reverse Z: Near Plane at 1, Far Plane at 0 (z comes in negative after camera view matrix is
// applied)
simd_float4x4 perspectiveMatrixf(float fov, float aspect, float near, float far) {
    const float angle = degToRad(0.5 * fov);
    const float farMinusNear = far - near;

    const float sy = 1.0 / tanf(angle);
    const float sx = sy / aspect;

    const float sz = near / farMinusNear;
    const float sw = (far * near) / farMinusNear;

    const simd_float4 col0 = simd_make_float4(sx, 0.0, 0.0, 0.0);
    const simd_float4 col1 = simd_make_float4(0.0, sy, 0.0, 0.0);
    const simd_float4 col2 = simd_make_float4(0.0, 0.0, sz, -1.0);
    const simd_float4 col3 = simd_make_float4(0.0, 0.0, sw, 0.0);

    return simd_matrix(col0, col1, col2, col3);
}

// Frustum shift perspective projection matrix
simd_float4x4 frustumShiftPerspectiveMatrixf(float fov, float aspect, float near, float far, float lensShiftX, float lensShiftY) {

    const float halfFovRad = degToRad(0.5 * fov);
    const float top = near * tanf(halfFovRad);
    const float bottom = -top;
    const float right = top * aspect;
    const float left = -right;

    const float horizontalShift = lensShiftX * (right - left);
    const float verticalShift = lensShiftY * (top - bottom);

    const float shiftedLeft = left + horizontalShift;
    const float shiftedRight = right + horizontalShift;
    const float shiftedBottom = bottom + verticalShift;
    const float shiftedTop = top + verticalShift;

    return frustrumMatrixf(shiftedLeft, shiftedRight, shiftedBottom, shiftedTop, near, far);
}

simd_float4x4 lookAtMatrix3f(simd_float3 eye, simd_float3 at, simd_float3 up) {
    simd_float4x4 result = matrix_identity_float4x4;

    const simd_float3 zAxis = simd_normalize(at - eye);
    const simd_float3 xAxis = simd_normalize(simd_cross(up, zAxis));
    const simd_float3 yAxis = simd_normalize(simd_cross(zAxis, xAxis));

    result.columns[0].x = xAxis.x;
    result.columns[0].y = xAxis.y;
    result.columns[0].z = xAxis.z;

    result.columns[1].x = yAxis.x;
    result.columns[1].y = yAxis.y;
    result.columns[1].z = yAxis.z;

    result.columns[2].x = zAxis.x;
    result.columns[2].y = zAxis.y;
    result.columns[2].z = zAxis.z;

    result.columns[3].x = eye.x;
    result.columns[3].y = eye.y;
    result.columns[3].z = eye.z;

    return result;
}
