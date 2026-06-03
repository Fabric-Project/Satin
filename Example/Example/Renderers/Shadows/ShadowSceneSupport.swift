//
//  ShadowSceneSupport.swift
//  Example
//
//  Created by OpenAI Codex on 6/2/26.
//

import Satin

final class StandardShadowSceneContent {
    let cycloramaMesh: Mesh
    let baseMesh: Mesh
    let torusMesh: Mesh
    let centerSphereMesh: Mesh
    let boxMesh: Mesh
    let coneMesh: Mesh
    let cylinderMesh: Mesh
    let sideSphereMesh: Mesh

    init(context: Context) {
        cycloramaMesh = Mesh(
            context: context,
            geometry: CycloramaGeometry(
                context: context,
                width: 10.0,
                length: 10.0,
                depth: 6.0,
                radius: 4.0,
                widthResolution: 6,
                lengthResolution: 6,
                depthResolution: 5,
                angularResolution: 32
            ),
            material: StandardMaterial(
                context: context,
                baseColor: [0.78, 0.8, 0.84, 1.0],
                metallic: 0.0,
                roughness: 0.98
            )
        )

        baseMesh = Mesh(
            context: context,
            geometry: BoxGeometry(context: context, width: 1.25, height: 0.125, depth: 1.25, resolution: 5),
            material: StandardMaterial(context: context, baseColor: [1.0, 1.0, 1.0, 1.0], metallic: 0.75, roughness: 0.25)
        )

        torusMesh = Mesh(
            context: context,
            geometry: TorusGeometry(context: context, minorRadius: 0.1, majorRadius: 0.5),
            material: StandardMaterial(context: context, baseColor: [1.0, 1.0, 1.0, 1.0], metallic: 1.0, roughness: 0.25, specular: 1.0)
        )

        centerSphereMesh = Mesh(
            context: context,
            geometry: IcoSphereGeometry(context: context, radius: 0.25, resolution: 3),
            material: StandardMaterial(context: context, baseColor: .one, metallic: 0.8, roughness: 0.5, specular: 1.0)
        )

        boxMesh = Mesh(
            context: context,
            geometry: BoxGeometry(context: context, width: 1.1, height: 1.6, depth: 1.1, resolution: 3),
            material: StandardMaterial(context: context, baseColor: .one , metallic: 0.92, roughness: 0.2, specular: 1.0)
        )

        coneMesh = Mesh(
            context: context,
            geometry: ConeGeometry(context: context, radius: 0.6, height: 1.7, angularResolution: 72, radialResolution: 1, verticalResolution: 8),
            material: StandardMaterial(context: context, baseColor:.one, metallic: 0.04, roughness: 0.62, specular: 0.28)
        )

        cylinderMesh = Mesh(
            context: context,
            geometry: CylinderGeometry(context: context, radius: 0.38, height: 1.45, angularResolution: 72, radialResolution: 1, verticalResolution: 5),
            material: StandardMaterial(context: context, baseColor: .one, metallic: 0.58, roughness: 0.36, specular: 0.9)
        )

        sideSphereMesh = Mesh(
            context: context,
            geometry: IcoSphereGeometry(context: context, radius: 0.55, resolution: 4),
            material: StandardMaterial(context: context, baseColor: .one, metallic: 0.42, roughness: 0.02, specular: 0.58)
        )
    }

    var objects: [Mesh] {
        [cycloramaMesh, baseMesh, torusMesh, centerSphereMesh, boxMesh, coneMesh, cylinderMesh, sideSphereMesh]
    }

    var sceneTarget: simd_float3 { [0.0, 0.0, 0.0] }

    func setup() {
        cycloramaMesh.label = "Cyclorama"
        cycloramaMesh.position = [0.0, -1.0, -6.0]
        cycloramaMesh.receiveShadow = true
        cycloramaMesh.cullMode = .none

        baseMesh.label = "Base"
        baseMesh.position.y = -1.0 + baseMesh.bounds.size.y / 2.0
        baseMesh.castShadow = true
        baseMesh.receiveShadow = true

        torusMesh.label = "Main Torus"
        torusMesh.position = [0.0, 0.05, 0.0]
        torusMesh.castShadow = true
        torusMesh.receiveShadow = true

        centerSphereMesh.label = "Center Sphere"
        centerSphereMesh.position = [0.0, 0.05, 0.0]
        centerSphereMesh.castShadow = true
        centerSphereMesh.receiveShadow = true

        boxMesh.label = "Box"
        boxMesh.position = [-2.35, -0.2, -1.45]
        boxMesh.castShadow = true
        boxMesh.receiveShadow = true

        coneMesh.label = "Cone"
        coneMesh.position = [1.95, -0.15, -2.0]
        coneMesh.castShadow = true
        coneMesh.receiveShadow = true

        cylinderMesh.label = "Cylinder"
        cylinderMesh.position = [-2.65, -0.275, 1.75]
        cylinderMesh.castShadow = true
        cylinderMesh.receiveShadow = true

        sideSphereMesh.label = "Outer Sphere"
        sideSphereMesh.position = [2.2, -0.45, 1.45]
        sideSphereMesh.castShadow = true
        sideSphereMesh.receiveShadow = true
    }

    func update(time: Float) {
        torusMesh.orientation = simd_quatf(angle: time, axis: Satin.worldUpDirection)
        torusMesh.orientation *= simd_quatf(angle: time, axis: Satin.worldRightDirection)

        boxMesh.orientation = simd_quatf(angle: time * 0.2, axis: Satin.worldUpDirection)
        coneMesh.orientation = simd_quatf(angle: -time * 0.45, axis: Satin.worldUpDirection)
        cylinderMesh.orientation = simd_quatf(angle: time * 0.28, axis: Satin.worldUpDirection)
//        sideSphereMesh.position.y = -0.45 + sin(time * 1.2) * 0.18
    }
}
