# Patch 0.4.5a6 - Fix remaining shatter

**Iteration:** 0.4.5

## Root cause (persisted after 0.4.5a5)

1. Sub-pixel force-draw painted only the CENTER pixel of tiny bboxes.
   Neighbour pixels stayed empty -> sandpaper on smooth models, holes on dense ones.
   Fix: fill ENTIRE bbox (up to 3x3 pixels = 9) when spanX * spanY <= 9.

2. Degenerate triangles (normal ~ 0) were SKIPPED via `continue`.
   Many STL meshes contain degenerate faces after Triangulate (no JoinIdenticalVertices).
   Fix: draw with MinLambert color instead of skipping.

3. SS=2 insufficient for 1.5M polygons at 512x512.
   Average triangle = 0.17 pixels, adjacent triangles land in different pixels.
   Fix: High quality now uses SS=3 (768x768 internal), each output pixel averages 9 subpixels.

4. Scale safety: bbox with maxDim < 1e-6 rendered as unit cube
   (fixes "empty" previews seen for a few models).

5. RendererVersion bumped to "0.4.5a6" - forces all previews to regenerate.

## Quality mapping

- High: idle SS=3 (768x768 internal, ~1.8s per model), drag half-res SS=1 (200ms).
- Medium: idle SS=2 (512x512, ~800ms), drag half-res SS=1 (200ms).
- Low: idle SS=1 (256x256, ~200ms), drag quarter-res SS=1 (~50ms).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart, previews regenerate automatically (RendererVersion changed).
- No shatter on High. Medium may have slight sandpaper but usable. Low for speed only.
- Viewer High idle: 1.8s wait, but crisp. Drag: 200ms/frame.