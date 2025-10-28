//
//  Types.c
//  Satin
//
//  Created by Reza Ali on 7/5/20.
//

#include <malloc/_malloc.h>
#include <string.h>

#include "Geometry.h"
#include "Types.h"
#include <Accelerate/Accelerate.h>

Points2D createPoints2D(void) { return (Points2D) { .count = 0, .data = NULL }; }

void freePoints2D(Points2D *points) {
    if (points->count > 0 && points->data != NULL) {
        free(points->data);
        points->count = 0;
        points->data = NULL;
    }
}

TriangleFaceMap createTriangleFaceMap() { return (TriangleFaceMap) { .count = 0, .data = NULL }; }

void appendFaceMapData(TriangleFaceMap *dest, int index, int count) {
    if (dest->count > 0) {
        int totalCount = dest->count + count;
        size_t newSize = sizeof(uint32_t) * totalCount;

        dest->data = (uint32_t *)realloc(dest->data, newSize);
        for (int i = dest->count; i < totalCount; i++) {
            dest->data[i] = index;
        }

        dest->count = totalCount;
    } else {
        size_t newSize = sizeof(uint32_t) * count;
        dest->data = (uint32_t *)malloc(newSize);

        for (int i = 0; i < count; i++) {
            dest->data[i] = index;
        }

        dest->count = count;
    }
}

void freeTriangleFaceMap(TriangleFaceMap *map) {
    if (map->count > 0 && map->data != NULL) {
        free(map->data);
        map->count = 0;
        map->data = NULL;
    }
}

TriangleData createTriangleData(void) { return (TriangleData) { .count = 0, .indices = NULL }; }

void freeTriangleData(TriangleData *data) {
    if (data->count > 0 && data->indices != NULL) {
        free(data->indices);
        data->count = 0;
        data->indices = NULL;
    }
}

GeometryData createGeometryData() {
    return (
        GeometryData) { .vertexCount = 0, .vertexData = NULL, .indexCount = 0, .indexData = NULL };
}

void freeGeometryData(GeometryData *data) {
    if (data->vertexCount > 0 && data->vertexData != NULL) {
        free(data->vertexData);
        data->vertexCount = 0;
        data->vertexData = NULL;
    }

    if (data->indexCount > 0 && data->indexData != NULL) {
        free(data->indexData);
        data->indexCount = 0;
        data->indexData = NULL;
    }
}

void combineVertexGeometryData(GeometryData *dest, GeometryData *src) {
    if (src->vertexCount > 0) {
        if (dest->vertexCount > 0) {
            int totalCount = src->vertexCount + dest->vertexCount;
            dest->vertexData =
                (SatinVertex *)realloc(dest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                dest->vertexData + dest->vertexCount,
                src->vertexData,
                src->vertexCount * sizeof(SatinVertex));
            dest->vertexCount += src->vertexCount;
        } else {
            dest->vertexData = (SatinVertex *)malloc(src->vertexCount * sizeof(SatinVertex));
            memcpy(dest->vertexData, src->vertexData, src->vertexCount * sizeof(SatinVertex));
            dest->vertexCount = src->vertexCount;
        }
    }
}

void combineIndexGeometryData(
    GeometryData *dest, GeometryData *src, int destPreCombineVertexCount) {
    if (src->indexCount > 0) {
        if (dest->indexCount > 0) {
            int totalCount = src->indexCount + dest->indexCount;
            dest->indexData =
                (TriangleIndices *)realloc(dest->indexData, totalCount * sizeof(TriangleIndices));
            memcpy(
                dest->indexData + dest->indexCount,
                src->indexData,
                src->indexCount * sizeof(TriangleIndices));
            if (destPreCombineVertexCount > 0) {
                for (int i = dest->indexCount; i < totalCount; i++) {
                    dest->indexData[i].i0 += destPreCombineVertexCount;
                    dest->indexData[i].i1 += destPreCombineVertexCount;
                    dest->indexData[i].i2 += destPreCombineVertexCount;
                }
            }
            dest->indexCount += src->indexCount;
        } else {
            dest->indexData = (TriangleIndices *)malloc(sizeof(TriangleIndices) * src->indexCount);
            memcpy(dest->indexData, src->indexData, sizeof(TriangleIndices) * src->indexCount);
            dest->indexCount = src->indexCount;
        }
    }
}

