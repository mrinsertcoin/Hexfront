# Terrain material assets

The five material slots are `Grassland`, `Forest`, `Dryland`, `Rocky`, and `Wetland`. Put authored seamless maps in the corresponding lowercase folders and assign them to `BiomeMaterialDefinition` resources in the board's `terrain_config.materials` array. Paths are resource data; the shader has no texture paths.

Each definition accepts albedo, tangent-space normal, and roughness textures, tint, texture world scale (world units per repeat), normal strength, and roughness multiplier. Use OpenGL-style normal maps; invert a DirectX normal map's green channel before assigning it. Missing maps use deterministic neutral/grain albedo, flat normals, and the configured roughness. One concise fallback warning is printed per application run.

Import albedo as color and normal/roughness as linear data. Enable mipmaps, use lossless or suitable VRAM compression, and mark imported normal maps as normal maps. Repeat and trilinear filtering are enabled on the terrain shader samplers. No unrelated asset imports are changed.

At build time, input images are resized to `texture_resolution` (128 by default); roughness is packed in albedo alpha. Five layers populate a `Texture2DArray` for albedo/roughness and one for normals. This removes separate roughness samples. Object-local triplanar coordinates remain in world-unit scale, without global sphere UVs. Normal perturbations are projected into each mapping plane and then the surface tangent plane, so neutral normals preserve the displaced smooth normal without UV tangents.

The supplied look uses replaceable procedural placeholder textures, not final scanned PBR art. There are no per-cell textures or biome-transition texture permutations. `normal_maps_enabled=false` disables the 15 normal samples per fragment; full mode uses 15 albedo/roughness plus 15 normal samples. Both modes share the same biome weights and geometry.

Shader API reference: [Godot shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html).
