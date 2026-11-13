# Patch 0.4.5a5 - Fix shatter + Quality/LOD

**Iteration:** 0.4.5

## Root cause of shatter

At 1.5M polygons on a 256x256 preview, average triangle covers ~0.04 pixels.
Barycentric center-of-pixel test misses 96% of triangles -> holes/shards on surface.

## Fixes

1. Sub-pixel force-draw in RasterizeTriangle:
   - If bbox span is <=2x2 pixels, force-draw to bbox center pixel.
   - Every tiny triangle contributes -> no holes.
   - Cost: one z-test per triangle, cheaper than the skipped barycentric loop.

2. Supersample in SkiaPreviewRenderer:
   - IPreviewRenderer.Render gains supersample param (default 2).
   - Renders at supersample x width/height, downsamples by averaging.
   - Previews use SS=2 (256 becomes 512 internal), eliminating sandpaper.

3. ThreeDViewer Quality property (High/Medium/Low):
   - Drag detection: _isDragging set when movement > 0.5px.
   - Drag renders at reduced resolution (half for High/Medium, quarter for Low).
   - Idle renders at full resolution (SS=2 for High, SS=1 for Medium/Low).
   - Pointer release triggers crisp re-render.

4. ModelCardPageViewModel.RenderQuality (High/Medium/Low), persisted to Setting "Render.Quality".

5. ModelCardView: Quality ComboBox next to MinLambert slider.

## Expected behavior

- Previews: SS=2, ~800ms per model, no shatter, no sandpaper.
- Viewer High: idle SS=2 (smooth, ~800ms), drag half-size (50ms, 20fps).
- Viewer Medium: idle SS=1 (200ms, slight sandpaper), drag half (50ms).
- Viewer Low: idle SS=1 (200ms), drag quarter (12ms, 80fps).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Clear data/cache/previews before testing (RendererVersion unchanged).
- Previews no longer show broken polygons.
- Drag in viewer is responsive (no 800ms freezes).
- Quality ComboBox works, persists across restarts.