void copyVertexDataToGeometryData(SatinVertex *vertices, int count, GeometryData *destData) {
    GeometryData srcData = createGeometryData();
    srcData.vertexData = vertices;
    srcData.vertexCount = count;

    combineVertexGeometryData(destData, &srcData);
}

void copyTriangleDataToGeometryData(TriangleData *triData, GeometryData *destData) {
    GeometryData srcData = createGeometryData();
    srcData.indexData = triData->indices;
    srcData.indexCount = triData->count;

    combineIndexGeometryData(destData, &srcData, destData->vertexCount);
}

void createGeometryDataFromPaths(
    simd_float2 **paths, int *lengths, int count, GeometryData *geoData, simd_float4 pathBounds ) {
    int vertexCount = 0;
    for (int i = 0; i < count; i++) {
        vertexCount += lengths[i];
    }

    geoData->vertexCount = vertexCount;
    geoData->vertexData = (SatinVertex *)malloc(sizeof(SatinVertex) * geoData->vertexCount);

    int index = 0;
    for (int i = 0; i < count; i++) {
        const int pathLength = lengths[i];
        const simd_float2 *subpath = paths[i];
        for (int j = 0; j < pathLength; j++) {
            const simd_float2 &pt = subpath[j];
            
            geoData->vertexData[index++] =
            (SatinVertex) { .position = simd_make_float3(pt.x, pt.y, 0.0),
                    .normal = simd_make_float3(0.0, 0.0, 1.0),
                    .uv = simd_make_float2((pt.x - pathBounds[0])/(pathBounds[2] - pathBounds[0]),
                                           (pt.y - pathBounds[1])/(pathBounds[3] - pathBounds[1]) )};
//                                                       (float)pt.x / (float)pathLength ,
//                                                       (float)pt.y / (float)pathLength ) };
//                                .uv = simd_make_float2((float)j / (float)pathLength, 0.0) };
        }
    }
}

void createGeometryDataFromPolylines(Polylines2D *polylines, GeometryData *geoData) {
    int vertexCount = 0;
    for (int i = 0; i < polylines->count; i++) {
        vertexCount += polylines->data[i].count;
    }

    geoData->vertexCount = vertexCount;
    geoData->vertexData = (SatinVertex *)malloc(sizeof(SatinVertex) * geoData->vertexCount);

    int index = 0;
    for (int i = 0; i < polylines->count; i++) {
        const Polyline2D *polyline = &polylines->data[i];
        const int pathLength = polyline->count;
        const simd_float2 *subpath = polyline->data;
        for (int j = 0; j < pathLength; j++) {
            const simd_float2 &pt = subpath[j];
            geoData->vertexData[index++] =
                (SatinVertex) { .position = simd_make_float3(pt.x, pt.y, 0.0),
                                .normal = simd_make_float3(0.0, 0.0, 1.0),
                                .uv = simd_make_float2((float)j / (float)pathLength, 0.0) };
        }
    }
}

void addTrianglesToGeometryData(GeometryData *dest, TriangleIndices *triangles, int triangleCount) {
    if (triangleCount > 0) {
        if (dest->indexCount > 0) {
            int totalCount = triangleCount + dest->indexCount;
            dest->indexData =
                (TriangleIndices *)realloc(dest->indexData, totalCount * sizeof(TriangleIndices));
            memcpy(
                dest->indexData + dest->indexCount,
                triangles,
                triangleCount * sizeof(TriangleIndices));
            dest->indexCount += triangleCount;
        } else {
            dest->indexData = (TriangleIndices *)malloc(sizeof(TriangleIndices) * triangleCount);
            memcpy(dest->indexData, triangles, sizeof(TriangleIndices) * triangleCount);
            dest->indexCount = triangleCount;
        }
    }
}

