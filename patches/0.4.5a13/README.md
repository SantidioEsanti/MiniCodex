# Patch 0.4.5a13 - Final polish

**Iteration:** 0.4.5

## What it does

1. YawDegrees { 180, 220, 260, 300 } -> { 220, 250, 280, 310 }.
   Range 90deg (was 120). 4 stops at 30deg apart. Starts at 220 (3/4 back).

2. Theme persistence (Setting "UI.Theme"):
   - MainWindowViewModel ctor loads saved theme synchronously (one-time, ~1ms).
   - Setter saves on each change.

3. Auto-save in model card:
   - Text fields Title, Author, SourceUrl, Notes: debounce 500ms -> SaveAsync.
   - Scale fields (RealHeightMmText, ModelHeightMmText, OnScaleChanged): debounce 500ms -> SaveAsync.
   - Status/Difficulty were already auto-saved (0.4.3e.1).
   - Tags, primary file were already auto-saved via commands.
   - Save button removed from toolbar. "Saved" status still appears after autosave.

4. Library preview cleanup:
   - ModelCardTile.axaml: gray background around preview removed (Background=Transparent).
   - Image wrapped in Border with CornerRadius=6 + ClipToBounds=True: preview itself rounded.
   - Hover overlay aligned to new margins.

5. RendererVersion 0.4.5a13 (angles changed -> regen needed).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Library: no gray rectangle around preview; preview corners rounded.
- Model card: Save button gone. Type in Title -> after 500ms "Saved" appears.
- Change theme -> close app -> reopen -> theme restored.
- Hover rotation: 30deg steps.