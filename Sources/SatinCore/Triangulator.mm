//
//  Triangulator.c
//  Satin
//
//  Created by Reza Ali on 7/5/20.
//

#include <float.h>
#include <string.h>
#include <math.h>
#include <malloc/_malloc.h>
#include <simd/simd.h>
#include <iostream>
#include <simd/quaternion.h>

#include "Triangulator.h"
#include "Geometry.h"
#include "Types.h"

// #define DEBUGDIAGONAL
// #define DEBUGTRIANGULATION
// #define DEBUGCOMBINEPATHS
// #define DEBUGINITALIZEEARS
#define ALLOWFAILEDTRIAGULATIONS

/* Types */

typedef struct tsVertex {
    int index;
    simd_float2 v;
    bool ear;
    bool imaginary;
    tsVertex *next;
    tsVertex *prev;
} tsVertex;

typedef struct tsVertexPool {
    int count;
    tsVertex **data;
} tsVertexPool;

typedef struct tsPath {
    int index;
    int length;
    int added;
    bool clockwise;
    tsPath *parent;
    tsPath *next;
    tsPath *prev;
    tsVertex *v;
} tsPath;

tsVertexPool createVertexPool() { return (tsVertexPool) { .count = 0, .data = NULL }; }

void freeVertexPool(tsVertexPool *pool) {
    for (int i = 0; i < pool->count; i++) {
        free(pool->data[i]);
    }

    free(pool->data);
    pool->data = NULL;
    pool->count = 0;
}

/* Helper Functions */

bool _isDiagonalie(tsVertex *vertices, tsVertex *a, tsVertex *b) {
    tsVertex *c, *c1;
    c = vertices;
    do {
        c1 = c->next;
        if ((c != a) && (c1 != a) && (c != b) && (c1 != b)) {
            if (isBetween(a->v, b->v, c->v) && isBetween(a->v, b->v, c1->v)) { return false; }
            if (intersectsProper(a->v, b->v, c->v, c1->v)) { return false; }
        }
        c = c->next;
    } while (c != vertices);
    return true;
}

bool _inCone(tsVertex *a, tsVertex *b) {
    tsVertex *a0, *a1;
    a1 = a->next;
    a0 = a->prev;
    if (isLeftOn(a->v, a1->v, a0->v)) {
        return isLeftOn(a->v, b->v, a0->v) && isLeftOn(b->v, a->v, a1->v);
    }
    return !(isLeftOn(a->v, b->v, a1->v) && isLeftOn(b->v, a->v, a0->v));
}

bool _isDiagonal(tsVertex *vertices, tsVertex *a, tsVertex *b) {
    const bool i0 = _inCone(a, b);
    const bool i1 = _inCone(b, a);
    const bool i2 = _isDiagonalie(vertices, a, b);
#ifdef DEBUGDIAGONAL
    printf("inCone: \t\t%d\ninCone: \t\t%d\nisDiagonalie: \t%d\n", i0, i1, i2);
#endif
    return i0 && i1 && i2;
}

bool insidePath2(tsPath *path, tsVertex *vertex) {
    bool inside = false;
    tsVertex *vertices = path->v;
    tsVertex *curr = vertices;
    simd_float2 pt = vertex->v;
    do {
        simd_float2 v0 = curr->v;
        simd_float2 v1 = curr->next->v;
        if (((v0.y > pt.y) != (v1.y > pt.y)) &&
            (pt.x < ((v1.x - v0.x) * (pt.y - v0.y) / (v1.y - v0.y) + v0.x))) {
            inside = !inside;
        }
        curr = curr->next;
    } while (curr != vertices);
    //    printf("In polygon: %d, %d\n", path->index, inside);
    return inside;
}

/* Creator Functions */

tsVertex *createVertexStructureFromPath(
    simd_float2 *path, int length, int indexOffset, int localOffset, bool *clockwise) {
    tsVertex *vertices = (tsVertex *)malloc(sizeof(tsVertex) * length);

    float area = 0;

    for (int i = 0; i < length; i++) {
        const int next = (i + 1) % length;
        const int prev = (i - 1) < 0 ? (length - 1) : (i - 1);

        int i0 = i;
        int i1 = (i + 1) % length;
        const simd_float2 &a = path[i0];
        const simd_float2 &b = path[i1];
        area += (b.x - a.x) * (b.y + a.y);

        vertices[i] = (tsVertex) {
            .index = (i + indexOffset),
            .v = path[i],
            .ear = false,
            .next = &vertices[next],
            .prev = &vertices[prev],
        };
    }

    if (clockwise != NULL) { *clockwise = !signbit(area); }

    return vertices;
}

