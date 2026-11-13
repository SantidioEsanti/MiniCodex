#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3z2 - Rewrite docs/HANDOFF.md (control point for new dialogue).
.DESCRIPTION
    Replaces docs/HANDOFF.md with current state after ~50 patches.
    Content: quick start, state, files, architecture, DB, stack, features,
    deferred, patch workflow (updated rules), known limitations, next step.
    ASCII-only, single here-string.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3z2'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel"
}

$handoff = @'
# HANDOFF - MiniCodex

**Document version:** 2.0 (after ~50 patches)
**Last updated:** 2026-11-12
**Current version:** 0.4.3z2 (pre-release)
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

End of HANDOFF.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $handoffPath = Join-Path $ProjectRoot 'docs\HANDOFF.md'
    Backup-File $handoffPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    [IO.File]::WriteAllText($handoffPath, $handoff, [Text.UTF8Encoding]::new($false))
    Write-Log 'updated: docs\HANDOFF.md (rewritten to v2.0, English, ASCII)'

    # Verify basic structure
    $verify = [IO.File]::ReadAllText($handoffPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('Quick start section', ($verify -match '## 1\. Quick start')),
        @('Patch workflow section', ($verify -match '## 10\. Patch workflow')),
        @('Hard-won lessons', ($verify -match 'HARD-WON LESSONS')),
        @('Next step 0.4.4', ($verify -match '0\.4\.4 - Release'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }
    Write-Log ("HANDOFF size: {0} bytes, {1} lines" -f (Get-Item -LiteralPath $handoffPath).Length, (Get-Content -LiteralPath $handoffPath).Count)

    # README patch
    $readme = @'
# Patch 0.4.3z2 - Rewrite docs/HANDOFF.md

**Iteration:** 0.4

## What it does

Replaces docs/HANDOFF.md with v2.0 - current state after ~50 patches.
English, ASCII-only (AI-readable, no parsing risk).

## Contents
1. Quick start
2. Project state
3. Fixed decisions
4. File structure (actual)
5. Architecture
6. Database schema
7. Tech stack (versions)
8. Features working (checklist)
9. Deferred to v1.1+
10. Patch workflow (10 rules, including 8 hard-won lessons)
11. Known limitations
12. Open questions for product owner
13. Next step (0.4.4 Release)

## DoD
- docs/HANDOFF.md rewritten (~380 lines).
- Verify checks OK in log.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3z2\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3z2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3z2] - 2026-11-12`r`n`r`n### Changed`r`n- docs/HANDOFF.md rewritten to v2.0 (English, ASCII, full project state after ~50 patches).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3z1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}