//
//  Types.h
//  Satin
//
//  Created by Reza Ali on 6/4/20.
//

#ifndef Types_h
#define Types_h

#import <stdbool.h>
#import <simd/simd.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct SatinVertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 uv;
} SatinVertex;

typedef struct Bounds {
    simd_float3 min;
    simd_float3 max;
} Bounds;

typedef struct Rectangle {
    simd_float2 min;
    simd_float2 max;
} Rectangle;

typedef struct Ray {
    simd_float3 origin;
    simd_float3 direction;
} Ray;

typedef struct Polyline2D {
    int count;
    int capacity;
    simd_float2 *data;
} Polyline2D;

typedef struct Polylines2D {
    int count;
    Polyline2D *data;
} Polylines2D;

typedef struct Polyline3D {
    int count;
    int capacity;
    simd_float3 *data;
} Polyline3D;

typedef struct Polylines3D {
    int count;
    Polyline3D *data;
} Polylines3D;

typedef struct Points2D {
    int count;
    simd_float2 *data;
} Points2D;

typedef struct TriangleIndices {
    uint32_t i0;
    uint32_t i1;
    uint32_t i2;
} TriangleIndices;

typedef struct TriangleFaceMap {
    int count;
    uint32_t *data;
} TriangleFaceMap;

typedef struct TriangleData {
    int count;
    TriangleIndices *indices;
} TriangleData;

typedef struct GeometryData {
    int vertexCount;
    SatinVertex *vertexData;
    int indexCount;
    TriangleIndices *indexData;
} GeometryData;

typedef struct BVHNode {
    Bounds aabb;
    uint32_t leftFirst;
    uint32_t triCount;
} BVHNode;

typedef struct BVH {
    BVHNode *nodes;
    simd_float3 *centroids;
    simd_float3 *positions;
    TriangleIndices *triangles;
    uint32_t *triIDs;
    uint32_t nodesUsed;
    bool useSAH;
} BVH;

typedef struct VertexUniforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 modelViewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 viewProjectionMatrix;
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 inverseModelViewProjectionMatrix;
    simd_float4x4 inverseViewMatrix;
    simd_float3x3 normalMatrix;
    simd_float4 viewport;
    simd_float3 worldCameraPosition;
    simd_float3 worldCameraViewDirection;
} VertexUniforms;

Points2D createPoints2D(void);
void freePoints2D(Points2D *points);

TriangleFaceMap createTriangleFaceMap(void);
void freeTriangleFaceMap(TriangleFaceMap *map);
void appendFaceMapData(TriangleFaceMap *map, int index, int count);

TriangleData createTriangleData(void);
void freeTriangleData(TriangleData *data);

GeometryData createGeometryData(void);
void freeGeometryData(GeometryData *data);

void copyVertexDataToGeometryData(SatinVertex *vertices, int count, GeometryData *destData);
void copyTriangleDataToGeometryData(TriangleData *triData, GeometryData *destData);

void createGeometryDataFromPaths(simd_float2 **paths, int *lengths, int count, GeometryData *tData, simd_float4 pathBounds);
void createGeometryDataFromPolylines(Polylines2D *polylines, GeometryData *tData);

void copyGeometryVertexData(GeometryData *dest, GeometryData *src, int start, int end);
void copyGeometryIndexData(GeometryData *dest, GeometryData *src, int start, int end);
void copyGeometryData(GeometryData *dest, GeometryData *src);
GeometryData duplicateGeometryData(GeometryData *src);

void addTrianglesToGeometryData(GeometryData *dest, TriangleIndices *triangles, int triangleCount);

void combineTriangleFaceMap(TriangleFaceMap *dest, const TriangleFaceMap *src);
void combineTriangleData(TriangleData *dest, const TriangleData *src, int offset);

void combineGeometryData(GeometryData *dest, GeometryData *src);
void combineAndOffsetGeometryData(GeometryData *dest, GeometryData *src, simd_float3 offset);
void combineAndScaleGeometryData(GeometryData *dest, GeometryData *src, simd_float3 scale);
void combineAndScaleAndOffsetGeometryData(
    GeometryData *dest, GeometryData *src, simd_float3 scale, simd_float3 offset);
void combineAndTransformGeometryData(
    GeometryData *dest, GeometryData *src, simd_float4x4 transform);

void computeNormalsOfGeometryData(GeometryData *data);
void reverseFacesOfGeometryData(GeometryData *data);

void transformVertices(SatinVertex *vertices, int vertexCount, simd_float4x4 transform);
void transformGeometryData(GeometryData *data, simd_float4x4 transform);

void deindexGeometryData(GeometryData *dest, GeometryData *src);
void unrollGeometryData(GeometryData *dest, GeometryData *src);

void combineGeometryDataAndTriangleFaceMap(
    GeometryData *destGeo, GeometryData *srcGeo, TriangleFaceMap *destMap, TriangleFaceMap *srcMap);

#if defined(__cplusplus)
}
#endif

#endif /* Types_h */
