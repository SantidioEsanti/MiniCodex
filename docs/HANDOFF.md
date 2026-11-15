# HANDOFF - MiniCodex

**Document version:** 3.1 (post v0.1.3 release prep)
**Last updated:** 2026-11-15
**Current version:** v0.1.3 (release prep complete, awaiting git tag + GitHub Release)
**Purpose:** Context transfer for a new AI dialogue to continue development.

---

## 1. Quick start (read this first)

If you are an AI picking up this project in a new dialogue:

1. Read this document fully.
2. Project state: v0.1.3 release prep is complete (patches 0.5.6a..0.5.6c.1b applied). Next step is build-release.ps1 + git tag + GitHub Release.
3. Do NOT re-architect. Code is stable, all 60 tests pass, 0 warnings.
4. All changes go through **patch scripts** (see section 10). No direct edits in src/.
5. Before writing any .ps1 patch, read section 10 carefully - it lists 11 hard-won lessons.

---

## 2. Project state

- **Name:** MiniCodex (working title, accepted).
- **Version:** 0.1.3 (release prep complete; awaiting tag).
- **Platform:** Windows x64 desktop only (uses Registry, Explorer, Segoe Fluent Icons).
- **Distribution:** Portable (zip, no install, no admin rights).
- **Licence:** MIT.
- **Repository:** https://github.com/SantidioEsanti/MiniCodex (public, MIT license).
- **Previous release:** v0.1.0-alpha (2026-11-13, first public).
- **Patch count since 0.1.0:** ~40 patches (see patches/).
- **Tests:** 60 passing. **Build:** 0 errors, 0 warnings.

### What is fully implemented (v0.1.3)

- Library screen: cards grid with "Soft Glass" UI (rounded corners, soft shadows, gradients). Distinct card background per theme.
- Scan folders: recursive, incremental by (path + size + last_write_time), progress bar, cancel, skips unavailable folders.
- Preview generation: 4 angles (220/250/280/310 yaw, pitch 15), PNG cache, invalidation by source_updated_at + RendererVersion + baseOrientation.
- 3D viewer on card: drag to rotate, mouse wheel to zoom, wireframe toggle, MinLambert slider, theme-aware background.
- MeshNormalSmoother: spatial deduplication for 3D-scanned STLs (smooth normals for meshes >500K triangles).
- Duplicate detection: SHA-256 file hashes in DB, "Find duplicates" toolbar button.
- Smart Collections: save search + tag filter as a named collection in the sidebar. JSON filter stored in Collection.filter_query.
- Tag management: TreeView hierarchy (parent_id), Rename / Delete / Clear Color context menu, custom HEX color picker with 8 presets + live preview.
- Tag autocomplete in Add tag dialogs (card + group); Delete-tag dialog: direct vs subtree usage breakdown.
- Associated files fullscreen viewer (double-click open, Left/Right nav, Esc close); thumbnail context menu (Open fullscreen / Open external / Explorer / Copy path / Replace / Remove with confirmation); "Other" section (render/document/profile) 128x128.
- Multi-select in library grid: plain/Ctrl/Shift click, rubber-band, Ctrl+A/Esc; group toolbar (Add tag with autocomplete / Copy paths / Find duplicates in selection / Remove selected / Clear).
- Collection colors: 8 preset swatches + Clear via context menu.
- Single-instance lock: Named Mutex prevents multiple launches racing on SQLite.
- Keyboard UX: Enter/Esc in all dialogs (Panel.KeyBindings).
- Context menu on tags: works on the full highlighted row (TreeViewItem PART_HeaderPresenter stretched).
- RU + EN localization, autodetect by system locale, fallback to EN.
- Themes light/dark/auto, amber accent #E67E22.

---

## 3. Fixed project decisions

| Parameter | Value |
|---|---|
| Name | MiniCodex |
| Platform | Windows (desktop) x64 |
| Stack | .NET 8 + Avalonia UI 11.2.3 |
| Rendering | SkiaSharp (CPU, software rasterizer) |
| Mesh parsing | AssimpNet + own wrappers |
| DB | SQLite (Microsoft.Data.Sqlite 8.0.10) |
| Licence | MIT |
| Release | GitHub (current: v0.1.2, next: v0.1.3) |
| Distribution | Portable zip (self-contained single-file) |
| Localization | RU + EN, expandable via JSON |
| Themes | light / dark / auto |
| Data storage | Portable ./data/ next to exe |
| Accent | Amber #E67E22 |
| Font | Inter (fallback Segoe UI) |

