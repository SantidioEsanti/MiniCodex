# HANDOFF - MiniCodex

**Document version:** 2.2 (after ~66 patches, post-release)
**Last updated:** 2026-11-13
**Current version:** v0.1.0-alpha (PUBLISHED 2026-11-13)
**Purpose:** Context transfer for a new AI dialogue to continue development.

---

## 1. Quick start (read this first)

If you are an AI picking up this project in a new dialogue:

1. Read this document fully.
2. Project state: MVP is functionally complete except packaging/release.
3. Next step is **0.4.4 (release)**: build portable zip + GitHub Release v0.1.0-alpha.
4. Do NOT re-architect. Code is stable, all 48 tests pass, 0 warnings.
5. All changes go through **patch scripts** (see section 10). No direct edits in src/.
6. Before writing any .ps1 patch, read section 10 carefully - it lists 8 hard-won lessons.

---

## 2. Project state

- **Name:** MiniCodex (working title, accepted).
- **Version:** 0.4.3z2 pre-release. v0.1.0-alpha release is the next step.
- **Platform:** Windows x64 desktop only (uses Registry, Explorer, Segoe Fluent Icons).
- **Distribution:** Portable (zip, no install, no admin rights).
- **Licence:** MIT.
- **Repository:** GitHub (not yet created; will be in 0.4.4).
- **Monetization:** None. Optional "Support the author" link (Boosty) in About screen.
- **Patch count:** ~50 patches since 0.1.0 (see patches/0.1.0 ... 0.4.3z2).
- **Tests:** 48 passing. **Build:** 0 errors, 0 warnings.

### What is fully implemented

