# Patch 0.4.2b - Regenerate previews button + tile auto-refresh

**Iteration:** 0.4

## What it does

- ModelCardPageViewModel:
  - RegeneratePreviewsCommand: saves current orientation, force-regenerates 4 PNGs, raises PreviewsRegenerated(modelId).
  - IsRegenerating / CanRegeneratePreviews: button disabled during work or if no primary file.
  - Status feedback: "Regenerating..." -> "Previews updated" (uses OrientationStatusText).
- ModelCardView: "Regenerate previews" button after "Save orientation".
- MainWindowViewModel: subscribes to PreviewsRegenerated and calls Library.OnPreviewsRegeneratedAsync(modelId).
- LibraryViewModel.OnPreviewsRegeneratedAsync: finds card by id, calls ReloadPreviewsAsync.
- lang/en.json + lang/ru.json: Card.Status.Regenerating, Card.Status.Regenerated.

## Effect

User flow: open card -> rotate -> "Save orientation" -> "Regenerate previews" -> back to library.
Tile in library now shows the new angle without restart or rescan.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40.
- Save orientation, regenerate, back: tile shows new angle.
- Button disabled while regenerating (fast on small meshes, visible on large).