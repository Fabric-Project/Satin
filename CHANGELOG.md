# Satin 2.0 Changelog

## Point Geometry Rendering

All core materials now support point primitive rendering. Set `geometry.primitiveType = .point` on any mesh — no material swap required.

### API

Every material gains a `pointSize: Float` property (default `1.0`):

```swift
let mesh = Mesh(context: context, geometry: myGeo, material: BasicColorMaterial(context: context))
mesh.geometry.primitiveType = .point
mesh.material.pointSize = 8.0
```

`StandardMaterial` and `PhysicalMaterial` additionally require `pointRenderingEnabled = true` to activate the Metal `[[point_size]]` output (this recompiles the shader with `HAS_POINT_SIZE` defined):

```swift
let mat = StandardMaterial(context: context)
mat.pointRenderingEnabled = true
mat.pointSize = 8.0
let mesh = Mesh(context: context, geometry: myGeo, material: mat)
mesh.geometry.primitiveType = .point
```

### Supported Materials

| Material | Opt-in required | Notes |
|---|---|---|
| `BasicColorMaterial` | No | Solid color points |
| `BasicTextureMaterial` | No | Samples texture at vertex UV |
| `DepthMaterial` | No | Depth-encoded points |
| `UVColorMaterial` | No | UV-as-color points |
| `NormalColorMaterial` | No | Normal-as-color points |
| `StandardMaterial` | `pointRenderingEnabled = true` | Full PBR — each point lit by its vertex normal |
| `PhysicalMaterial` | `pointRenderingEnabled = true` | Full advanced PBR — inherits from Standard |

> For circular/masked points with per-fragment UV control, `BasicPointMaterial` remains the dedicated option.

`[[point_size]]` is ignored by the Metal rasterizer for non-point primitives, so all existing triangle rendering is unaffected. `pointSize` serializes automatically via the `ParameterGroup` Codable path — no migration needed.
