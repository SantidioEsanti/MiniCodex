# Patch 0.4.3e.1 - Auto-save Status/Difficulty, compact Info, viewer fills height

**Iteration:** 0.4

## What it does

1. Auto-save Status/Difficulty:
   - IModelRepository.UpdateStatusDifficultyAsync (UPDATE only status, difficulty; no UpdatedAt touch).
   - SetStatus and SetDifficulty are now async void, call SaveFieldAsync after change.
   - Status toggle: click active status -> reset to empty.
   - Previews cache NOT invalidated (UpdatedAt unchanged).

2. Compact Info panel:
   - Title/Author/SourceUrl: no labels above, only Watermark in TextBox.
   - Status/Difficulty: label moved inline (left of icons/stars, Width=90).
   - ScrollViewer removed (content short enough).
   - Saves ~100px vertical.

3. Viewer fills available vertical space:
   - Left column: RowDefinitions "320,*" -> "*,Auto".
   - 3D viewer ~450px on 750px window (was 320px).
   - Horizontal models (tanks, ships) get more room.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Card: viewer taller, Info panel more compact.
- Click status icon -> saves instantly (close+reopen shows same value).
- Click star -> saves instantly.
- Text fields show grey placeholders when empty (Title, Author, Source URL).