---

## 4. File structure (actual)

D:\AI\MiniCodex\
- .github/workflows/build.yml - CI (build + test + publish)
- .gitignore
- LICENSE - MIT
- README.md - project positioning (screenshots in docs/screenshots/)
- CHANGELOG.md - version history (updated with [0.1.2] section)
- build-release.ps1 - release zip builder
- docs/
  - HANDOFF.md (this file)
  - ROADMAP.md (MVP roadmap, historical)
  - ARCHITECTURE.md (ADR)
  - DB_SCHEMA.md (schema)
  - UI_UX.md (screens)
  - SCALES.md (scale presets)
  - screenshots/ (01..05)
- lang/
  - en.json
  - ru.json
- patches/ (each patch: patch_X.ps1 + README.md + patch.log)
  - 0.1.0 ... 0.5.5
- backups/ (auto-created, {version}_{timestamp}/)
- dist/ (built zips)
- src/
  - MiniCodex.sln
  - MiniCodex.App/ (Avalonia UI)
    - App.axaml(.cs) - theme dictionaries, styles, DataTemplates
    - Program.cs - single-instance Mutex, WithInterFont, global exception handlers
    - AppServices.cs - composition root (Models, Files, Assets, Settings, ModelTags, Scanner, PreviewGenerator, AssetService, TagService, CollectionService, IntegrationService)
    - Services/ - AppPaths, LocalizationService, ThemeService, FileSystemHelper, WindowsRegistryProbe
    - ViewModels/ - MainWindow, Library, ModelCard, ModelCardPage, Settings, IntegrationAppRow, ModelFileRow, AssetRow, TagRow, TagNode, CollectionRow, RelayCommand
    - Views/ - MainWindow, LibraryView, ModelCardTile, ModelCardView, ThreeDViewer, SettingsView
  - MiniCodex.Core/ (business logic, no UI/Data/Render deps)
    - Logging/Log.cs - crash-safe file logger
    - Models/ - Entities.cs (Model, ModelFile, Asset, Tag, Collection), MeshInfo, MeshGeometry, ScalePreset, ModelOrientation, TagWithUsage, IntegrationApp, SmartCollectionFilter
    - Repositories/ - IRepositories (IModel, IModelFile, IAsset, ITag, IModelTag, ICollection, ISetting)
    - Services/ - IMeshLoader, IMeshGeometryLoader, IPreviewRenderer, IPreviewGenerator, PreviewGenerator, PreviewGeneratorOptions, RenderStyle, IScannerService, ScannerService, ScanProgress, IAssetService, AssetService, IAssetThumbnailGenerator, ITagService, TagService, ICollectionService, CollectionService, IIntegrationProbe, IIntegrationService, IntegrationService, IntegrationCatalog, ScaleCatalog
  - MiniCodex.Data/ (SQLite)
    - SqliteConnectionFactory.cs - PRAGMA foreign_keys = ON
    - MigrationRunner.cs, DatabaseInitializer.cs
    - Migrations/ - 0001_InitialSchema, 0002_ModelFile_LastWriteTime, 0003_ModelOrientation, 0004_ModelFile_FileHash, 0005_Collection_Color
    - Repositories/ - ModelRepository, ModelFileRepository, AssetRepository, TagRepository, ModelTagRepository, CollectionRepository, SettingRepository
  - MiniCodex.Render/ (3D and images, depends on Core)
    - Loaders/ - AssimpMeshLoader
    - Rendering/ - SkiaPreviewRenderer, SkiaThumbnailGenerator, MeshNormalSmoother
  - MiniCodex.Tests/ (xUnit, 60 tests)
    - CollectionServiceTests (5), DatabaseInitializerTests (3), MeshNormalSmootherTests (2), TagCrudTests (5), + existing 45

---

## 5. Architecture

Layers, dependency direction (arrows = depends on):

  MiniCodex.App  -->  Core, Data, Render
  MiniCodex.Data -->  Core
  MiniCodex.Render --> Core
  MiniCodex.Core --> (nothing, pure)

Rules:
- Core has ZERO dependencies on UI, Data, Render. Only BCL.
- Render implements Core interfaces (IMeshLoader, IMeshGeometryLoader, IPreviewRenderer, IAssetThumbnailGenerator).
- Data implements Core repository interfaces.
- App composes everything via AppServices.Init(paths).