tsVertex *createVertexStructureAndGeometryDataFromPath(
    simd_float2 *path,
    int length,
    int indexOffset,
    int localOffset,
    bool *clockwise,
    GeometryData *geometryData) {
    tsVertex *vertices = (tsVertex *)malloc(sizeof(tsVertex) * length);

    float area = 0;

    const int lengthMinusOne = length - 1;
    for (int i = 0; i < length; i++) {
        const int next = (i + 1) % length;
        const int prev = (i - 1) < 0 ? lengthMinusOne : (i - 1);

        int i0 = i;
        int i1 = (i + 1) % length;
        const simd_float2 &vCurr = path[i0];
        const simd_float2 &vNext = path[i1];
        area += (vNext.x - vCurr.x) * (vNext.y + vCurr.y);

        vertices[i] = (tsVertex) {
            .index = (i + indexOffset),
            .v = vCurr,
            .ear = false,
            .next = &vertices[next],
            .prev = &vertices[prev],
        };

        geometryData->vertexData[indexOffset + i] =
            (SatinVertex) { .position = simd_make_float3(vCurr.x, vCurr.y, 0.0),
                            .normal = simd_make_float3(0.0, 0.0, 1.0),
                            .uv = simd_make_float2((float)i / (float)lengthMinusOne, 0.0) };
    }

    *clockwise = !signbit(area);

    return vertices;
}

tsPath *createPathStructureFromPath(simd_float2 **paths, int *lengths, int count, int indexOffset) {
    tsPath *result = (tsPath *)malloc(sizeof(tsPath) * count);
    int localOffset = 0;
    for (int i = 0; i < count; i++) {
        simd_float2 *path = paths[i];
        const int length = lengths[i];
        const int next = (i + 1) % count;
        const int prev = (i - 1) < 0 ? (count - 1) : (i - 1);

        bool clockwise = false;
        result[i] = (tsPath) { .index = i,
                               .length = length,
                               .added = 0,
                               .clockwise = clockwise,
                               .parent = NULL,
                               .next = &result[next],
                               .prev = &result[prev],
                               .v = createVertexStructureFromPath(
                                   path, length, indexOffset, localOffset, &clockwise) };

        result[i].clockwise = clockwise;

        indexOffset += length;
        localOffset += length;
    }
    return result;
}

tsPath *createPathStructureAndGeometryDataFromPath(
    simd_float2 **paths, int *lengths, int count, int indexOffset, GeometryData *geometryData) {
    tsPath *result = (tsPath *)malloc(sizeof(tsPath) * count);
    int localOffset = 0;
    for (int i = 0; i < count; i++) {
        simd_float2 *path = paths[i];
        const int length = lengths[i];
        const int next = (i + 1) % count;
        const int prev = (i - 1) < 0 ? (count - 1) : (i - 1);

        bool clockwise = false;
        result[i] =
            (tsPath) { .index = i,
                       .length = length,
                       .added = 0,
                       .clockwise = clockwise,
                       .parent = NULL,
                       .next = &result[next],
                       .prev = &result[prev],
                       .v = createVertexStructureAndGeometryDataFromPath(
                           path, length, indexOffset, localOffset, &clockwise, geometryData) };

        result[i].clockwise = clockwise;

        indexOffset += length;
        localOffset += length;
    }
    return result;
}

tsPath *createPathStructureFromPolylines(
    Polylines2D *polylines, GeometryData *geometryData, int indexOffset) {
    int vertexCount = 0;
    for (int i = 0; i < polylines->count; i++) {
        vertexCount += polylines->data[i].count;
    }

    geometryData->vertexCount = vertexCount;
    geometryData->vertexData =
        (SatinVertex *)malloc(sizeof(SatinVertex) * geometryData->vertexCount);

    const int count = polylines->count;

    tsPath *result = (tsPath *)malloc(sizeof(tsPath) * count);
    int localOffset = 0;

    for (int i = 0; i < count; i++) {
        const Polyline2D &polyline = polylines->data[i];

        const int next = (i + 1) % count;
        const int prev = (i - 1) < 0 ? (count - 1) : (i - 1);

        const int length = polyline.count;

        bool clockwise = false;

        result[i] = (tsPath) {
            .index = i,
            .length = length,
            .added = 0,
            .clockwise = clockwise,
            .parent = NULL,
            .next = &result[next],
            .prev = &result[prev],
            .v = createVertexStructureAndGeometryDataFromPath(
                polyline.data, length, indexOffset, localOffset, &clockwise, geometryData)
        };

        result[i].clockwise = clockwise;

        indexOffset += length;
        localOffset += length;
    }
    return result;
}

