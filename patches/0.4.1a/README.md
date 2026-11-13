# Patch 0.4.1a - Hover-panel, Quick Actions, rotation

**Iteration:** 0.4

Fixes 0.4.1 (PS 5.1 parser error from non-ASCII chars in UTF-8 without BOM).
This script is pure ASCII; Russian strings are injected via base64 at runtime.

## What it does

- Hover-panel on each card: total size, polygon count, file count (if >1).
- Rotation on hover: horizontal mouse movement switches the 4 preview angles.
- Context menu (right-click + "..." button):
  - Open card, Copy path, Add tag (opens card on Tags tab), Show in folder
  - To slicer / To editor (first available)
  - Remove from library (DB only, files NOT touched)
- New files: ModelCardTile.axaml(.cs), FileSystemHelper.cs.
- Updated: ModelCardViewModel, LibraryViewModel, MainWindowViewModel, LibraryView.axaml.
- New lang keys: Library.Hover.PolygonsFormat, Library.Hover.FilesFormat, Library.MoreActions.

## Deferred to 0.4.1b

- Del key (needs card selection model).
- Grid virtualization.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40.
- Hover on card: metadata strip at bottom, "..." at top-right.
- Horizontal mouse movement: preview rotates.
- Right-click: context menu works.
- Remove from library: card disappears, files on disk stay.