# Satin 2.0 Changelog

## Point Geometry Rendering

All core materials now support point primitive rendering. Set `geometry.primitiveType = .point` on any mesh — no material swap required.

### API

Every material gains a `pointSize: Float` property (default `1.0`):

```swift
let mesh = Mesh(context: context, geometry: myGeo, material: StandardMaterial(context: context))
mesh.geometry.primitiveType = .point
mesh.material.pointSize = 8.0
```

### Supported Materials

| Material | Notes |
|---|---|
| `BasicColorMaterial` | Solid color points |
| `BasicTextureMaterial` | Samples texture at vertex UV; inherits `pointSize` |
| `DepthMaterial` | Depth-encoded points |
| `UVColorMaterial` | UV-as-color points |
| `NormalColorMaterial` | Normal-as-color points |
| `StandardMaterial` | Full PBR — each point lit by its vertex normal |
| `PhysicalMaterial` | Full advanced PBR — inherits from Standard |

> For circular/masked points with per-fragment UV control, `BasicPointMaterial` remains the dedicated option.

`[[point_size]]` is ignored by the Metal rasterizer for non-point primitives, so all existing triangle rendering is unaffected. `pointSize` serializes automatically via the `ParameterGroup` Codable path — no migration needed.
