# Patch 0.4.5a8 - Final render polish

**Iteration:** 0.4.5

## What it does

1. Z-buffer bias (ZBias = 1e-4) in RasterizeTriangle.
   Applied in main barycentric loop AND in sub-pixel bbox fill.
   Fixes z-fighting flicker on coplanar surfaces (bases, plinths, flat bottoms).

2. Fill light: second directional light (0.3, -0.4, 0.5), strength 0.35.
   Applied ONLY on shadowed faces (keyLambert < 0.5).
   Lit faces keep pure key light strength (no over-brighten).

3. MinLambert default 0.4 -> 0.5 in RenderStyle record and ModelCardPageViewModel._minLambert.
   Shadows ~25% lighter. Slider in UI stays, user can revert per-card.

4. RendererVersion 0.4.5a8 - forces preview regeneration.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate automatically.
- Warrior-with-base and other coplanar-base models: no white speckle on base.
- All models slightly lighter in shadows (MinLambert 0.5).