Portable runtime:
- AppContext.BaseDirectory is the exe folder.
- data/library.db - SQLite DB
- data/cache/previews/{modelId}/{angle}.png + metadata.json
- data/cache/asset-thumbs/{assetId}_256.png
- data/assets/{modelId}/{8hex}_{origName}{ext}
- data/logs/minicodex-{yyyyMMdd}.log

Localization:
- lang/{en,ru}.json, loaded at startup, autodetect via CultureInfo.CurrentUICulture, fallback EN.
- Keys use PascalCase.Category.Subkey.
- UI strings via App.Loc.Get(key) or computed properties in ViewModels.

---

## 6. Database schema

SQLite, file at data/library.db. Migrations applied at startup (idempotent).

Tables:
- Model (id TEXT PK, title, author, source_url, model_type, primary_model_file_id, status, difficulty INTEGER, real_height_mm REAL, model_height_mm REAL, scale_ratio, notes, orientation_json, created_at, updated_at)
- ModelFile (id TEXT PK, model_id TEXT FK, path, file_role, part_name, file_size_bytes INTEGER, polygon_count INTEGER, last_write_time_utc, file_hash TEXT)
- Asset (id TEXT PK, model_id TEXT FK, asset_type, absolute_path, thumbnail_path, sort_order INTEGER, storage_mode)
- Tag (id TEXT PK, name, parent_id, color)
- ModelTag (model_id, tag_id, PRIMARY KEY)
- Collection (id TEXT PK, name, filter_query, is_smart INTEGER, color TEXT)
- Setting (key TEXT PK, value TEXT)

Migrations:
1. Initial schema.
2. Add last_write_time_utc to ModelFile.
3. Add orientation_json to Model.
4. Add file_hash (SHA-256) to ModelFile.
5. Add color (TEXT) to Collection.

FK: ModelTag.model_id -> Model.id, ModelTag.tag_id -> Tag.id (PRAGMA foreign_keys = ON in SqliteConnectionFactory).

Enums (strings in DB):
- Model.status: planned | printed | painted
- Model.model_type: single | split | multipart | diorama | variant_set
- ModelFile.file_role: main | part | presupported | hollowed | variant | accessory
- Asset.asset_type: reference | render | photo | document | profile
- Asset.storage_mode: hybrid | adjacent | central | restructure

---

## 7. Tech stack (exact versions)

MiniCodex.App.csproj:
- Avalonia 11.2.3
- Avalonia.Desktop 11.2.3
- Avalonia.Themes.Fluent 11.2.3
- Avalonia.Fonts.Inter 11.2.3
- Microsoft.Win32.Registry 5.0.0

MiniCodex.Render.csproj:
- AssimpNet 4.1.0
- SkiaSharp 2.88.8
- SkiaSharp.NativeAssets.Win32 2.88.8

MiniCodex.Data.csproj:
- Microsoft.Data.Sqlite 8.0.10

MiniCodex.Tests.csproj:
- Microsoft.NET.Test.Sdk 17.11.1
- xunit 2.9.2
- xunit.runner.visualstudio 2.8.2

SDK: .NET 8 (targets net8.0), builds fine with .NET 9 SDK (9.0.318).

---

## 8. Features working (checklist)