void freePathVertexStructure(tsPath *paths, int count) {
    if (paths != NULL) {
        tsPath *path = paths;
        for (int i = 0; i < count; i++) {
            if (path->v != NULL) {
                free(path->v);
                path->v = NULL;
            }
            path++;
        }

        free(paths);
        paths = NULL;
    }
}

/* Memory Appending Functions */

void appendVertexData(GeometryData *gDataDest, GeometryData *gDataSrc) {
    if (gDataSrc->vertexCount > 0) {
        if (gDataDest->vertexCount > 0) {
            int totalCount = gDataSrc->vertexCount + gDataDest->vertexCount;
            gDataDest->vertexData =
                (SatinVertex *)realloc(gDataDest->vertexData, totalCount * sizeof(SatinVertex));
            memcpy(
                gDataDest->vertexData + gDataDest->vertexCount,
                gDataSrc->vertexData,
                gDataSrc->vertexCount * sizeof(SatinVertex));
            gDataDest->vertexCount += gDataSrc->vertexCount;
        } else {
            gDataDest->vertexData =
                (SatinVertex *)malloc(gDataSrc->vertexCount * sizeof(SatinVertex));
            memcpy(
                gDataDest->vertexData,
                gDataSrc->vertexData,
                gDataSrc->vertexCount * sizeof(SatinVertex));
            gDataDest->vertexCount = gDataSrc->vertexCount;
        }
    }
}

void appendIndexData(GeometryData *gDataDest, GeometryData *gDataSrc) {
    if (gDataSrc->indexCount > 0) {
        if (gDataDest->indexCount > 0) {
            int totalCount = gDataSrc->indexCount + gDataDest->indexCount;
            gDataDest->indexData = (TriangleIndices *)realloc(
                gDataDest->indexData, totalCount * sizeof(TriangleIndices));
            memcpy(
                gDataDest->indexData + gDataDest->indexCount,
                gDataSrc->indexData,
                gDataSrc->indexCount * sizeof(TriangleIndices));
            gDataDest->indexCount += gDataSrc->indexCount;
        } else {
            gDataDest->indexData =
                (TriangleIndices *)malloc(sizeof(TriangleIndices) * gDataSrc->indexCount);
            memcpy(
                gDataDest->indexData,
                gDataSrc->indexData,
                sizeof(TriangleIndices) * gDataSrc->indexCount);
            gDataDest->indexCount = gDataSrc->indexCount;
        }
    }
}

void appendTriangleData(TriangleData *tDataDest, TriangleData *tDataSrc) {
    if (tDataSrc->count > 0) {
        if (tDataDest->count > 0) {
            int totalCount = tDataSrc->count + tDataDest->count;
            tDataDest->indices = (TriangleIndices *)realloc(
                tDataDest->indices, totalCount * sizeof(TriangleIndices));
            memcpy(
                tDataDest->indices + tDataDest->count,
                tDataSrc->indices,
                tDataSrc->count * sizeof(TriangleIndices));
            tDataDest->count += tDataSrc->count;
        } else {
            tDataDest->indices =
                (TriangleIndices *)malloc(sizeof(TriangleIndices) * tDataSrc->count);
            memcpy(
                tDataDest->indices, tDataSrc->indices, sizeof(TriangleIndices) * tDataSrc->count);
            tDataDest->count = tDataSrc->count;
        }
    }
}

void appendGeometryData(GeometryData *gDataDest, GeometryData *gDataSrc) {
    appendVertexData(gDataDest, gDataSrc);
    appendIndexData(gDataDest, gDataSrc);
}

/* Initializer Functions */

