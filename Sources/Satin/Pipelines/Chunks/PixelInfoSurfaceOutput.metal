// Populates 'surface' (SurfaceOutput) from 'pixel' (PixelInfo) after pbrInit has run.
// Albedo is the gamma-corrected base color before lighting accumulation, which is correct
// for SSGI and other effects that need the pre-lit surface color.
surface.albedo    = half3(pixel.material.baseColor);
surface.normal    = half3(pixel.normal);
surface.roughness = half(pixel.material.roughness);
surface.metalness = half(pixel.material.metallic);
surface.ao        = half(pixel.material.occlusion);
surface.emissive  = half3(pixel.material.emissiveColor);