- [x] Portable data dir, first-run creates data/
- [x] RU/EN localization, autodetect, fallback EN
- [x] Themes light/dark/auto, amber accent
- [x] Inter font with Segoe UI fallback
- [x] Library grid: cards, soft shadow, hover metadata, 4-angle rotation on hover, context menu, More button, double-click open
- [x] Scan folders: incremental, progress, cancel, unavailable-folder handling
- [x] Preview cache: 4 angles PNG, invalidation
- [x] 3D viewer: drag rotate, zoom, wireframe, MinLambert slider, theme-aware bg
- [x] MeshNormalSmoother: spatial dedup for 3D-scanned STLs
- [x] Duplicate detection: SHA-256 file hashes, "Find duplicates" toolbar button
- [x] Single-instance lock: Named Mutex
- [x] Smart Collections: save filter, sidebar ListBox, apply on click, delete
- [x] Tag hierarchy in TreeView (parent_id)
- [x] Tag management: Rename, Delete (with association cleanup), Clear Color
- [x] Tag color: 8 preset swatches + custom HEX picker with live preview
- [x] Keyboard UX: Enter/Esc in all dialogs (Panel.KeyBindings)
- [x] Context menu on full tag row
- [x] Model card layout: viewer + Info left, tabs right
- [x] Info auto-save for Status/Difficulty
- [x] Associations: Reference/Photo drag-drop, 256x256 thumbs
- [x] Associated files: fullscreen viewer (double-click, Left/Right nav, Esc), thumbnail context menu (Open fullscreen / Open external / Explorer / Copy path / Replace / Remove with confirmation), Other section (render/document/profile) 128x128
- [x] Multi-select in library grid: plain/Ctrl/Shift click, rubber-band, Ctrl+A/Esc, group toolbar (Add tag / Copy paths / Find duplicates / Remove selected / Clear)
- [x] Collection colors: 8 preset swatches + Clear via context menu
- [x] Tag autocomplete in Add tag dialogs (card + group)
- [x] Delete-tag dialog: direct vs subtree usage breakdown
- [x] Scale converter: 43 presets, prototype filter, bidirectional auto-calc
- [x] Integrations: 12 apps (Bambu Studio, PrusaSlicer, OrcaSlicer, UltiMaker Cura, Lychee, CHITUBOX, Anycubic Slicer, Anycubic Slicer Next, Blender, ZBrush, 3D-Coat, Meshmixer)
- [x] Settings screen: integrations list, Re-detect, Browse, Clear

---

## 9. Deferred to v1.1+ (out of current scope)

- ZIP/RAR/7Z archives
- Duplicate detection by geometry
- Printer bed fit check
- Real 3D rotation in library grid
- Bulk tag editing
- Auto-tags from filename/folder
- Adjacent storage mode
- Composite model merge
- WebP cache
- Tag subtree as collection (currently single TagId, but parent-tag filter already includes descendants)
- macOS/Linux support
- Mica/Acrylic window background
- Wildcard paths in IntegrationCatalog

---

## 10. Patch workflow - CRITICAL

All changes after 0.1.0 go through patch scripts. Direct edits in src/ forbidden.

### 10.1 Location and naming

D:\AI\MiniCodex\patches\{MAJOR}.{MINOR}.{PATCH}\patch_{MAJOR}.{MINOR}.{PATCH}.ps1
Alongside: README.md describing what/why/files affected.

Version format: MAJOR.MINOR.PATCH
- MAJOR = 0 (pre-release), 1 after stable release
- MINOR = iteration number
- PATCH = sequential number within iteration
- Suffixes like "a", "b", ".1" used for fixes

### 10.2 Mandatory script contract

1. Backup affected files to backups/{version}_{YYYYMMDD_HHMMSS}/ FIRST.
2. Be idempotent (repeat run does not break state).
3. Log to console + patches/{version}/patch.log (UTF-8).
4. On error: report, print backup path, suggest restore command. NO auto-rollback.
5. Update CHANGELOG.md at end (with marker <!-- patch X applied -->).

### 10.3 Run command (always)

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\{version}\patch_{version}.ps1"

### 10.4 HARD-WON LESSONS (read these, they prevent lost hours)

1. **ASCII-only .ps1** - the safest form. Do not put Cyrillic, "..." (U+2026), em-dash, guillemets, or any non-ASCII characters in .ps1. PS 5.1 reads .ps1 without BOM as CP1251, so UTF-8 bytes get misinterpreted and the parser breaks unpredictably.
   - For Russian strings inside patch, encode with [char] codes: -join ((0x041F,0x0440,...) | % {[char]$_})
   - Or use base64: [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('...'))
   - Or use C# string escapes: "\u041F\u0440..." in C# content

2. **BOM required if any non-ASCII in .ps1** - prepend the BOM fix command to the run line. Without BOM, PS 5.1 fails with "Missing }" / "Try without Catch" (misleading errors).

3. **No here-strings with indented closer** - '@ or "@ must be at column 0, NO leading spaces. An indented closer is not recognized, the parser eats the rest of the file.

4. **Remove-Item in pipeline hangs** - PS 5.1 does not bind FileInfo from pipeline to Path. Always use foreach + Remove-Item -LiteralPath $f.FullName -Force inside loop.