int initalizeEars(tsVertex *vertices) {
    tsVertex *v0, *v1, *v2;
    v1 = vertices;
    int ears = 0;
    do {
        v0 = v1->prev;
        v2 = v1->next;
        v1->ear = _isDiagonal(vertices, v0, v2);
        ears += (v1->ear == true) ? 1 : 0;
#ifdef DEBUGINITALIZEEARS
        printf("\n\nEar Test: %d, %d, %d\n", v0->index, v1->index, v2->index);
        printf("Ear Index: %d\n", v1->index);
        printf("is Ear: %d\n\n\n", v1->ear);
#endif
        v1 = v1->next;
    } while (v1 != vertices);
    return ears;
}

/* Triangulation Functions */

void reversePath(tsPath *path) {
    tsVertex *head = path->v;
    tsVertex *curr = head;
    do {
        tsVertex *prev = curr->prev;
        tsVertex *next = curr->next;
        curr->next = prev;
        curr->prev = next;
        curr = curr->next;
    } while (curr != head);
    path->clockwise = !path->clockwise;
}

bool combineOuterAndInnerPaths(tsPath *outerPath, tsPath *innerPath, tsVertexPool *pool) {
    tsVertex *oData = outerPath->v;
    tsVertex *iData = innerPath->v;

    // find the right most inner vertex (if tie take lowest the vertex in the y direction)
    tsVertex *rightInner = iData;
    tsVertex *inner = iData;
    do {
        if (inner->v.x > rightInner->v.x) {
            rightInner = inner;
        } else if (isEqual(rightInner->v.x, inner->v.x) && inner->v.y < rightInner->v.y) {
            rightInner = inner;
        }
        inner = inner->next;
    } while (inner != iData);

    tsVertex *rightOuter = NULL;
    tsVertex *rightOuterNext = NULL;
    tsVertex *outer = oData;

#ifdef DEBUGCOMBINEPATHS
    printf("Right Inner Index: %d\n", rightInner->index);
#endif

    float intersectionDistance = FLT_MAX;
    simd_float2 rightInnerPosExt = rightInner->v + simd_make_float2(FLT_MAX - rightInner->v.x, 0.0);
    int intersectionCount = 0;
    do {
        if (!isColinear2(rightInner->v, outer->v, outer->next->v) &&
            intersectsProperOrInBetween(
                rightInner->v, rightInnerPosExt, outer->v, outer->next->v)) {
            intersectionCount++;

            if (isColinear2(rightInner->v, rightInnerPosExt, outer->v)) {
                if (rightOuter != NULL && rightOuterNext->index == outer->index) {
#ifdef DEBUGCOMBINEPATHS
                    printf("we have overlapping intersections at: %d\n", outer->index);
#endif
                    intersectionCount++;
                } else if (!isColinear2(rightInner->v, outer->v, outer->next->v)) {
#ifdef DEBUGCOMBINEPATHS
                    printf("intersection is colinear at outer: %d\n", outer->index);
#endif
                    intersectionCount++;
                }
            }

            float dist = pointLineDistance2(outer->v, outer->next->v, rightInner->v);
#ifdef DEBUGCOMBINEPATHS
            printf(
                "intersection index: %d, next: %d time: %f\n",
                outer->index,
                outer->next->index,
                dist);
#endif
            if (dist <= intersectionDistance) {
#ifdef DEBUGCOMBINEPATHS
                printf(
                    "setting right outer: %d & right outer next: %d\n",
                    outer->index,
                    outer->next->index);
#endif
                intersectionDistance = dist;
                rightOuter = outer;
                rightOuterNext = outer->next;
            }
        }
        outer = outer->next;
    } while (outer != oData);

#ifdef DEBUGCOMBINEPATHS
    printf(
        "\nIntersections: %d at: %d\n\n",
        intersectionCount,
        rightOuter == NULL ? -1 : rightOuter->index);
#endif

    if (intersectionCount % 2 == 0) { rightOuter = NULL; }

#ifdef DEBUGCOMBINEPATHS
    printf(
        "Right most inner index: %d %f %f\n", rightInner->index, rightInner->v.x, rightInner->v.y);
#endif

    // connect paths if valid
    if (rightOuter != NULL) {
#ifdef DEBUGCOMBINEPATHS
        printf("\nCombining paths at outer: %d, inner: %d\n", rightOuter->index, rightInner->index);
#endif

        // add new vertices to pool
        const int _poolLength = pool->count;

        if (pool->count > 0) {
            pool->data = (tsVertex **)realloc(pool->data, sizeof(tsVertex *) * (_poolLength + 2));
            pool->data[_poolLength] = (tsVertex *)malloc(sizeof(tsVertex));
            pool->data[_poolLength + 1] = (tsVertex *)malloc(sizeof(tsVertex));
        } else {
            pool->data = (tsVertex **)malloc(sizeof(tsVertex *) * (_poolLength + 2));
            pool->data[0] = (tsVertex *)malloc(sizeof(tsVertex));
            pool->data[1] = (tsVertex *)malloc(sizeof(tsVertex));
        }

        pool->count = _poolLength + 2;

        tsVertex *rightOuterNew = pool->data[_poolLength];
        rightOuterNew->index = rightOuter->index;
        rightOuterNew->v = rightOuter->v;
        rightOuterNew->ear = rightOuter->ear;
        rightOuterNew->imaginary = true;

        tsVertex *rightInnerNew = pool->data[_poolLength + 1];
        rightInnerNew->index = rightInner->index;
        rightInnerNew->v = rightInner->v;
        rightInnerNew->ear = rightInner->ear;
        rightInnerNew->imaginary = true;

        tsVertex *rightOuterNext = rightOuter->next;
        tsVertex *rightInnerNext = rightInner->next;

        // 0
        rightOuter->next = rightInnerNew;
        rightInnerNew->prev = rightOuter;

        // 1
        rightInnerNew->next = rightInnerNext;
        rightInnerNext->prev = rightInnerNew;

        // 2
        rightInner->next = rightOuterNew;
        rightOuterNew->prev = rightInner;

        // 3
        rightOuterNew->next = rightOuterNext;
        rightOuterNext->prev = rightOuterNew;

        // Set path length (+2 because of virtual vertices add)
        outerPath->length += innerPath->length;
        outerPath->added += 2;

        innerPath->parent = outerPath;
        return true;
    }

    return false;
}

