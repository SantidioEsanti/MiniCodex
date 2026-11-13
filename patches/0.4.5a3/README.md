# Patch 0.4.5a3 - Fix Assimp OOM

**Iteration:** 0.4.5

## Root cause (from user log)

1. LibraryViewModel.ReloadModelsCoreAsync launched 76 x Task.Run(LoadDetailsAsync) in parallel.
   Each LoadDetails calls PreviewGenerator -> Assimp ImportFile for a 1.5M-poly model (~500 MB native).
   76 simultaneous native allocations -> "bad allocation" (native OOM).

2. PreviewGenerator called LoadGeometry 4 times per model (once per angle).
   4x time and 4x peak memory for the same model.

3. GC did not release native Assimp scene memory between models (no forced collection).

## Fixes

1. LibraryViewModel: SemaphoreSlim(1,1) around LoadDetailsAsync.
   Only ONE preview generator runs at a time. Others queue.
   UI remains responsive (Task.Run). Previews appear one-by-one.

2. PreviewGenerator:
   - LoadGeometry called ONCE per model, reused for all 4 angles.
   - Explicit GC.Collect after each model (releases native scene memory).
   - Logs per-model: LoadGeometry took, Render per angle, total mem.

3. ScannerService:
   - GC.Collect every 10 processed files.
   - Logs forced GC after N files with mem.

## Expected result

- Scanning 76 x 1.5M poly models no longer OOM.
- Speed: ~90s Assimp Import + 4x ~1s render per model, sequential.
  Total ~2 hours for 76 models. Slow but STABLE.
- Log shows PreviewGen START / LoadGeometry / Render / DONE per model.
- Memory stays bounded (~2 GB peak instead of 10+ GB).

## Not in this patch (planned for 0.4.5a4)

- Fast binary STL header parser for Scan (polys from header, no full Assimp import).
  This will reduce Scan time from ~2 hours to ~5 minutes for 76 x 1.5M STL files.
- Skip preview generation for huge models (>5M tris).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48 (PreviewGeneratorTests still pass - EnsurePreviewsAsync behavior unchanged from caller perspective).
- Scan folder: no OOM, scan completes.
- Log shows PreviewGen per-model with serialized execution.