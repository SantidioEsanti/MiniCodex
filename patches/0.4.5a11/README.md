# Patch 0.4.5a11 - Remove fill light + remove Quality UI

**Iteration:** 0.4.5

## What it does

1. SkiaPreviewRenderer: fill light fully removed. Only key light (-0.4, 0.6, 1).
   Gouraud shading preserved. Models will look less "chrome" - single-direction
   light creates natural shadow falloff instead of soft even lighting.

2. ModelCardPageViewModel: RenderQuality, QualityChoices, LabelQuality removed.
   Render.Quality persistence removed.

3. ModelCardView.axaml: Quality ComboBox removed.

4. ThreeDViewer: QualityProperty removed. Internal drag optimization kept:
   during drag renders at half resolution + SS=1 (4x faster for responsiveness),
   after pointer release re-renders at full resolution + SS=2.
   This is not a user-visible "LOD" - no option, automatic, and result after drag
   is always at full quality.

5. RendererVersion 0.4.5a11 - forces preview regeneration.

## Expected result

- Less "chrome" look: sharper light/shadow contrast, single-direction lighting.
- No Quality ComboBox in card toolbar.
- Drag is still responsive (internal optimization), and after release shows crisp image.
- Previews in library regenerated with single-light shading.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After restart: previews regenerate. Models look more "3D-printed" (contrast lighting) vs "chromed" (even lighting).