// Added represents the number of addition verticies added to connect an outer path to an inner path
int _triangulate(tsVertex *vertices, int count, int added, TriangleData *data) {
    if (initalizeEars(vertices) == 0) {
        printf("Invalid Polygon: Doesn't have any ears.\n");
        return 1;
    }

#ifdef DEBUGTRIANGULATION
    printf("\n");
    tsVertex *head = vertices;
    do {
        printf("%d ", head->index);
        head = head->next;
    } while (head != vertices);
    printf("\n");
#endif

    const int totalCount = count + added;
    int triangleIndex = 0;
    data->count = totalCount - 2;
    data->indices = (TriangleIndices *)malloc(sizeof(TriangleIndices) * data->count);

    tsVertex *v1, *v2 = vertices, *v3;
    int n = totalCount;
//    int n = count;
#ifdef ALLOWFAILEDTRIAGULATIONS
    int indexCache = 0;
    int nCache = 0;
    int lastN = -1;
    int lastIndex = -1;
#endif

    while (n > 3) {
        v2 = vertices;
#ifdef ALLOWFAILEDTRIAGULATIONS
        // these can be removed when the triangulator is rock solid, otherwise if triangulation
        // fails, your program will crash completely
        if (n != lastN) {
            lastN = n;
            nCache = 0;
        } else {
            nCache++;
        }

        if (v2->index != lastIndex) {
            lastIndex = v2->index;
            indexCache = 0;
        } else {
            indexCache++;
        }

        if (nCache > 1 && indexCache > 1) {
#ifdef DEBUGTRIANGULATION
            printf("\n\nBreaking at n: %d index: %d, indexCache: %d\n\n", n, v2->index, indexCache);
            tsVertex *head = v2;
            do {
                printf("%d ", head->index);
                head = head->next;
            } while (head != vertices);
            printf("\n");
#endif
            data->count = triangleIndex - indexCache;
            data->indices =
                (TriangleIndices *)realloc(data->indices, (sizeof(TriangleIndices) * data->count));
            return indexCache;
        }
#endif

        do {
            if (v2->ear) {
                v3 = v2->next;
                //                v4 = v3->next;
                v1 = v2->prev;
                //                v0 = v1->prev;

#ifdef DEBUGTRIANGULATION
                printf("\nLeft: %d\n", n - 1);
                printf(
                    "v0: %d, v1: %d, v2: %d, v3: %d, v4: %d\n",
                    v0->index,
                    v1->index,
                    v2->index,
                    v3->index,
                    v4->index);
                printf("Ear @ Index: %d\n", triangleIndex);
                printf("Adding Triangle: %d, %d, %d\n", v1->index, v2->index, v3->index);
#endif
                const uint32_t i1 = v1->index;
                const uint32_t i2 = v2->index;
                const uint32_t i3 = v3->index;

                // add triangle
                data->indices[triangleIndex] = (TriangleIndices) { .i0 = uint32_t(i1),
                                                                   .i1 = uint32_t(i2),
                                                                   .i2 = uint32_t(i3) };

                triangleIndex++;

                v1->next = v3;
                v3->prev = v1;

                vertices = v3;

                v1->ear = _isDiagonal(vertices, v1->prev, v1->next);
                v3->ear = _isDiagonal(vertices, v3->prev, v3->next);

#ifdef DEBUGTRIANGULATION
                printf(
                    "v0: %d, v1: %d, v2: %d, v3: %d, v4: %d\n",
                    v0->index,
                    v1->index,
                    v2->index,
                    v3->index,
                    v4->index);
                printf(
                    "v1->prev: %d, v1: %d, v1->next: %d, ear: %d\n",
                    v1->prev->index,
                    v1->index,
                    v1->next->index,
                    v1->ear);
                printf(
                    "v3->prev: %d, v3: %d, v3->next: %d, ear: %d\n",
                    v3->prev->index,
                    v3->index,
                    v3->next->index,
                    v3->ear);
                printf("\n");

                tsVertex *start = v1;
                tsVertex *head = v1;
                do {
                    printf("%d ", head->index);
                    head = head->next;
                } while (head != start);
                printf("\n");
#endif
                n--;
                break;
            }

            v2 = v2->next;
        } while (v2 != vertices);
    }

    v2 = v2->next;
    v3 = v2->next;
    v1 = v2->prev;

#ifdef DEBUGTRIANGULATION
    printf("Adding last triangle: %d, %d, %d\n", v1->index, v2->index, v3->index);
#endif

    data->indices[triangleIndex] = (TriangleIndices) { .i0 = uint32_t(v1->index),
                                                       .i1 = uint32_t(v2->index),
                                                       .i2 = uint32_t(v3->index) };

    return 0;
}