- Library screen: cards grid with soft shadows, rounded corners, distinct card background per theme (light grey window / white card, dark #1A1A1A / #252525), hover metadata strip (size, polygons, file count), rotation on horizontal hover (4 angles), context menu (Open card, Copy path, Add tag, Show in folder, To slicer, To editor, Remove from library), More (...) button, double-click to open card.
- Scan folders: recursive, incremental by (path + size + last_write_time), progress bar, cancel, skips unavailable folders. Files on disk are never touched by removal (DB only).
- Preview generation: 4 angles (180/270/0/90 yaw, pitch 15), PNG cache in data/cache/previews/{modelId}/, invalidation by source_updated_at + RendererVersion + baseOrientation offset.
- 3D viewer on card: drag to rotate (yaw/pitch), mouse wheel to zoom, wireframe toggle, MinLambert slider (shadow softness), theme-aware background, save/load orientation per model, "Regenerate previews" button that auto-refreshes library tile.
- Model card layout: left column = 3D viewer (auto-fills vertical space) + compact Info panel below; right column = tabs.
- Info panel: Title/Author/Source URL as watermark-only text fields; Status as 3 icon buttons (planned/printed/painted, auto-save on click, toggle); Difficulty as 5 stars (auto-save, click same value to reset).
- Files tab: list of model files with primary radio button.
- Associations tab (default open): Reference (top) and Photo (bottom) as two stacked elevated sections with drag-drop, Add file button, 256x256 thumbnails, remove (x) overlay.
- Tags tab: create-or-get, add/remove, flat hierarchy in UI (DB has parent_id, not used).
- Scale tab: prototype type filter (figure/vehicle/building/ship/any), 43 presets in 7 categories, manual input (1:24, 24, 1/24, 1:35.5), bidirectional auto-calc (real height <-> model height), saves RealHeightMm/ModelHeightMm/ScaleRatio.
- Notes tab: multiline text.
- Search: name/author/source_url/tag name, debounced 200ms, Ctrl+F focus.
- Tag sidebar: usage counts, click to filter, "All models" first.
- Integrations: 12 apps (Bambu Studio, PrusaSlicer, OrcaSlicer, UltiMaker Cura, Lychee, CHITUBOX, Anycubic Slicer, Anycubic Slicer Next, Blender, ZBrush, 3D-Coat, Meshmixer). Auto-detect via common paths + Uninstall registry keys. Manual override via Settings screen (Browse / Clear / Re-detect). Launch with file argument from card.
- Settings screen: integration list with status (Auto / Manual / Not found).
- Themes: light/dark/auto, amber accent #E67E22 for selection/focus/tab underline/checkboxes/sliders. Window background distinct from card background.
- Localization: RU + EN, autodetect by system locale, fallback to EN. All strings in lang/*.json.
- Portable data dir: data/library.db, data/cache/previews/, data/cache/asset-thumbs/, data/assets/.

---

## 3. Fixed project decisions

| Parameter | Value |
|---|---|
| Name | MiniCodex |
| Platform | Windows (desktop) x64 |
| Stack | .NET 8 + Avalonia UI 11 |
| Rendering | SkiaSharp (CPU, software rasterizer) |
| Mesh parsing | AssimpNet + own wrappers |
| DB | SQLite (Microsoft.Data.Sqlite) |
| Licence | MIT |
| Release | GitHub (first: pre-release v0.1.0-alpha) |
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
- README.md - project positioning (needs screenshots before release)
- CHANGELOG.md - version history
- docs/
  - HANDOFF.md (this file)
  - ROADMAP.md (MVP roadmap, historical)
  - ARCHITECTURE.md (ADR)
  - DB_SCHEMA.md (schema)
  - UI_UX.md (screens)
  - SCALES.md (scale presets)
- lang/
  - en.json
  - ru.json
- patches/ (each patch: patch_X.ps1 + README.md + patch.log)
  - 0.1.0 ... 0.4.3z2
- backups/ (auto-created, {version}_{timestamp}/)
- dist/ (built zips)
- src/
  - MiniCodex.sln
  - MiniCodex.App/ (Avalonia UI)
    - App.axaml(.cs) - theme dictionaries, styles, DataTemplates
    - Program.cs - WithInterFont
    - AppServices.cs - composition root
    - Assets/ - icon.ico, Icon.png
    - Services/ - AppPaths, LocalizationService, ThemeService, FileSystemHelper, WindowsRegistryProbe
    - ViewModels/ - MainWindow, Library, ModelCard, ModelCardPage, Settings, IntegrationAppRow, ModelFileRow, AssetRow, TagRow, RelayCommand
    - Views/ - MainWindow, LibraryView, ModelCardTile, ModelCardView, ThreeDViewer, SettingsView
  - MiniCodex.Core/ (business logic, no UI/Data/Render deps)
    - Models/ - Entities (Model, ModelFile, Asset, Tag, Collection), MeshInfo, MeshGeometry, ScalePreset, ModelOrientation, TagWithUsage, IntegrationApp
    - Repositories/ - IRepositories (IModel, IModelFile, IAsset, ITag, IModelTag, ICollection, ISetting), IModelTagRepository
    - Services/ - IMeshLoader, IMeshGeometryLoader, IPreviewRenderer, IPreviewGenerator, PreviewGenerator, PreviewGeneratorOptions, RenderStyle, IScannerService, ScannerService, ScanProgress, IAssetService, AssetService, IAssetThumbnailGenerator, ITagService, TagService, IIntegrationProbe, IIntegrationService, IntegrationService, IntegrationCatalog, ScaleCatalog
  - MiniCodex.Data/ (SQLite)
    - SqliteConnectionFactory.cs
    - MigrationRunner.cs
    - DatabaseInitializer.cs
    - Migrations/ - IMigration, Migration_0001_InitialSchema, Migration_0002_ModelFile_LastWriteTime, Migration_0003_ModelOrientation
    - Repositories/ - ModelRepository, ModelFileRepository, AssetRepository, TagRepository, ModelTagRepository, CollectionRepository, SettingRepository
  - MiniCodex.Render/ (3D and images, depends on Core)
    - Loaders/ - AssimpMeshLoader (implements IMeshLoader + IMeshGeometryLoader)
    - Rendering/ - SkiaPreviewRenderer (CPU rasterizer with Z-buffer, wireframe), SkiaThumbnailGenerator
  - MiniCodex.Tests/ (xUnit)
    - DatabaseInitializerTests, AssetServiceTests, TagServiceTests, SearchServiceTests, ScannerServiceTests, PreviewGeneratorTests, MeshLoaderTests, PreviewRendererTests, IntegrationServiceTests, ScaleCatalogTests

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

Localization:
- lang/{en,ru}.json, loaded at startup, autodetect via CultureInfo.CurrentUICulture, fallback EN.
- Keys use PascalCase.Category.Subkey.
- UI strings via App.Loc.Get(key) or computed properties in ViewModels.

---

## 6. Database schema

SQLite, file at data/library.db. Migrations applied at startup (idempotent).

Tables:
- Model (id TEXT PK, title, author, source_url, model_type, primary_model_file_id, status, difficulty INTEGER, real_height_mm REAL, model_height_mm REAL, scale_ratio, notes, orientation_json, created_at, updated_at)
- ModelFile (id TEXT PK, model_id TEXT FK, path, file_role, part_name, file_size_bytes INTEGER, polygon_count INTEGER, last_write_time_utc)
- Asset (id TEXT PK, model_id TEXT FK, asset_type, absolute_path, thumbnail_path, sort_order INTEGER, storage_mode)
- Tag (id TEXT PK, name, parent_id, color)
- ModelTag (model_id, tag_id, PRIMARY KEY)
- Collection (id TEXT PK, name, filter_query, is_smart INTEGER)
- Setting (key TEXT PK, value TEXT)

Migrations (in MiniCodex.Data/Migrations):
1. Initial schema (all tables above).
2. Add last_write_time_utc to ModelFile.
3. Add orientation_json to Model.

Enums (strings in DB):
- Model.status: planned | printed | painted
- Model.model_type: single | split | multipart | diorama | variant_set
- ModelFile.file_role: main | part | presupported | hollowed | variant | accessory
- Asset.asset_type: reference | render | photo | document | profile
- Asset.storage_mode: hybrid | adjacent | central | restructure

Note: orientation_json is {yaw: float, pitch: float}. Default (180, 15). Absolute values from viewer.

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
- AllowUnsafeBlocks=true

MiniCodex.Data.csproj:
- Microsoft.Data.Sqlite 8.0.10

MiniCodex.Tests.csproj:
- Microsoft.NET.Test.Sdk 17.11.1
- xunit 2.9.2
- xunit.runner.visualstudio 2.8.2

SDK: .NET 8 (targets net8.0), but builds fine with .NET 9 SDK (9.0.318).

---

## 8. Features working (checklist)

- [x] Portable data dir, first-run creates data/
- [x] RU/EN localization, autodetect, fallback EN
- [x] Themes light/dark/auto, amber accent
- [x] Inter font with Segoe UI fallback
- [x] Library grid: cards, soft shadow, hover metadata, 4-angle rotation on hover, context menu, More button, double-click open
- [x] Scan folders: incremental, progress, cancel, unavailable-folder handling
- [x] Preview cache: 4 angles PNG, invalidation by (source_updated_at, renderer_version, base orientation)
- [x] 3D viewer: drag rotate, zoom, wireframe, MinLambert slider, theme-aware bg
- [x] Model card layout: viewer + Info left, tabs right
- [x] Info auto-save for Status/Difficulty (no UpdatedAt change)
- [x] Status: 3 icon buttons (planned/printed/painted), toggle
- [x] Difficulty: 5 stars, toggle
- [x] Associations: Reference/Photo stacked, drag-drop, Add file, 256x256 thumbs, remove
- [x] Tags: create-or-get, add/remove, flat UI (parent_id in DB, not used)
- [x] Search: name/author/source_url/tag, debounce, Ctrl+F
- [x] Tag sidebar with usage counts
- [x] Scale converter: 43 presets in 7 categories, prototype filter, manual input, bidirectional auto-calc, save/load
- [x] Integrations: 12 apps, auto-detect via paths + registry, manual override, launch with file
- [x] Settings: integrations list, Re-detect, Browse, Clear
- [x] Orientation: save/load per model, Regenerate previews, auto-refresh library tile
- [x] Info panel compact: watermarks, inline status/difficulty labels
- [x] Viewer auto-fills vertical space
- [x] Images in Reference/Photo clipped to rounded corners

---

## 9. Deferred to v1.1+ (out of MVP)

- ZIP/RAR/7Z archives
- Duplicate detection by geometry
- Printer bed fit check (based on printer profiles)
- Real 3D rotation in library grid (only 4 static angles)
- Bulk tag editing
- Auto-tags from filename/folder
- Adjacent storage mode (assets next to model file)
- Composite model merge (parts -> single preview)
- WebP cache (PNG works)
- Tag hierarchy in UI (parent_id exists in DB)
- Tag color picker UI (color field exists in DB)
- Display render/document/profile associations (stored in DB but hidden)
- Grid virtualization (WrapPanel in ScrollViewer not virtualized; ok for <1000)
- Del key for card deletion (needs selection model)
- Multi-select in grid
- macOS/Linux support (Windows-only: Registry, Explorer, Segoe Fluent Icons)
- Toast notifications (currently status text)
- Mica/Acrylic window background
- Wildcard paths in IntegrationCatalog (e.g. "Cura 5.*")

---

## 10. Patch workflow - CRITICAL

All changes after 0.1.0 go through patch scripts. Direct edits in src/ forbidden.

### 10.1 Location and naming

D:\AI\MiniCodex\patches\{MAJOR}.{MINOR}.{PATCH}\patch_{MAJOR}.{MINOR}.{PATCH}.ps1
Alongside: README.md describing what/why/files affected.

Version format: MAJOR.MINOR.PATCH
- MAJOR = 0 (pre-release), 1 after stable release
- MINOR = iteration number (1=foundation, 2=scanning, 3=card, 4=integrations/release)
- PATCH = sequential number within iteration, starts at 0
- Suffixes like "a", "b", ".1" used for fixes (0.4.3g.1, 0.4.3z1)

### 10.2 Mandatory script contract

1. Backup affected files to backups/{version}_{YYYYMMDD_HHMMSS}/ FIRST.
2. Be idempotent (repeat run does not break state).
3. Log to console + patches/{version}/patch.log (UTF-8).
4. On error: report, print backup path, suggest restore command. NO auto-rollback.
5. Update CHANGELOG.md at end (with marker <!-- patch X applied -->).

### 10.3 Run command (always)

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\{version}\patch_{version}.ps1"

If patch contains Cyrillic, prepend BOM fix:
$p='D:\...\patch_X.ps1'; if (Test-Path $p) { $c=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($true)) }; powershell -ExecutionPolicy Bypass -File $p

### 10.4 HARD-WON LESSONS (read these, they prevent lost hours)

1. **ASCII-only .ps1** - the safest form. Do not put Cyrillic, "..." (U+2026), em-dash, guillemets, or any non-ASCII characters in .ps1. PS 5.1 reads .ps1 without BOM as CP1251, so UTF-8 bytes get misinterpreted and the parser breaks unpredictably.
   - For Russian strings inside patch, encode with [char] codes: -join ((0x041F,0x0440,...) | % {[char]$_})
   - Or use base64: [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('...'))
   - Or use C# string escapes: "\u041F\u0440..." in C# content

2. **BOM required if any non-ASCII in .ps1** - prepend the BOM fix command to the run line. Without BOM, PS 5.1 fails with "Missing }" / "Try without Catch" (misleading errors).

3. **No here-strings with indented closer** - '@ or "@ must be at column 0, NO leading spaces. An indented closer is not recognized, the parser eats the rest of the file.

4. **Remove-Item in pipeline hangs** - PS 5.1 does not bind FileInfo from pipeline to Path. Always use foreach + Remove-Item -LiteralPath $f.FullName -Force inside loop. Never:
   Get-ChildItem ... | Remove-Item -Force

5. **Avalonia XAML: DragOver/Drop are attached events** - attribute names must be DragDrop.DragOver="..." DragDrop.Drop="...". Bare DragOver="..." gives AVLN2000.

6. **Avalonia StackPanel has no Padding** - Padding is on Border / Decorator. Move Padding to parent Border. AVLN2000 error otherwise.

7. **Unicode in XAML** - use XML character references: &#x22EF; (horizontal ellipsis), &#x00D7; (multiplication x for remove), &#xE823; (Segoe Fluent Icons clock). No raw Unicode needed.

8. **One patch = one logical step** - do not bundle core plumbing + full UI in a single script. Split: 0.4.2a (plumbing) then 0.4.2b (UI). Large scripts (>800 lines) risk truncation in transfer.

9. **Tree check** - use: cmd /c tree /F /A "D:\AI\MiniCodex" (full path in quotes).

10. **Event signatures in code-behind** - DragEventArgs for DragDrop.Drop and DragDrop.DragOver. Not RoutedEventArgs.

11. **String.Split(string) does not exist in PS 5.1** - it silently binds to Split(char[]), so "abc".Split("b") iterates chars and returns 3 pieces, not 2. For occurrence counting use: [regex]::Matches($text, [regex]::Escape($anchor)).Count. Symptom: "Anchor ambiguous (14782 occurrences)" for a 45-char string. Cost: one lost patch run in 0.5.2b. If you write a custom Replace-Exact helper (recommended), always validate anchor count == 1 before replacing.

### 10.5 Rollback

Manual only: copy files from backups/{version}_{timestamp}/ back into D:\AI\MiniCodex\.
Script on error prints restore command.

---

## 11. Known limitations (MVP-accepted)

- Search: SQLite LIKE is case-sensitive for Cyrillic. English is fine (default). Fix: COLLATE NOCASE or LOWER() - deferred.
- Tag hierarchy: parent_id exists in DB, UI is flat.
- Tag color: color field in DB, no UI picker.
- Render/document/profile assets: stored but not displayed in Associations tab.
- 3D renderer: software, ~50-100ms per frame at 480x480 on 100k triangles. Fine for MVP. No LOD.
- Thumbnails: original {assetId}.png (128px) deprecated; {assetId}_256.png (256px) in use. Old files cleaned best-effort in dev bin only. Portable release starts fresh.
- No multi-select in grid. Delete only via context menu.
- Windows-only.
- No single-instance lock (multiple launches compete for SQLite file).
- Amber highlighting on status buttons uses Classes.statusActive with bool binding - works on current Avalonia 11.2.3; if a future version changes it, use explicit Style triggers.

---

## 12. Open questions for product owner (user)

- Screenshots for README - needed before GitHub release.
- GitHub repo URL and author name for About screen.
- Boosty link for "Support the author" button.
- Should MinLambert slider also affect library tile previews? (Currently only card 3D viewer.)
- Do we want "Others" section in Associations for render/document/profile types? (Currently hidden.)

---

## 13. Next step

**0.4.4 - Release**

Tasks:
1. Set version = 0.1.0-alpha in csproj (or AssemblyVersion).
2. Add About screen (currently absent - just Author/Repo/Boosty link).
3. dotnet publish -c Release -r win-x64 --self-contained /p:PublishSingleFile=true -o dist/MiniCodex-win-x64.
4. Compress-Archive -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip.
5. Update README.md with screenshots and download link.
6. Create GitHub repo, push code, tag v0.1.0-alpha, create Release with zip attached.
7. Verify: download zip on a clean Windows x64, extract, run MiniCodex.exe, portable data/ is created, scan works.

After 0.4.4: end of MVP. Version 1.0.0 development depends on feedback.

---

## 14. Iteration 0.4.5 - Post-release stabilization (2026-11-12/13)

After 0.4.3z3 was usable, testing with 76 heavy models (1.5M polys each) revealed issues.
Iteration 0.4.5a1..a13.1 fixed them. All 48 tests still pass, 0 build warnings.

### 14.1 Logging (0.4.5a1, a2)

- Core/Logging/Log.cs - static file logger. Appends to data/logs/minicodex-{yyyyMMdd}.log
  (crash-safe: per-line File.AppendAllText with lock). Log.Info/Warn/Error/Exception/SessionEnd/MemoryMb.
- Program.Main wraps StartWithClassicDesktopLifetime in try/finally + global handlers:
  AppDomain.UnhandledException, TaskScheduler.UnobservedTaskException, Dispatcher.UIThread.UnhandledException.
- App.OnFrameworkInitializationCompleted restores DatabaseInitializer.InitializeAsync + AppServices.Init
  (lost in a1 refactor - caused silent no-op scanning until a2).
- ScannerService: per-file logging (FILE start/ok/fail with size, polys, took, mem).
- AssimpMeshLoader: all silent catches now log via Log.Exception.

### 14.2 Memory / OOM fixes (0.4.5a1, a3, a4)

Cause: LibraryViewModel launched 76 parallel Task.Run(LoadDetailsAsync) - each one spawned
an Assimp ImportFile of 1.5M poly -> 10+ GB native alloc -> "bad allocation".

Fixes:
- 0.4.5a1: removed PostProcessSteps.JoinIdenticalVertices (memory hog).
- 0.4.5a3: SemaphoreSlim(1,1) in LibraryViewModel - preview gen is serialized.
  PreviewGenerator: LoadGeometry once per model (was 4x), GC.Collect after each model.
  ScannerService: GC.Collect every 10 files.
- 0.4.5a4: preview progress in status bar ("Previews: X / Y"). IAsyncDisposable
  cancels pending preview tasks on detach (no duplicate parallel after nav).

### 14.3 Rendering fixes (0.4.5a5..a11, a13)

Many iterations to fix shading artifacts on dense meshes:
- a5: sub-pixel force-draw, supersample param in IPreviewRenderer.Render.
- a6: bbox fill (not just center pixel), degenerate triangles drawn with MinLambert,
  scale safety for collapsed bbox, SS=3 default.
- a7: two-sided lighting (MathF.Abs on lambert dot) - fixed STL winding sparkle.
- a8: ZBias on regular triangles (fixed z-fighting on bases/plinths), fill light.
- a9: sub-pixel uses max-z (front-most triangle wins), fill light always (no inversion).
- a10: file normals from Assimp mesh.Normals + Gouraud per-vertex lambert.
  Fixed flat grey on 1.5M+ poly models. ModelCardViewModel passes orientation offset.
- a11: fill light removed (single key light) - less "chrome", more contrast.
- a13: YawDegrees {220, 250, 280, 310} - 90deg span, 30deg per step.

### 14.4 UI polish (0.4.5a4, a12, a13)

- a4: preview progress in library status bar.
- a12: first-scan warning overlay (Setting "Scan.WarningShown"). Theme ComboBox
  replaced with icon button (sun/moon/contrast, Segoe Fluent Icons E706/E708/E7F4).
- a13: theme persisted in Setting "UI.Theme" (loaded sync in MainWindowViewModel ctor).
  Auto-save card fields Title/Author/SourceUrl/Notes/Scale (500ms debounce);
  Save button removed from toolbar. Library preview: no grey rectangle, rounded corners.

### 14.5 Version

0.4.5a13.1. 48 tests passing. 0 build warnings.

---

## 15. Next step - v0.1.0-alpha release

Prerequisites (already done):
- build-release.ps1 at project root.
- README.md with 5 screenshot references.
- AssemblyName=MiniCodex (exe name), Version 0.1.0, InformationalVersion 0.1.0-alpha.
- Screenshots must be saved in docs/screenshots/ with names 01..05 (see README.md).

Release steps:
1. `powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"`
   -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip
2. Verify by extracting on clean Windows x64, running MiniCodex.exe.
3. git init, git add ., git commit -m "MiniCodex v0.1.0-alpha".
4. Push to https://github.com/SantidioEsanti/MiniCodex
5. GitHub Release: tag v0.1.0-alpha, pre-release flag, attach zip.

### Known limitations (deferred to v0.1.1+)

- STL with layer-lines from 3D scanners still shows micro texture (spatial dedup for smoothing planned).
- No single-instance lock (multiple launches race on SQLite file).
- Grid not virtualized (WrapPanel in ScrollViewer; OK for <1000 cards).
- Drag-rotate during 3D drag renders at half resolution internally (~5 fps).
- Tag hierarchy flat in UI (parent_id in DB, unused).
- Tag color field unused (no picker UI).
- render/document/profile asset types stored but hidden from Associations tab.
- Multi-select in library not implemented (delete only via context menu).
- No Copy/Paste/Undo in notes/fields.

---

## 14. Iteration 0.4.5 - Post-release stabilization (2026-11-12/13)

After 0.4.3z3 was usable, testing with 76 heavy models (1.5M polys each) revealed issues.
Iteration 0.4.5a1..a13.1 fixed them. All 48 tests still pass, 0 build warnings.

### 14.1 Logging (0.4.5a1, a2)

- Core/Logging/Log.cs - static file logger. Appends to data/logs/minicodex-{yyyyMMdd}.log
  (crash-safe: per-line File.AppendAllText with lock). Log.Info/Warn/Error/Exception/SessionEnd/MemoryMb.
- Program.Main wraps StartWithClassicDesktopLifetime in try/finally + global handlers:
  AppDomain.UnhandledException, TaskScheduler.UnobservedTaskException, Dispatcher.UIThread.UnhandledException.
- App.OnFrameworkInitializationCompleted restores DatabaseInitializer.InitializeAsync + AppServices.Init
  (lost in a1 refactor - caused silent no-op scanning until a2).
- ScannerService: per-file logging (FILE start/ok/fail with size, polys, took, mem).
- AssimpMeshLoader: all silent catches now log via Log.Exception.

### 14.2 Memory / OOM fixes (0.4.5a1, a3, a4)

Cause: LibraryViewModel launched 76 parallel Task.Run(LoadDetailsAsync) - each one spawned
an Assimp ImportFile of 1.5M poly -> 10+ GB native alloc -> "bad allocation".

Fixes:
- 0.4.5a1: removed PostProcessSteps.JoinIdenticalVertices (memory hog).
- 0.4.5a3: SemaphoreSlim(1,1) in LibraryViewModel - preview gen is serialized.
  PreviewGenerator: LoadGeometry once per model (was 4x), GC.Collect after each model.
  ScannerService: GC.Collect every 10 files.
- 0.4.5a4: preview progress in status bar ("Previews: X / Y"). IAsyncDisposable
  cancels pending preview tasks on detach (no duplicate parallel after nav).

### 14.3 Rendering fixes (0.4.5a5..a11, a13)

Many iterations to fix shading artifacts on dense meshes:
- a5: sub-pixel force-draw, supersample param in IPreviewRenderer.Render.
- a6: bbox fill (not just center pixel), degenerate triangles drawn with MinLambert,
  scale safety for collapsed bbox, SS=3 default.
- a7: two-sided lighting (MathF.Abs on lambert dot) - fixed STL winding sparkle.
- a8: ZBias on regular triangles (fixed z-fighting on bases/plinths), fill light.
- a9: sub-pixel uses max-z (front-most triangle wins), fill light always (no inversion).
- a10: file normals from Assimp mesh.Normals + Gouraud per-vertex lambert.
  Fixed flat grey on 1.5M+ poly models. ModelCardViewModel passes orientation offset.
- a11: fill light removed (single key light) - less "chrome", more contrast.
- a13: YawDegrees {220, 250, 280, 310} - 90deg span, 30deg per step.

### 14.4 UI polish (0.4.5a4, a12, a13)

- a4: preview progress in library status bar.
- a12: first-scan warning overlay (Setting "Scan.WarningShown"). Theme ComboBox
  replaced with icon button (sun/moon/contrast, Segoe Fluent Icons E706/E708/E7F4).
- a13: theme persisted in Setting "UI.Theme" (loaded sync in MainWindowViewModel ctor).
  Auto-save card fields Title/Author/SourceUrl/Notes/Scale (500ms debounce);
  Save button removed from toolbar. Library preview: no grey rectangle, rounded corners.

### 14.5 Version

0.4.5a13.1. 48 tests passing. 0 build warnings.

---

## 15. Next step - v0.1.0-alpha release

Prerequisites (already done):
- build-release.ps1 at project root.
- README.md with 5 screenshot references.
- AssemblyName=MiniCodex (exe name), Version 0.1.0, InformationalVersion 0.1.0-alpha.
- Screenshots must be saved in docs/screenshots/ with names 01..05 (see README.md).

Release steps:
1. `powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"`
   -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip
2. Verify by extracting on clean Windows x64, running MiniCodex.exe.
3. git init, git add ., git commit -m "MiniCodex v0.1.0-alpha".
4. Push to https://github.com/SantidioEsanti/MiniCodex
5. GitHub Release: tag v0.1.0-alpha, pre-release flag, attach zip.

### Known limitations (deferred to v0.1.1+)

- STL with layer-lines from 3D scanners still shows micro texture (spatial dedup for smoothing planned).
- No single-instance lock (multiple launches race on SQLite file).
- Grid not virtualized (WrapPanel in ScrollViewer; OK for <1000 cards).
- Drag-rotate during 3D drag renders at half resolution internally (~5 fps).
- Tag hierarchy flat in UI (parent_id in DB, unused).
- Tag color field unused (no picker UI).
- render/document/profile asset types stored but hidden from Associations tab.
- Multi-select in library not implemented (delete only via context menu).
- No Copy/Paste/Undo in notes/fields.

---

## 16. Post-release state (2026-11-13)

MVP v0.1.0-alpha is PUBLISHED on GitHub.

- Release page: https://github.com/SantidioEsanti/MiniCodex/releases/tag/v0.1.0-alpha
- Repository: https://github.com/SantidioEsanti/MiniCodex (public, MIT license)
- Tag: v0.1.0-alpha (pre-release)
- Artifact: MiniCodex-v0.1.0-alpha-win-x64.zip (~42 MB zip, ~95 MB extracted)
- SHA-256: see Release description on GitHub
- CI: GitHub Actions build.yml succeeded on first push (green check on initial commit)
- Topics: 20 (3d-printing, 3d-models, miniatures, stl, 3mf, obj, 3d-model-manager,
  stl-library, 3d-viewer, scale-converter, slicer-integration, dotnet, avalonia,
  csharp, sqlite, windows, portable, desktop-app, catalog, hobby)
  - NOTE: 'object-detection' was added accidentally. Remove via repo Settings if desired.

### 16.1 Metrics at release

- 0 downloads, 0 stars, 0 forks, 0 watchers (as of 2026-11-13)
- No issues yet

### 16.2 First 48h checklist (post-release)

1. Verify README screenshots render correctly in browser (5 images in docs/screenshots/,
   named 01-library-light.png ... 05-settings-integrations.png).
   If broken -> rename SCR_*.png and push again.
2. Announce on Reddit (r/3Dprinting, r/PrintedMinis, r/minipainting),
   Boosty, relevant Telegram channels.
3. Monitor GitHub Issues, respond within 24h.
4. Track download counter on Release page (metric: <10 = repitch,
   10-50 = normal solo-MVP start, 50-200 = good reception, 200+ = prioritize v0.1.1).

### 16.3 v0.1.1 backlog (priority by expected user impact)

1. Spatial deduplication for 3D-scanned STL (smooth normals; layer-line artifacts
   remain on scanned meshes because normals are per-face or degenerate).
2. Grid virtualization (ItemsRepeater + UniformGridLayout) for 1000+ models.
   WrapPanel in ScrollViewer is not virtualized.
3. Single-instance lock (SQLite race when multiple launches).
4. Tag hierarchy in UI (Tag.parent_id already in DB, currently flat).
5. Custom icons for status (replace Unicode glyphs with SVG for consistent rendering).
6. If z-fighting resurfaces: per-face depth sorting or MSAA (currently zbias on
   regular triangles; sub-pixel path uses max-z without bias).

### 16.4 What is NOT in v0.1.0-alpha (see В§15 for full list)

- No archives (ZIP/RAR/7Z) - planned v1.1
- No duplicate geometry detection
- No printer bed fit check
- No multi-select in library grid
- render/document/profile asset types stored in DB but hidden from UI
- No tag color picker UI (Tag.color field unused)

### 16.5 Development workflow reminder for next session

- All changes through patch scripts (section 10).
- .ps1 = ASCII-only. If Cyrillic needed: BOM-fix prepend + here-strings closing
  marker at column 0 (no leading spaces), or use [char] codes, or base64.
- One patch = one logical step. Do NOT bundle plumbing + full UI rewrite.
- 48 tests must stay green after every patch. Build: 0 errors, 0 warnings.
- When changing an interface signature (e.g. IPreviewRenderer.Render, IPreviewGenerator),
  grep for Stub*/Fake*/Test*/Mock* implementations in MiniCodex.Tests - update them too
  (hard-won lesson from 0.3.0a, 0.4.5a1, 0.4.5a5.1).
- Next session: start by reading HANDOFF.md fully, then plan before patching.

End of HANDOFF.
---

## 17. Development state (2026-11-13 - post UI/3D updates)

### 17.1 UI Soft Glass (v0.5.0a1..a18)
- Implemented Glassmorphism UI (soft shadows, rounded corners, glass panels).
- Added gradient backgrounds for Light (warm white to soft lavender) and Dark (warm gray to graphite) themes.
- Moved design tokens (colors, shadows) into ThemeDictionaries for proper Light/Dark support.
- Known issue: Card grid margins are currently large (added for shadows). Needs optimization in future UI patches.

### 17.2 Spatial Deduplication (v0.5.1a1)
- Added MeshNormalSmoother in MiniCodex.Render.Rendering.
- Triggered for meshes with >500,000 triangles to weld vertices by spatial position (precision 1e-3) and average normals.
- Fixes "layer lines" on 3D-scanned STL models.
- Added unit tests (50 total now).

### 17.3 Next steps (v0.1.1 backlog)
1. Single-instance lock (Mutex) to prevent SQLite race conditions.
2. Grid virtualization (ItemsRepeater + UniformGridLayout) for 1000+ models.
3. Tag hierarchy in UI.

<!-- patch 0.5.1a2 applied -->
---

## 18. Post-release state v0.1.1 (2026-11-13)

### 18.1 UI Soft Glass (v0.5.0a1..a18, a28)
- Implemented Glassmorphism UI (soft shadows, rounded corners, glass panels).
- Added gradient backgrounds for Light (warm white to soft lavender) and Dark (warm gray to graphite) themes.
- Moved design tokens (colors, shadows) into ThemeDictionaries for proper Light/Dark support.
- Replaced Unicode status icons (Segoe Fluent Icons) with native StreamGeometry + PathIcon (Clock, 3D Printer, Brush).
- Reduced card margins (6,6,6,20) and shadow blur to increase grid density.

### 18.2 Critical Architecture Changes (v0.5.1a20..a27)
- **Virtualization Reverted:** We tried ItemsRepeater with UniformGridLayout (Avalonia 11.1.5), but it caused severe UI update bugs (cards disappearing, stuck filters). We reverted to stable ItemsControl + WrapPanel and a get-only ObservableCollection.
- **Singleton ViewModel:** LibraryViewModel is no longer disposed on navigation (DisposeAsync is a no-op). It must survive navigation to/from model cards.
- **Direct UI Updates:** Removed complex Dispatcher.InvokeAsync for collection replacement. Now Cards.Clear() + Cards.Add() is done directly, and ReloadModelsCoreAsync uses a SemaphoreSlim to prevent overlapping loads.

### 18.3 New Features (v0.5.1a33..a38)
- **Spatial Deduplication:** MeshNormalSmoother in MiniCodex.Render smooths normals for meshes with >500K triangles.
- **Duplicate Detection:** 
  - Migration_0004 adds ile_hash (SHA-256) to ModelFile.
  - ScannerService computes SHA-256 on scan for new/updated files.
  - ModelRepository.GetDuplicateModelIdsAsync() finds duplicates.
  - "Find duplicates" button added to Library toolbar.
- **Single-instance lock:** Named Mutex in Program.cs prevents multiple instances (protects SQLite).

### 18.4 Known Issues
- **First scan after v0.5.1a35:** If you didn't scan after the hash migration, the "Find duplicates" button will return an empty list until you scan folders again (to populate hashes).
- **Card margins:** We reduced them to 6,6,6,20, but some users may still find the grid sparse. Future optimization: use dynamic Margin based on viewport width.

### 18.5 Next steps (v1.1 backlog)
1. **Bed Fit Check:** Add model dimensions to DB, compare with printer bed size.
2. **Archives:** Support ZIP/RAR/7Z scanning.
3. **Tag color picker:** UI for Tag.color field.
4. **Multi-select:** In library grid.

<!-- patch 0.5.1a39 applied -->

---

## 19. Session 2026-11-13 evening - Smart Collections (v0.5.2a..d)

### 19.1 What was added
- **0.5.2a** backend: SmartCollectionFilter DTO (Core.Models), ICollectionService + CollectionService (Core.Services), ITagService.SetColorAsync, AppServices.CollectionService wiring, CollectionServiceTests (5 tests). Tests 50 -> 55.
- **0.5.2b** ViewModels: CollectionRow.cs; TagNodeViewModel gains Color/ColorBrush/HasColor/static Palette (8 hex)/SetColorCommand/ClearColorCommand/OnColorChange; LibraryViewModel gains Collections/SelectedCollection/commands/LoadCollectionsAsync/SaveCurrentFilterAsync/DeleteCollectionAsync/ChangeTagColorAsync/ApplyCollectionAsync/FindTagById and 7th optional ICollectionService ctor param; MainWindowViewModel passes AppServices.CollectionService.
- **0.5.2c** UI: LibraryView.axaml Collections section (header + delete button + ListBox) under the tag tree; per-tag color dot + 8-swatch context menu + Clear in TreeDataTemplate; Save filter button in toolbar. TagNodeViewModel.ClearColorLabel. lang/en.json + lang/ru.json +5 keys each.
- **0.5.2d** Save Filter dialog: LibraryViewModel.ShowSaveFilterDialog/NewCollectionName/ConfirmSaveFilterCommand/CancelSaveFilterCommand/OpenSaveFilterDialog/ConfirmSaveFilterAsync/CancelSaveFilter; LibraryView.axaml overlay dialog; lang +4 keys per file (SaveFilterDialog.Title/Placeholder/Save/Cancel); HANDOFF lesson 11 (String.Split) + this section.

### 19.2 SmartCollectionFilter format
JSON: {"Search":"...","TagId":"...","TagName":"..."}. Stored in Collection.filter_query; Collection.is_smart = 1. CollectionService.DeserializeFilter is null-safe and returns SmartCollectionFilter.Empty on bad JSON. SaveSmartAsync matches existing by name OrdinalIgnoreCase -> upsert (no duplicates by name).

### 19.3 Known limitations of the 0.5.2 series
- Tag color picker is a fixed 8-color palette (TagNodeViewModel.Palette). No custom hex input yet.
- Smart Collection stores single TagId, not subtree. Filtering by a parent tag already includes descendants (LibraryViewModel.FilterTagIds uses GetDescendantIds), so if the collection references a parent tag, subtree filtering works.
- Saving a filter while a collection is selected reads current UI state (_searchQuery/_selectedTag), not SelectedCollection.Filter. Re-saving with the same name overwrites (upsert).
- Right-click on an unselected tag also selects it (Avalonia default TreeView behavior) -> filter applies before the context menu opens. Works fine but unexpected; if it becomes a nuisance, handle ContextRequested with e.Handled = true (deferred to 0.5.3).

### 19.4 Next steps
1. v0.1.2 release if 55 tests green.
2. Deferred to 0.5.3: tag rename/delete UI, custom hex color picker, per-tag subtree saved as collection.
3. Deferred to v1.1: bulk tag editing, multi-select grid, printer bed fit check.