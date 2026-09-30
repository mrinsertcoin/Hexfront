# Stylized terrain material

Normal gameplay uses one lightweight palette shader: `terrain.gdshader`. It blends the existing continuous Grassland, Forest, Dryland, Rocky, and Wetland weights, then applies restrained object-space macro variation, real-surface slope rock tint, and moisture/wetland darkening.

The shader does not load terrain textures, build texture arrays, or pack AO, height, roughness, and normal maps. The removed scanned library under `assets/environment/terrain/materials` is no longer part of the project. Terrain displacement, normals, hydrology, water geometry, picking, and procedural-world fields remain authoritative and unchanged.

`TerrainRenderConfig.biome_colors` owns the five-color palette. Medium and High still select visual mesh subdivision 4 and 5 respectively; they no longer allocate different terrain texture resolutions.