5. **Avalonia XAML: DragOver/Drop are attached events** - attribute names must be DragDrop.DragOver="..." DragDrop.Drop="...". Bare DragOver="..." gives AVLN2000.

6. **Avalonia StackPanel has no Padding** - Padding is on Border / Decorator. Move Padding to parent Border.

7. **Unicode in XAML** - use XML character references: &#x22EF;, &#x00D7;, &#xE823;. No raw Unicode needed.

8. **One patch = one logical step** - do not bundle core plumbing + full UI in a single script. Split: 0.4.2a (plumbing) then 0.4.2b (UI).

9. **Tree check** - use: cmd /c tree /F /A "D:\AI\MiniCodex" (full path in quotes).

10. **Event signatures in code-behind** - DragEventArgs for DragDrop.Drop and DragDrop.DragOver. Not RoutedEventArgs.

11. **String.Split(string) does not exist in PS 5.1** - it silently binds to Split(char[]), so "abc".Split("b") iterates chars and returns 3 pieces, not 2. For occurrence counting use: [regex]::Matches($text, [regex]::Escape($anchor)).Count. Symptom: "Anchor ambiguous (14782 occurrences)" for a 45-char string.

### 10.5 Rollback

Manual only: copy files from backups/{version}_{timestamp}/ back into D:\AI\MiniCodex\.
Script on error prints restore command.

### 10.6 Patch output format (after every patch text)

After each patch script, the assistant MUST print, in this exact order:

1. Create patch dir + file. The patch directory MUST match the full version string exactly - never the parent version.
   Correct:
New-Item -ItemType Directory -Force -Path "D:\AI\MiniCodex\patches{version}"
New-Item -ItemType File -Path "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1" -force

text
Wrong (do not do this): putting patch_0.5.6a.1c.ps1 into patches\0.5.6a\ instead of patches\0.5.6a.1c\.

2. Run the patch:
powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1"

text

3. If a build/test run is needed:
dotnet run --project "D:\AI\MiniCodex\src\MiniCodex.App\MiniCodex.App.csproj"

text

The entire .ps1 content MUST be emitted inside a single fenced text code block (no markdown inside), so the user can copy-paste it verbatim.

Rationale: keeps friction at zero; avoids path typos; one block = one paste.

### 10.7 Escaping in replacement strings (learned 2026-11-15)

Never put `\"` inside a double-quoted PowerShell string. PS 5.1 treats backslash as a literal character; the `"` closes the string; the call is parsed into multiple positional args; Replace-Exact receives garbage in $old/$new/$tag. Symptom: log line `replace-exact OK: <garbage>` where $tag was never passed.