void combineTriangleFaceMap(TriangleFaceMap *dest, const TriangleFaceMap *src) {
    if (src->count > 0) {
        size_t srcSize = sizeof(uint32_t) * src->count;

        if (dest->count > 0) {
            int totalCount = src->count + dest->count;
            size_t destSize = sizeof(uint32_t) * totalCount;

            dest->data = (uint32_t *)realloc(dest->data, destSize);
            memcpy(dest->data + dest->count, src->data, srcSize);

            dest->count = totalCount;
        } else {
            dest->data = (uint32_t *)malloc(srcSize);
            memcpy(dest->data, src->data, srcSize);

            dest->count = src->count;
        }
    }
}

void combineTriangleData(TriangleData *dest, const TriangleData *src, int offset) {
    if (src->count > 0) {
        if (dest->count > 0) {
            int totalCount = src->count + dest->count;
            dest->indices =
                (TriangleIndices *)realloc(dest->indices, totalCount * sizeof(TriangleIndices));
            memcpy(dest->indices + dest->count, src->indices, src->count * sizeof(TriangleIndices));
            if (offset > 0) {
                for (int i = dest->count; i < totalCount; i++) {
                    TriangleIndices *t = &dest->indices[i];
                    t->i0 += offset;
                    t->i1 += offset;
                    t->i2 += offset;
                }
            }
            dest->count = totalCount;
        } else {
            dest->indices = (TriangleIndices *)malloc(sizeof(TriangleIndices) * src->count);
            memcpy(dest->indices, src->indices, sizeof(TriangleIndices) * src->count);
            dest->count = src->count;
        }
    }
}

void combineGeometryData(GeometryData *dest, GeometryData *src) {
    int destPreCombineVertexCount = dest->vertexCount;
    combineVertexGeometryData(dest, src);
    combineIndexGeometryData(dest, src, destPreCombineVertexCount);
}

void combineGeometryDataAndTriangleFaceMap(
    GeometryData *destGeo,
    GeometryData *srcGeo,
    TriangleFaceMap *destMap,
    TriangleFaceMap *srcMap) {
    combineGeometryData(destGeo, srcGeo);

    if (srcMap->count > 0) {
        if (destMap->count > 0) {
            int totalCount = srcMap->count + destMap->count;
            destMap->data = (uint32_t *)realloc(destMap->data, totalCount * sizeof(uint32_t));
            memcpy(destMap->data + destMap->count, srcMap->data, srcMap->count * sizeof(uint32_t));
            destMap->count += srcMap->count;
        } else {
            destMap->data = (uint32_t *)malloc(srcMap->count * sizeof(uint32_t));
            memcpy(destMap->data, srcMap->data, srcMap->count * sizeof(uint32_t));
            destMap->count = srcMap->count;
        }
    }
}

void combineAndOffsetGeometryData(GeometryData *dest, GeometryData *src, simd_float3 offset) {
    int destPreCombineVertexCount = dest->vertexCount;

    if (src->vertexCount > 0) {
        if (dest->vertexCount > 0) {
            int totalCount = src->vertexCount + dest->vertexCount;
            dest->vertexData =
                (SatinVertex *)realloc(dest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                dest->vertexData + dest->vertexCount,
                src->vertexData,
                src->vertexCount * sizeof(SatinVertex));
            for (int i = dest->vertexCount; i < totalCount; i++) {
                dest->vertexData[i].position += offset;
            }
            dest->vertexCount += src->vertexCount;
        } else {
            dest->vertexData = (SatinVertex *)malloc(src->vertexCount * sizeof(SatinVertex));
            memcpy(dest->vertexData, src->vertexData, src->vertexCount * sizeof(SatinVertex));
            for (int i = 0; i < src->vertexCount; i++) {
                dest->vertexData[i].position += offset;
            }
            dest->vertexCount = src->vertexCount;
        }
    }

    combineIndexGeometryData(dest, src, destPreCombineVertexCount);
}

