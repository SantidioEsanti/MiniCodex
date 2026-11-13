# Patch 0.4.5a7 - Two-sided lighting

**Iteration:** 0.4.5

## Root cause (from 0.4.5a6 screenshot)

STL files produced by different generators have inconsistent face winding.
Some triangles are CW, some CCW. We compute normal = cross(edge1, edge2) from
the winding, so adjacent triangles on the same surface get opposite normals.

Rendering (single-sided):
- Normal points toward light: dot > 0, lambert = 0.8..1.0 -> WHITE
- Normal points away from light: dot < 0, lambert = MinLambert (0.4) -> DARK GREY

Adjacent triangles on one plane -> white sparkle next to dark grey -> visible "noise".

## Fix

Math.Abs on the dot product (two-sided lighting):

  var lambert = MathF.Max(style.MinLambert, MathF.Abs(Vector3.Dot(normal, lightDir)));

Standard technique for STL rendering when winding is not unified.
Both faces of each triangle render with correct lambert shading based on |angle| to light.

RendererVersion bumped to "0.4.5a7" - forces preview regeneration.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate automatically.
- No white sparkle on any model. All models render as solid shaded silhouettes.
- Layer-line texture (from 3D-printed scans) remains visible as intended surface detail.