Rule: any replacement payload containing `"` (C# string literals, JSON, etc.) MUST use a single-quoted here-string `@'...'@` and literal `.Replace($old, $new)`.

### 10.8 Cyrillic in .ps1 (re-learned 2026-11-15)

Beyond BOM/ASCII-only: do NOT embed Cyrillic literals as Replace-Exact anchors. Get-Content -Encoding UTF8 on the target returns correct UTF-8 strings, but PS 5.1 without BOM parses the .ps1 source as CP1251, so the anchor inside the here-string is mojibake and never matches (matched 0 times).

Safe pattern:
- ASCII-only anchors (`"AssetType"`, `"Status"`, `},`) located via IndexOf / LastIndexOf.
- Cyrillic payload via \uXXXX escapes + [regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', $MatchEvaluator) - .ps1 stays ASCII, inserted text is real Cyrillic.
- After writing .json, ALWAYS verify with Get-Content -Raw | ConvertFrom-Json.

### 10.9 Silent-failure symptom (learned 2026-11-15)

If running a patch via powershell -File produces ZERO output (not even the "=== MiniCodex patch X ===" banner), the .ps1 file was empty at run time. Always verify file size > 2 KB before running:
(Get-Item "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1").Length

text
If size is 0, re-paste the script content from chat into the file, then run.

---

## 11. Known limitations (v0.1.2-accepted)

- Search: SQLite LIKE is case-sensitive for Cyrillic. English is fine (default). Fix: COLLATE NOCASE or LOWER() - deferred.
- 3D renderer: software, ~50-100ms per frame at 480x480 on 100k triangles. No LOD.
- Windows-only.
- Tag hierarchy in UI: works for filtering, but tag rename/delete does not auto-merge children.
- Right-click on an unselected tag also selects it (Avalonia TreeView default) -> filter applies before the context menu opens. Works fine but unexpected; if it becomes a nuisance, handle ContextRequested with e.Handled = true (deferred).
- Fullscreen image viewer: no zoom/pan, no rotation, no EXIF orientation.
- "Replace" re-imports the file as a new Asset row (old thumbnail stays in cache; harmless).
- Save Filter dialog: name only, no rename. Re-saving with the same name overwrites (upsert).
- Amber highlighting on status buttons uses Classes.statusActive with bool binding - works on current Avalonia 11.2.3.

---

## 12. Open questions for product owner (user)

- Screenshots for README (already exist in docs/screenshots/, verify render on GitHub).
- GitHub repo URL and author name for About screen: https://github.com/SantidioEsanti/MiniCodex, Santidio Esanti.
- Boosty link for "Support the author" button (not yet added).
- Should MinLambert slider also affect library tile previews? (Currently only card 3D viewer.)

---

## 13. Next step - v0.1.3 Release

Prerequisites (already done):
- build-release.ps1 at project root.
- README.md with 5 screenshot references.
- AssemblyName=MiniCodex (exe name), Version 0.1.3, InformationalVersion 0.1.3.
- CHANGELOG.md has [0.1.3] section.
- Screenshots must be saved in docs/screenshots/ with names 01..05.

Release steps:
1. `powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"`
   -> dist/MiniCodex-v0.1.3-win-x64.zip
2. Verify by extracting on clean Windows x64, running MiniCodex.exe.
3. git add . && git commit -m "Release v0.1.3: Associated files viewer, multi-select, collection colors"
4. git tag -a v0.1.3 -m "MiniCodex v0.1.3"
5. git push origin master && git push origin v0.1.3
6. GitHub Release: tag v0.1.3, pre-release flag, attach zip.

---

## 14. Session 2026-11-14 - v0.1.2 features (0.5.2a..0.5.5)

### 14.1 What was added
- **0.5.2a** backend: SmartCollectionFilter DTO (Core.Models), ICollectionService + CollectionService (Core.Services), ITagService.SetColorAsync, AppServices.CollectionService wiring, CollectionServiceTests (5 tests). Tests 50 -> 55.
- **0.5.2b** ViewModels: CollectionRow.cs; TagNodeViewModel gains Color/ColorBrush/HasColor/static Palette (8 hex)/SetColorCommand/ClearColorCommand/OnColorChange; LibraryViewModel gains Collections/SelectedCollection/commands/LoadCollectionsAsync/SaveCurrentFilterAsync/DeleteCollectionAsync/ChangeTagColorAsync/ApplyCollectionAsync/FindTagById and 7th optional ICollectionService ctor param; MainWindowViewModel passes AppServices.CollectionService.
- **0.5.2c** UI: LibraryView.axaml Collections section (header + delete button + ListBox) under the tag tree; per-tag color dot + 8-swatch context menu + Clear in TreeDataTemplate; Save filter button in toolbar. TagNodeViewModel.ClearColorLabel. lang/en.json + lang/ru.json +5 keys each.
- **0.5.2d** Save Filter dialog: LibraryViewModel.ShowSaveFilterDialog/NewCollectionName/ConfirmSaveFilterCommand/CancelSaveFilterCommand/OpenSaveFilterDialog/ConfirmSaveFilterAsync/CancelSaveFilter; LibraryView.axaml overlay dialog; lang +4 keys per file; HANDOFF lesson 11.
- **0.5.3a** backend: ITagService.RenameAsync/DeleteAsync, TagService implementations, IModelTagRepository.RemoveAllForTagAsync, ModelTagRepository implementation, TagCrudTests (5 tests). Tests 55 -> 60.
- **0.5.3a.1** test fix: TagCrudTests.DeleteAsync_RemovesTagAndAssociations seeded real Model rows via ModelRepository.UpsertAsync before ModelTag.AddAsync (FK constraint under PRAGMA foreign_keys = ON).
- **0.5.3b** UI: TagNodeViewModel OnRename/OnDelete callbacks + RenameCommand/DeleteCommand + RenameLabel/DeleteLabel + RefreshLocalized; LibraryViewModel rename/delete dialog state + 4 commands + wire in LoadTagsAsync; LibraryView.axaml 2 MenuItem in ContextMenu + 2 modal overlays; lang +10 keys.
- **0.5.3b.1** UI fix: ContextMenu moved from TextBlock to root Grid; Border color swatches (16x16) instead of hex text.
- **0.5.3b.2** UI fix: TreeViewItem has no HorizontalContentAlignment in Avalonia 11; use Style Selector="TreeViewItem /template/ ContentPresenter#PART_HeaderPresenter" with HorizontalAlignment + HorizontalContentAlignment = Stretch. Makes the whole row stretch, so right-click works anywhere on the highlighted row.
- **0.5.3b.3** UX: IsDefault/IsCancel on all dialog buttons (ScanWarning, SaveFilter, RenameTag, DeleteTag).
- **0.5.3b.4** UX fix: IsDefault/IsCancel are unreliable when focus is inside a TextBox. Added Panel.KeyBindings: Enter -> ConfirmRenameTagCommand, Escape -> CancelRenameTagCommand.
- **0.5.3c** Custom color picker: TagNodeViewModel.CustomColorCommand + CustomColorLabel + OnCustomColor callback; LibraryViewModel ShowColorPickerDialog/NewTagColor/ColorPreviewBrush/4 strings/2 commands/3 methods; LibraryView.axaml Custom Color menu item + ColorPicker overlay + KeyBindings for Enter/Esc; lang TagContextMenu.CustomColor + ColorPickerDialog.*.
- **0.5.3c.1** JSON fix: en.json "CustomColor" was inserted in the wrong block (Common instead of TagContextMenu). Fixed en.json; ru.json update failed because Replace-Exact anchor did not match.
- **0.5.3c.2** JSON fix: line-based insertion for ru.json (TagContextMenu.CustomColor + ColorPickerDialog.*). en.json verified.
- **0.5.4** Release prep: MiniCodex.App.csproj Version 0.1.1 -> 0.1.2, InformationalVersion 0.1.2, CHANGELOG.md [0.1.2] section prepended.
- **0.5.5** HANDOFF.md rewrite (this file).

### 14.2 SmartCollectionFilter format
JSON: {"Search":"...","TagId":"...","TagName":"..."}. Stored in Collection.filter_query; Collection.is_smart = 1. CollectionService.DeserializeFilter is null-safe and returns SmartCollectionFilter.Empty on bad JSON. SaveSmartAsync matches existing by name OrdinalIgnoreCase -> upsert.

### 14.3 Known limitations of the 0.5.2/0.5.3 series
- Tag color picker: 8 fixed presets + custom HEX dialog. No color wheel / opacity.
- Smart Collection stores single TagId. Filtering by a parent tag already includes descendants (LibraryViewModel.FilterTagIds uses GetDescendantIds), so subtree filtering works via parent tag.
- Tag rename does not merge same-named tags; TagService.RenameAsync blindly renames.
- Right-click on an unselected tag also selects it (Avalonia TreeView default) -> filter applies before the context menu opens.
- Rename/Delete commands on tag node use OnRename/OnDelete callbacks wired in LoadTagsAsync; if LoadTagsAsync is called during an in-flight dialog, the target object is stale (shows "target gone" silently).

### 14.4 Next steps
1. v0.1.2 release (section 13).
2. Deferred to 0.5.x/v1.1: tag rename does not auto-merge children; custom collection color; bulk tag editing; multi-select grid; printer bed fit check; archives (ZIP/RAR/7Z).
3. Deferred to v1.2: real 3D rotation in grid; composite model merge; WebP cache.

<!-- patch 0.5.5 applied -->

## 15. Session 2026-11-15 - v0.1.3 features (0.5.6a..0.5.6c.1b)

### 15.1 What was added
- **0.5.6a.1** backend+VM: AssetRowViewModel gains callbacks (open/open-external/open-in-explorer/copy-path/replace), IsImage/IsDocument/IsProfile/AssetIconGlyph, FullBitmap + LoadFullBitmapAsync(cap) via Bitmap.DecodeToWidth. ModelCardPageViewModel gains OtherAssets + HasOtherAssets, fullscreen state (IsFullScreenOpen/FullScreenBitmap/FullScreenTitle/NextAssetCommand/PrevAssetCommand), OpenExternalAsync/OpenInExplorerAsync/CopyPathAsync, remove-confirm dialog (ShowRemoveAssetConfirm/ConfirmRemoveAssetCommand/CancelRemoveAssetCommand), ReplaceRequested event + ReplaceAssetAsync. AssetService.ImportAsync dedup by original basename.
- **0.5.6a.2** UI: ModelCardView.axaml - fullscreen overlay (Border #E0000000, Focusable Grid with KeyBindings for Escape/Left/Right), ContextMenu on every thumbnail (Reference/Photo/Other), third "Other" section (128x128). Content grid hidden when IsFullScreenOpen (prevents Skia 3D viewer overdraw). Code-behind: ReplaceRequested -> file picker -> ReplaceAssetAsync.
- **0.5.6a.2b** fixes: PointerPressed on thumbnail opens fullscreen; remove-asset confirmation overlay (was missing in 0.5.6a.2).
- **0.5.6a.2c** UX: open-on-double-click instead of single-click.
- **0.5.6b.1** backend: ModelCardViewModel.IsSelected; LibraryViewModel SelectedCards + GroupTagCandidates, SelectedCount/HasSelection/IsMultiSelection, OnCardClicked(card,ctrl,shift), ClearSelection/SelectAllVisible/RefreshSelectionCollections; group commands (Add tag / Remove with confirmation / Copy paths / Find duplicates in selection); group dialog state.
- **0.5.6b.2** UI: rubber band on WrapPanel (Canvas overlay), Ctrl/Shift/plain click, group toolbar (visible when IsMultiSelection), amber border (#E67E22) on IsSelected, Esc + Ctrl+A KeyBindings, group dialogs (AutoCompleteBox for tag, red confirm for remove). Code-behind: OnCardsPointerPressed/Moved/Released, double-click detection (400ms), right-click selection sync.
- **0.5.6c** backend: Migration 0005 Collection.color; Entities.Collection.Color; ICollectionService.SetColorAsync; CollectionService.SetColorAsync; CollectionRepository upsert+map color (FieldCount>4 guard); CollectionRow rewrite (INotifyPropertyChanged, Color/ColorBrush/HasColor/Palette/SetColorCommand/ClearColorCommand/OnColorChange). LibraryViewModel: _tagDirectUsage dict, DeleteTagDialog breakdown (direct vs subtree), LoadCollectionsAsync wires OnColorChange, ChangeCollectionColorAsync. ModelCardPageViewModel: TagCandidates + RefreshTagCandidatesAsync.
- **0.5.6c** UI: LibraryView collections ListBox color dot + context menu (8 swatches + Clear); ModelCardView AutoCompleteBox for Add tag.
- **0.5.6c.1** fix: 0.5.6c STEP 9e detection was too loose (matched lambda reference), ChangeCollectionColorAsync was never inserted. Strict detection; STEP 10-15 re-executed.
- **0.5.6c.1b** fix: ru.json DeleteTagDialog.Message base64 anchor decoded to ":  <russian>" (missing the "Message" key name). Line-based ASCII anchors + [char] codes.
- **0.5.7** release prep: csproj Version 0.1.2 -> 0.1.3, InformationalVersion 0.1.3, CHANGELOG [0.1.3] section, HANDOFF sync (this update).
- **0.5.7.1** fix: 0.5.7 STEP 4 anchor for section 2 was copied from section 8 (had "- [x] " prefix and did not exist in section 2). Rewritten with correct anchor (Tag management + Single-instance lock).

### 15.2 Deferred to v0.1.4+ / v1.x
- Group "Add to collection" (needs manual-collection type - Collection is currently smart-filter-only).
- Edit filter after saving a collection.
- Multi-tag filter (AND/OR) - SmartCollectionFilter is single TagId.
- Merge same-name tags on rename (deliberately not auto-merged).
- Collection sort (drag-drop or explicit sort_order column).
- Collection count badge in sidebar (needs async count + cache).

### 15.3 Known limitations accepted in v0.1.3
- Fullscreen viewer: no zoom/pan, no rotation, no EXIF orientation. Image decoded as-is with 3840px cap.
- "Replace" removes old asset + imports new one as a separate Asset row; old thumbnail stays in cache (harmless).
- Rubber band uses intersection (any touch counts); Ctrl held = additive.
- Right-click on a non-selected card: resets selection to that card, then shows its context menu. Right-click on a selected card at multi-select keeps selection.
- AutoCompleteBox shows all existing tags (no prefix filtering tuning).
- Group dialogs are modal overlays (not separate windows) - Esc cancels the open dialog only.

<!-- patch 0.5.7 applied -->