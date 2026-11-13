# Patch 0.4.5a10 - File normals + Gouraud shading

**Iteration:** 0.4.5

## Root cause

Two issues:

1. Adaptive SS=4 on 1.5M tris: 16 subpixels averaged per output pixel
   washed out micro-detail -> flat grey surfaces. Only flat plates stayed bright.

2. Normals computed from cross(v1-v0, v2-v0) fail for STL with inconsistent winding.
   Assimp's mesh.Normals holds the file's per-vertex normals, which are correct
   even when winding is broken.

## Fixes

1. MeshGeometry gets VertexNormals; AssimpMeshLoader populates from mesh.Normals
   (fallback: computed face normal, averaged to vertex).

2. SkiaPreviewRenderer uses per-vertex normals transformed with the mesh, computes
   per-vertex lambert, and interpolates per-pixel via barycentric weights (Gouraud
   shading). Flat surfaces still look flat, smooth surfaces now show real curvature.

3. Fixed supersample = 2 (removed adaptive 3/4). Preview 384x384 (768x768 internal
   at SS=2). No ZBias (could skip triangles). Fill light with threshold (as 0.4.5a8).

4. MinLambert = 0.45 (between 0.4 and 0.5).

5. RendererVersion bumped to 0.4.5a10 - forces regeneration.

## Expected result

- Dense 1.5M poly models: smooth shading gradient visible (not flat grey).
- STL files with broken winding: correctly lit because we use file normals.
- OBJ files with per-vertex normals: Gouraud-shaded (smooth).
- Z-fighting: handled by natural z-order at 768x768 internal.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate.
- No flat grey silhouettes; models show volume.