void combineAndScaleGeometryData(GeometryData *dest, GeometryData *src, simd_float3 scale) {
    int destPreCombineVertexCount = dest->vertexCount;

    if (src->vertexCount > 0) {
        if (dest->vertexCount > 0) {
            int totalCount = src->vertexCount + dest->vertexCount;
            dest->vertexData =
                (SatinVertex *)realloc(dest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                dest->vertexData + dest->vertexCount,
                src->vertexData,
                src->vertexCount * sizeof(SatinVertex));
            for (int i = dest->vertexCount; i < totalCount; i++) {
                dest->vertexData[i].position *= scale;
            }
            dest->vertexCount += src->vertexCount;
        } else {
            dest->vertexData = (SatinVertex *)malloc(src->vertexCount * sizeof(SatinVertex));
            memcpy(dest->vertexData, src->vertexData, src->vertexCount * sizeof(SatinVertex));
            for (int i = 0; i < src->vertexCount; i++) {
                dest->vertexData[i].position *= scale;
            }
            dest->vertexCount = src->vertexCount;
        }
    }

    combineIndexGeometryData(dest, src, destPreCombineVertexCount);
}

void combineAndScaleAndOffsetGeometryData(
    GeometryData *dest, GeometryData *src, simd_float3 scale, simd_float3 offset) {
    int destPreCombineVertexCount = dest->vertexCount;

    if (src->vertexCount > 0) {
        if (dest->vertexCount > 0) {
            int totalCount = src->vertexCount + dest->vertexCount;
            dest->vertexData =
                (SatinVertex *)realloc(dest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                dest->vertexData + dest->vertexCount,
                src->vertexData,
                src->vertexCount * sizeof(SatinVertex));
            for (int i = dest->vertexCount; i < totalCount; i++) {
                dest->vertexData[i].position *= scale;
                dest->vertexData[i].position += offset;
            }
            dest->vertexCount += src->vertexCount;
        } else {
            dest->vertexData = (SatinVertex *)malloc(src->vertexCount * sizeof(SatinVertex));
            memcpy(dest->vertexData, src->vertexData, src->vertexCount * sizeof(SatinVertex));
            for (int i = 0; i < src->vertexCount; i++) {
                dest->vertexData[i].position *= scale;
                dest->vertexData[i].position += offset;
            }
            dest->vertexCount = src->vertexCount;
        }
    }

    combineIndexGeometryData(dest, src, destPreCombineVertexCount);
}

void combineAndTransformGeometryData(
    GeometryData *dest, GeometryData *src, simd_float4x4 transform) {
    int destPreCombineVertexCount = dest->vertexCount;
    simd_float4x4 rotation = simd_transpose(simd_inverse(transform));
    simd_float3x3 rot = simd_matrix(
        simd_make_float3(rotation.columns[0]),
        simd_make_float3(rotation.columns[1]),
        simd_make_float3(rotation.columns[2]));

    if (src->vertexCount > 0) {
        if (dest->vertexCount > 0) {
            int totalCount = src->vertexCount + dest->vertexCount;
            dest->vertexData =
                (SatinVertex *)realloc(dest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                dest->vertexData + dest->vertexCount,
                src->vertexData,
                src->vertexCount * sizeof(SatinVertex));
            for (int i = dest->vertexCount; i < totalCount; i++) {
                dest->vertexData[i].position = simd_make_float3(
                    simd_mul(transform, simd_make_float4(dest->vertexData[i].position, 1.0)));
                dest->vertexData[i].normal = simd_mul(rot, dest->vertexData[i].normal);
            }
            dest->vertexCount += src->vertexCount;
        } else {
            dest->vertexData = (SatinVertex *)malloc(src->vertexCount * sizeof(SatinVertex));
            memcpy(dest->vertexData, src->vertexData, src->vertexCount * sizeof(SatinVertex));
            for (int i = 0; i < src->vertexCount; i++) {
                dest->vertexData[i].position = simd_make_float3(
                    simd_mul(transform, simd_make_float4(dest->vertexData[i].position, 1.0)));
                dest->vertexData[i].normal = simd_mul(rot, dest->vertexData[i].normal);
            }
            dest->vertexCount = src->vertexCount;
        }
    }

    combineIndexGeometryData(dest, src, destPreCombineVertexCount);
}

