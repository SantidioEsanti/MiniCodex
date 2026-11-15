# MiniCodex v0.1.3

Portable 3D model library for Windows. **Pre-release.**

A lightweight desktop app for organizing, viewing, and printing 3D models. No install, no admin rights, data lives next to the exe.

## Highlights

- **Associated files viewer**
  - Fullscreen image viewer: double-click a thumbnail, navigate Left/Right, Esc to close.
  - Context menu on every thumbnail: Open (fullscreen) / Open with default viewer / Open in Explorer / Copy path / Replace... / Remove (with confirmation).
  - Third "Other" section for render / document / profile assets (icon fallback for non-images).
- **Multi-select in library grid**
  - Plain click, Ctrl+click (toggle), Shift+click (range), rubber-band on empty space (Ctrl = additive).
  - Esc clears selection, Ctrl+A selects all visible.
  - Group toolbar appears when 2+ cards selected: Add tag (autocomplete) / Copy paths / Find duplicates in selection / Remove selected / Clear.
- **Collection colors** - 8 preset swatches + Clear via context menu on each collection in the sidebar.
- **Tag autocomplete** - in Add tag dialogs (both on the card and in the group dialog).
- **Delete-tag dialog breakdown** - shows direct vs subtree usage count.

## What is new (full changelog)

See CHANGELOG.md in the repository for the full [0.1.3] section with all changes.

## Download

- MiniCodex-v0.1.3-win-x64.zip (attached below)

## Install

1. Extract anywhere (Desktop, portable USB drive, etc.).
2. Run MiniCodex.exe.
3. Data is stored in ./data/ next to the exe. First run creates it.

No installer, no admin rights, no .NET install required (self-contained build).

## Requirements

- Windows 10/11 x64.

## Known limitations

- Windows x64 only.
- Fullscreen image viewer: no zoom/pan, no rotation, no EXIF orientation.
- Replace re-imports the file as a new asset row; old thumbnail stays in cache (harmless).
- Tag rename/delete does not merge same-named children.
- Software renderer: ~50-100ms per frame at 480x480 on 100k triangles. No LOD.
- Search: SQLite LIKE is case-sensitive for Cyrillic (English fine).

## Checksums

    SHA-256 (MiniCodex-v0.1.3-win-x64.zip): <fill after build>

---

Licensed under MIT. Repository: https://github.com/SantidioEsanti/MiniCodex