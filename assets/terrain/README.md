# Terrain material assets

The production library lives under `assets/environment/terrain/materials`. `BiomeMaterialDefinition.defaults()` maps its canonical folders into the five continuous renderer slots: grass lush; forest leaf litter with moss, woody debris, and scattered leaves; dry sand with stony soil; layered rock with coarse and pebble gravel; and wet mud with moss and shoreline pebbles.

Each `TerrainTextureSet` accepts albedo, OpenGL tangent normal, roughness, ambient occlusion, and height maps. Missing maps become neutral albedo, flat normals, full roughness/AO, and mid-height, with one concise warning per run. Height only biases the detail blend and never displaces authoritative terrain geometry.

At build time the source library is resized to the configured runtime resolution and packed into four five-layer arrays. Ground arrays store albedo RGB plus roughness; surface arrays store normal RG, height, and AO. Secondary sets are composed once on the CPU per biome, rather than sampled as eleven independent materials in every fragment. Packed results are cached across terrain rebuilds.

Object-local triplanar coordinates preserve world-unit scale without longitude or pole seams. The shader retains world-generation biome weights, gradually adds layered rock on slopes, and uses effective moisture, terrain roughness, and wetland potential for restrained detail and wetness. Texture scale, detail strength, normal strength, tint, and roughness multiplier remain per-biome settings.

Terrain imports use mipmaps and runtime VRAM compression. `normal_gl.png` files are marked as normal maps; the shader samplers enable repeat, anisotropic mip filtering, and continuous biome blending. No unrelated asset imports are modified.

Shader API reference: [Godot shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html).
