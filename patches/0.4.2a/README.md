# Patch 0.4.2a - PreviewGenerator uses orientation (plumbing)

**Iteration:** 0.4

## What it does

- IPreviewGenerator.EnsurePreviewsAsync: 3 new optional params (baseYawDegrees, basePitchDegrees, forceRegenerate).
  Backward compatible: existing 4-arg calls use defaults (0, 0, false).
- PreviewGenerator:
  - Effective yaw = standard_yaw + baseYaw; effective pitch = 15 + basePitch.
  - CacheMetadata now stores baseYaw, basePitch. Cache invalidates if they differ from stored by >0.01.
  - forceRegenerate bypasses cache check.
  - RendererVersion kept at "0.2.3c" to avoid mass regen for models with default orientation.
- ModelCardViewModel.LoadDetailsAsync:
  - Reads Model.OrientationJson.
  - Computes offset relative to defaults (180 yaw, 15 pitch): offset = (o.Yaw - 180, o.Pitch - 15).
  - Passes offset to EnsurePreviewsAsync.
  - Models without orientation -> offset (0, 0) -> same behavior as before.
- ModelCardViewModel.ReloadPreviewsAsync: clears _previews[], reloads (used by 0.4.2b).

## No UI change

The "Regenerate previews" button and library tile refresh come in 0.4.2b.
Effect after 0.4.2a: if user saved orientation and reloads library (restart, rescan),
the tile shows the new angle. No button yet.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40 (PreviewGeneratorTests still pass; stub call signature unchanged for Render).
- App starts and behaves as 0.4.2 (no regressions).