# Patch 0.4.5a4 - Preview progress, no duplicates

**Iteration:** 0.4.5

## What it does

1. LibraryViewModel: preview progress in status bar.
   - PreviewsDone / PreviewsTotal counters.
   - Status: "Previews: 8 / 248" during queue, back to "Models: 248" when done.

2. LibraryViewModel: IAsyncDisposable.
   - CancellationTokenSource _lifetimeCts cancels all pending preview tasks on dispose.
   - OnDetachedFromVisualTree in LibraryView calls vm.DisposeAsync().
   - Prevents duplicate parallel PreviewGen (old VM no longer queues tasks).

3. LibraryView: clean dispose on detach.

4. lang: Library.PreviewsProgress.

## Why

User closed app while previews were still generating (log showed EXIT after 8/248 models).
Without progress UI, "still working" looked like "hanging".
Without cancellation, navigating away/back created a second LibraryViewModel whose SemaphoreSlim
allowed a second parallel PreviewGen (memory spike to 1.6 GB, potential re-OOM on huge libs).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scan a large folder: status bar shows "Previews: X / Y" until done, then "Models: Y".
- Navigate to Settings and back: no duplicate parallel PreviewGen in log.
- Close app mid-generation: pending tasks cancelled cleanly.