void copyGeometryVertexData(GeometryData *dest, GeometryData *src, int start, int count) {
    if (src->vertexCount > 0) {
        dest->vertexCount = count;
        dest->vertexData = (SatinVertex *)malloc(count * sizeof(SatinVertex));
        memcpy(dest->vertexData, src->vertexData + start, count * sizeof(SatinVertex));
    }
}

void copyGeometryIndexData(GeometryData *dest, GeometryData *src, int start, int count) {
    if (src->indexCount > 0) {
        dest->indexCount = count;
        dest->indexData = (TriangleIndices *)malloc(sizeof(TriangleIndices) * count);
        memcpy(dest->indexData, src->indexData + start, count * sizeof(TriangleIndices));
    }
}

void copyGeometryData(GeometryData *dest, GeometryData *src) {
    copyGeometryVertexData(dest, src, 0, src->vertexCount);
    copyGeometryIndexData(dest, src, 0, src->indexCount);
}

GeometryData duplicateGeometryData(GeometryData *src) {
    GeometryData dest = createGeometryData();
    copyGeometryData(&dest, src);
    return dest;
}

void computeNormalsOfGeometryData(GeometryData *data) {
    const simd_float3 zero = simd_make_float3(0.0);
    for (int i = 0; i < data->vertexCount; i++) {
        data->vertexData[i].normal = zero;
    }

    if (data->indexCount > 0) {
        int count = data->indexCount;
        for (int i = 0; i < count; i++) {
            const TriangleIndices tri = data->indexData[i];
            const uint32_t i0 = tri.i0;
            const uint32_t i1 = tri.i1;
            const uint32_t i2 = tri.i2;

            SatinVertex *v0 = &data->vertexData[i0];
            SatinVertex *v1 = &data->vertexData[i1];
            SatinVertex *v2 = &data->vertexData[i2];

            const simd_float3 p0 = simd_make_float3(v0->position);
            const simd_float3 p1 = simd_make_float3(v1->position);
            const simd_float3 p2 = simd_make_float3(v2->position);

            const simd_float3 normal = simd_cross(p1 - p0, p2 - p0);
            if (simd_length(normal) > 0) {
                v0->normal += normal;
                v1->normal += normal;
                v2->normal += normal;
            }
        }

        count = data->vertexCount;
        for (int i = 0; i < count; i++) {
            SatinVertex *v = &data->vertexData[i];
            v->normal = simd_normalize(v->normal);
        }
    } else {
        int count = data->vertexCount;
        for (int i = 0; i < count; i += 3) {
            SatinVertex *v0 = &data->vertexData[i];
            SatinVertex *v1 = &data->vertexData[i + 1];
            SatinVertex *v2 = &data->vertexData[i + 2];

            simd_float3 p0 = simd_make_float3(v0->position);
            simd_float3 p1 = simd_make_float3(v1->position);
            simd_float3 p2 = simd_make_float3(v2->position);

            simd_float3 normal = simd_normalize(simd_cross(p1 - p0, p2 - p0));

            v0->normal = normal;
            v1->normal = normal;
            v2->normal = normal;
        }
    }
}