bool isVertexStructureClockwise(tsVertex *vertices, int length) {
    float area = 0;
    for (int i = 0; i < length; i++) {
        const int i0 = i;
        const int i1 = (i + 1) % length;
        const simd_float2 &a = vertices[i0].v;
        const simd_float2 &b = vertices[i1].v;
        area += (b.x - a.x) * (b.y + a.y);
    }
    return !signbit(area);
}

void reverseStructure(tsVertex *structure) {
    tsVertex *head = structure;
    tsVertex *curr = structure;

    do {
        tsVertex *prev = curr->prev;
        tsVertex *next = curr->next;
        curr->next = prev;
        curr->prev = next;
        curr = next;
    } while (curr != head);
}

tsVertex *createVertexStructure(SatinVertex *vertices, const uint32_t *face, int length) {
    //    printf("face length: %d\n", length);
    //    printf("CREATING VERTEX STRUCTURE!\n\n");
    //
    //    printf("face indicies: ");
    //    for (int i = 0; i < length; i++) {
    //        printf("%d ", face[i]);
    //    }
    //    printf("\n");

    // Calculate normal
    simd_float3 n = simd_make_float3(0.0, 0.0, 0.0);

    for (int i = 0; i < length; i++) {
        int i0 = i;
        int i1 = (i + 1) % length;
        int i2 = (i + 2) % length;

        uint32_t index0 = face[i0];
        uint32_t index1 = face[i1];
        uint32_t index2 = face[i2];

        SatinVertex *v0 = &vertices[index0];
        SatinVertex *v1 = &vertices[index1];
        SatinVertex *v2 = &vertices[index2];

        simd_float3 p0 = simd_make_float3(v0->position);
        simd_float3 p1 = simd_make_float3(v1->position);
        simd_float3 p2 = simd_make_float3(v2->position);

        if (isColinear3(p0, p1, p2)) {
            //            printf("colinear, trying another set of verts\n");
            continue;
        } else {
            simd_float3 a = p2 - p1;
            simd_float3 b = p0 - p1;
            n = simd_normalize(simd_cross(a, b));
            break;
        }
    }

    //    printf("faces: %d, %d, %d\n\n", i0, i1, i2);
    //    printf("normal: %f, %f, %f\n", n.x, n.y, n.z);
    const simd_quatf &q = simd_quaternion(n, simd_make_float3(0.0, 0.0, 1.0));

    tsVertex *structure = (tsVertex *)malloc(length * sizeof(tsVertex));
    for (int i = 0; i < length; i++) {

        const int index = face[i];
        const simd_float3 &p = simd_act(q, simd_make_float3(vertices[index].position));

        const int next = (i + 1) % length;
        const int prev = (i - 1) < 0 ? (length - 1) : (i - 1);

        structure[i] = (tsVertex) { .index = index,
                                    .v = simd_make_float2(p),
                                    .ear = false,
                                    .imaginary = false,
                                    .next = &structure[next],
                                    .prev = &structure[prev] };
    }

    return structure;
}

