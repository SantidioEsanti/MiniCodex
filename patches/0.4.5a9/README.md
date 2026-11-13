# Patch 0.4.5a9 - Fix flat shading on high-poly

**Iteration:** 0.4.5

## Root cause (from screenshots)

Two bugs on 1.5M poly models:

1. Sub-pixel bbox fill used avg(z) + ZBias. With 22 triangles per pixel, only
   the first triangle (random) wrote, others were blocked by ZBias. Result: flat
   gray noise instead of front-most triangle's shading.

2. Fill light was gated to keyL < 0.5. A shadowed face with keyL=0.4 got fillL=0.35
   -> combined 0.75 (bright). A mid-lit face with keyL=0.6 got no fill -> 0.6 (darker).
   That's an INVERSION: shadows brighter than midtones. Flat gray result.

## Fixes

1. Sub-pixel triangle: use max(z0, z1, z2) (front-most vertex) + NO ZBias.
   Front-most triangle always wins. Correct gradient preserved on dense meshes.

2. Fill light: always added (removed keyL < 0.5 gate).
   combined = min(1.0, keyL + fillL * 0.35). Monotonic: brighter surface = brighter pixel.

3. MinLambert default back to 0.4 (from 0.5). More contrast in shadows.

4. Preview resolution 384x384 (from 256). 1.5x more detail visible in library card.

5. Adaptive supersample per triangle count:
   - < 200K tris: SS=2 (768x768 internal)
   - < 500K tris: SS=3 (1152x1152 internal)
   - >= 500K tris: SS=4 (1536x1536 internal)

6. RendererVersion 0.4.5a9 - forces regeneration.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate at 384x384 with adaptive SS.
- High-poly models show proper shading gradient (not flat gray).
- Warrior-base z-fighting still fixed (regular branch keeps ZBias).