void reverseFacesOfGeometryData(GeometryData *data) {
    int indexCount = data->indexCount;
    if (indexCount > 0) {
        for (int i = 0; i < indexCount; i++) {
            uint32_t i1 = data->indexData[i].i1;
            uint32_t i2 = data->indexData[i].i2;
            data->indexData[i].i1 = i2;
            data->indexData[i].i2 = i1;
        }
    }

    int vertexCount = data->vertexCount;
    if (vertexCount > 0) {
        for (int i = 0; i < vertexCount; i++) {
            data->vertexData[i].normal *= -1.0;
        }
    }
}

void transformVertices(SatinVertex *vertices, int vertexCount, simd_float4x4 transform) {
    simd_float4x4 rotation = simd_transpose(simd_inverse(transform));
    simd_float3x3 rot = simd_matrix(
        simd_make_float3(rotation.columns[0]),
        simd_make_float3(rotation.columns[1]),
        simd_make_float3(rotation.columns[2]));
    int count = vertexCount;
    for (int i = 0; i < count; i++) {
        vertices[i].position =
            simd_make_float3(simd_mul(transform, simd_make_float4(vertices[i].position, 1.0)));
        vertices[i].normal = simd_mul(rot, vertices[i].normal);
    }
}

void transformGeometryData(GeometryData *data, simd_float4x4 transform) {
    transformVertices(data->vertexData, data->vertexCount, transform);
}

void deindexGeometryData(GeometryData *dest, GeometryData *src) {
    int triangleCount = src->indexCount;
    int newVertexCount = triangleCount * 3;
    SatinVertex *vertices = (SatinVertex *)malloc(newVertexCount * sizeof(SatinVertex));

    int vertexIndex = 0;
    for (int i = 0; i < triangleCount; i++) {
        TriangleIndices t = src->indexData[i];
        SatinVertex v0 = src->vertexData[t.i0];
        SatinVertex v1 = src->vertexData[t.i1];
        SatinVertex v2 = src->vertexData[t.i2];

        vertices[vertexIndex].position = v0.position;
        vertices[vertexIndex].normal = v0.normal;
        vertices[vertexIndex].uv = v0.uv;

        vertexIndex += 1;

        vertices[vertexIndex].position = v1.position;
        vertices[vertexIndex].normal = v1.normal;
        vertices[vertexIndex].uv = v1.uv;

        vertexIndex += 1;

        vertices[vertexIndex].position = v2.position;
        vertices[vertexIndex].normal = v2.normal;
        vertices[vertexIndex].uv = v2.uv;

        vertexIndex += 1;
    }

    dest->indexCount = 0;
    dest->indexData = NULL;
    dest->vertexCount = vertexIndex;
    dest->vertexData = vertices;
}

void unrollGeometryData(GeometryData *dest, GeometryData *src) {
    int triangleCount = src->indexCount;
    int newVertexCount = triangleCount * 3;
    SatinVertex *vertices = (SatinVertex *)malloc(newVertexCount * sizeof(SatinVertex));

    int vertexIndex = 0;
    simd_float3 p01, p02, p0, p1, p2;
    simd_float3 normal;
    for (int i = 0; i < triangleCount; i++) {
        TriangleIndices t = src->indexData[i];

        SatinVertex v0 = src->vertexData[t.i0];
        SatinVertex v1 = src->vertexData[t.i1];
        SatinVertex v2 = src->vertexData[t.i2];

        p0 = simd_make_float3(v0.position);
        p1 = simd_make_float3(v1.position);
        p2 = simd_make_float3(v2.position);

        p01 = p1 - p0;
        p02 = p2 - p0;

        normal = simd_normalize(simd_cross(p01, p02));

        vertices[vertexIndex++] =
            (SatinVertex) { .position = v0.position, .normal = normal, .uv = v0.uv };
        vertices[vertexIndex++] =
            (SatinVertex) { .position = v1.position, .normal = normal, .uv = v1.uv };
        vertices[vertexIndex++] =
            (SatinVertex) { .position = v2.position, .normal = normal, .uv = v2.uv };
    }

    dest->indexCount = 0;
    dest->indexData = NULL;
    dest->vertexCount = vertexIndex;
    dest->vertexData = vertices;
}