tsPath *createPathStructure(SatinVertex *vertices, const uint32_t *face, int length) {
    tsPath *result = (tsPath *)malloc(sizeof(tsPath));
    result->index = 0;
    result->length = length;
    result->added = 0;
    result->clockwise = false;
    result->parent = NULL;
    result->next = NULL;
    result->prev = NULL;
    result->v = createVertexStructure(vertices, face, length);
    result->clockwise = isVertexStructureClockwise(result->v, length);
    if (result->clockwise) { reverseStructure(result->v); }
    return result;
}

int _triangulate(tsPath *pData, int count, TriangleData *tData) {
    tsVertexPool pool = createVertexPool();

    if (count > 1) {
        for (int i = 0; i < count; i++) {
            tsPath *a = pData + i;
            for (int j = i + 1; j < count; j++) {
                tsPath *b = pData + j;
                if (insidePath2(a, b->v)) {
                    // B is inside of A
                    // if B is already inside of another path, then its enclosed in a bigger path,
                    // so unlink the path from the parent
                    if (b->parent != NULL) {
                        b->parent = NULL;
                    } else {
                        b->parent = a;
                    }
                } else if (insidePath2(b, a->v)) {
                    // A is inside of B
                    // if A is already inside of another path, then its enclosed in a bigger path,
                    // so unlink the path from the parent
                    if (a->parent != NULL) {
                        a->parent = NULL;
                    } else {
                        a->parent = b;
                    }
                }
            }
        }

        for (int i = 0; i < count; i++) {
            tsPath *inner = pData + i;
            tsPath *parent = inner->parent;
            if (parent != NULL) {
                if (!inner->clockwise) { reversePath(inner); }
                if (parent->clockwise) { reversePath(parent); }
                combineOuterAndInnerPaths(parent, inner, &pool);
            }
        }
    }

    int success = 0;

    for (int i = 0; i < count; i++) {
        tsPath *path = pData + i;

        if (path->parent == NULL) {
            if (path->clockwise) { reversePath(path); }

#ifdef DEBUGTRIANGULATION
            printf("Triangulating path: %d, clockwise: %d\n", path->index, path->clockwise);
#endif

            TriangleData triData = createTriangleData();
            success += _triangulate(path->v, path->length, path->added, &triData);
            appendTriangleData(tData, &triData);
            freeTriangleData(&triData);

#ifdef DEBUGTRIANGULATION
            printf("Triangulated path: %d, clockwise: %d\n", path->index, path->clockwise);
            printf("Result: %d\n", success);
#endif
        }
    }

    freeVertexPool(&pool);

    freePathVertexStructure(pData, count);

    return success;
}

int triangulatePolylines(
    Polylines2D *polylines, GeometryData *geometryData, TriangleData *triangleData) {
    tsPath *pData = createPathStructureFromPolylines(polylines, geometryData, 0);
    return _triangulate(pData, polylines->count, triangleData);
}

int triangulate(simd_float2 **paths, int *lengths, int count, TriangleData *gData) {
    tsPath *pData = createPathStructureFromPath(paths, lengths, count, 0);
    return _triangulate(pData, count, gData);
}

// triangulates counter clockwise path
int triangulatePath(simd_float2 *points, int length, TriangleData *triData) {
    tsVertex vertices[length];

    for (int i = 0; i < length; i++) {
        const int next = (i + 1) % length;
        const int prev = (i - 1) < 0 ? (length - 1) : (i - 1);

        vertices[i] = (tsVertex) {
            .index = i,
            .v = points[i],
            .ear = false,
            .next = &vertices[next],
            .prev = &vertices[prev],
        };
    }

    return _triangulate(vertices, length, 0, triData);
}

int extrudePaths(simd_float2 **paths, int *lengths, int count, GeometryData *gData) {
    int success = 0;
    tsPath *pData = createPathStructureFromPath(paths, lengths, count, gData->vertexCount);

    if (count == 1) {
        if (pData->clockwise) { reversePath(pData); }
    } else {
        for (int i = 0; i < count; i++) {
            tsPath *a = pData + i;
            for (int j = i + 1; j < count; j++) {
                tsPath *b = pData + j;
                if (insidePath2(a, b->v)) {
                    // B is inside of A
                    // if B is already inside of another path, then its enclosed in a bigger path,
                    // so unlink the path from the parent
                    if (b->parent != NULL) {
                        b->parent = NULL;
                    } else {
                        b->parent = a;
                    }
                } else if (insidePath2(b, a->v)) {
                    // A is inside of B
                    // if A is already inside of another path, then its enclosed in a bigger path,
                    // so unlink the path from the parent
                    if (a->parent != NULL) {
                        a->parent = NULL;
                    } else {
                        a->parent = b;
                    }
                }
            }
        }
    }

    for (int i = 0; i < count; i++) {
        tsPath *path = pData + i;
        if (path->parent == NULL) {
            if (path->clockwise) { reversePath(path); }
        } else {
            if (!path->clockwise) { reversePath(path); }
        }

        int length = path->length;
        int vertexCount = length * 2;
        int indexCount = length * 2;
        GeometryData extrudeData =
            (GeometryData) { .vertexCount = vertexCount,
                             .vertexData = (SatinVertex *)malloc(vertexCount * sizeof(SatinVertex)),
                             .indexCount = indexCount,
                             .indexData =
                                 (TriangleIndices *)malloc(indexCount * sizeof(TriangleIndices)) };

        float L = 0.0f;
        tsVertex *v = path->v;
        for (int j = 0; j < length; ++j) {
            simd_float2 a = v->v;
            simd_float2 b = v->next->v;            // wraps on the last iter
            float dx = b.x - a.x;
            float dy = b.y - a.y;
            L += sqrtf(dx * dx + dy * dy);
            v = v->next;
        }
        if (L <= FLT_EPSILON) L = 1.0f;            // avoid divide-by-zero
        tsVertex *curr = path->v;
        float s = 0.0f;                             // running arc length from seam

        
//        float lengthMinusOne = (float)(length - 1);
        
        for (int j = 0; j < length; j++) {
            const simd_float2 pt = curr->v;
//            const float uv = (float)j / lengthMinusOne;
            const float u = s / L;
            // front vertex
            extrudeData.vertexData[j] =
                (SatinVertex) { .position = simd_make_float3(pt.x, pt.y, 1.0),
                                .normal = simd_make_float3(0.0, 0.0, 0.0),
                                .uv = simd_make_float2(u, 0.0) };

            // rear vertex
            extrudeData.vertexData[j + length] =
                (SatinVertex) { .position = simd_make_float3(pt.x, pt.y, -1.0),
                                .normal = simd_make_float3(0.0, 0.0, 0.0),
                                .uv = simd_make_float2(u, 1.0) };

            const uint32_t i0 = j;
            const uint32_t i1 = i0 + length;
            const uint32_t i3 = (i0 + 1) % length;
            const uint32_t i2 = i3 + length;

            const int j0 = j * 2;
            const int j1 = j0 + 1;

            extrudeData.indexData[j0] = (TriangleIndices) { .i0 = i0, .i1 = i1, .i2 = i2 };
            extrudeData.indexData[j1] = (TriangleIndices) { .i0 = i0, .i1 = i2, .i2 = i3 };

            const simd_float2 nxt = curr->next->v;
            const float dx = nxt.x - pt.x;
            const float dy = nxt.y - pt.y;
            s += sqrtf(dx * dx + dy * dy);
            
            curr = curr->next;
        }

        combineGeometryData(gData, &extrudeData);
        freeGeometryData(&extrudeData);
    }

    freePathVertexStructure(pData, count);

    return success;
}
