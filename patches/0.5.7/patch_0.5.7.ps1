# patch_0.5.7.ps1
# 0.5.7 - Release prep v0.1.3
#   csproj: Version 0.1.2 -> 0.1.3, InformationalVersion 0.1.2 -> 0.1.3.
#   CHANGELOG.md: prepend [0.1.3] - 2026-11-15 section.
#   HANDOFF.md: bump header (v3.1 / 2026-11-15 / v0.1.3), features list,
#     migrations (0005), Collection.color, remove deferred items now shipped,
#     remove stale limitations, remove resolved open question, rewrite §13
#     for v0.1.3 release, append §15 (Session 2026-11-15).
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.7\patch_0.5.7.ps1"

Write-Host "=== MiniCodex patch 0.5.7 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.7'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot ('patches\' + $version)
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir ('patch_' + $version + '.log')

if (-not (Test-Path $projectRoot)) { throw ("Project root not found: " + $projectRoot) }
New-Item -ItemType Directory -Force -Path $patchDir  | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { throw ("ASSERT FAILED: " + $msg) }
}
function Replace-Exact([string]$content, [string]$old, [string]$new, [string]$tag) {
    $cnt = [regex]::Matches($content, [regex]::Escape($old)).Count
    Assert ($cnt -eq 1) ("anchor '" + $tag + "' matched " + $cnt + " times (expected 1)")
    Log ("  replace-exact OK: " + $tag)
    return $content.Replace($old, $new)
}
function ForceLF([string]$s) { return $s.Replace("`r`n", "`n") }

Log ("=== MiniCodex patch " + $version + " ===")

$csprojPath   = Join-Path $projectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
$clPath       = Join-Path $projectRoot 'CHANGELOG.md'
$hoPath       = Join-Path $projectRoot 'docs\HANDOFF.md'

foreach ($p in @($csprojPath,$clPath,$hoPath)) {
    Assert (Test-Path $p) ("Missing: " + $p)
}

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src/MiniCodex.App/MiniCodex.App.csproj',
    'CHANGELOG.md',
    'docs/HANDOFF.md')) {
    $src = Join-Path $projectRoot ($rel -replace '/', '\')
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir ($rel -replace '/', '\')
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log ("  backup: " + $rel)
    }
}

# ================================================================
# STEP 2: csproj - version bump
# ================================================================
Log "STEP 2: csproj"

$cs = Get-Content -LiteralPath $csprojPath -Raw -Encoding UTF8

if ($cs.Contains('<Version>0.1.3</Version>')) {
    Log "  already 0.1.3 - skipping (idempotent)"
} else {
    Assert ($cs.Contains('<Version>0.1.2</Version>')) "csproj: Version 0.1.2 not found"
    Assert ($cs.Contains('<InformationalVersion>0.1.2</InformationalVersion>')) "csproj: InformationalVersion 0.1.2 not found"

    $cs = Replace-Exact $cs '<Version>0.1.2</Version>' '<Version>0.1.3</Version>' "csproj: Version"
    $cs = Replace-Exact $cs '<InformationalVersion>0.1.2</InformationalVersion>' '<InformationalVersion>0.1.3</InformationalVersion>' "csproj: InformationalVersion"

    Set-Content -LiteralPath $csprojPath -Value $cs -Encoding UTF8 -NoNewline
    Log ("  csproj written (" + $cs.Length + " chars)")
}

# ================================================================
# STEP 3: CHANGELOG - prepend [0.1.3]
# ================================================================
Log "STEP 3: CHANGELOG"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

if ($cl.Contains('## [0.1.3] - 2026-11-15')) {
    Log "  [0.1.3] section already present - skipping (idempotent)"
} else {
    $clNl = if ($cl.Contains("`r`n")) { "`r`n" } else { "`n" }

    $clOldRaw = @'
# Changelog

## [0.1.2] - 2026-11-14
'@
    $clNewRaw = @'
# Changelog

## [0.1.3] - 2026-11-15

### Added
- Associated files (Associations tab): fullscreen viewer (double-click to open, Left/Right navigation, Esc to close). Each thumbnail has a context menu: Open (fullscreen), Open with default viewer, Open in Explorer, Copy path, Replace, Remove (with confirmation dialog).
- Third "Other" section on Associations for render/document/profile asset types (128x128 thumbnails, icon fallback for non-images).
- Multi-select in library grid: plain click, Ctrl+click (toggle), Shift+click (range), rubber-band on empty space (Ctrl additive). Esc clears selection, Ctrl+A selects all visible.
- Group toolbar (visible when 2+ cards selected): Add tag (AutoCompleteBox), Copy paths, Find duplicates in selection, Remove selected (with confirmation), Clear.
- Collection colors: 8-swatch context menu on each collection in the sidebar + Clear color. Migration 0005 adds Collection.color.
- Tag autocomplete in Add tag dialogs (card tab + group dialog).
- Delete-tag dialog: shows direct vs subtree usage breakdown.

### Changed
- Thumbnail single-click is selection; double-click opens fullscreen (was: single-click, reverted after 0.5.6a.2b).
- Asset deduplication by original basename in AssetService.ImportAsync (idempotent re-import).

### Fixed
- Remove-asset confirmation dialog was missing in 0.5.6a.2 (VM state set, XAML overlay absent) - added in 0.5.6a.2b.
- ru.json language-pack anchor after 0.5.6c was based on mojibake base64 - fixed via line-based ASCII anchors in 0.5.6c.1b.

## [0.1.2] - 2026-11-14
'@
    $clOld = ForceLF $clOldRaw
    $clNew = ForceLF $clNewRaw
    $clOld = $clOld.Replace("`n", $clNl)
    $clNew = $clNew.Replace("`n", $clNl)

    $cl = Replace-Exact $cl $clOld $clNew "CHANGELOG: prepend [0.1.3]"

    Set-Content -LiteralPath $clPath -Value $cl -Encoding UTF8 -NoNewline
    Log ("  CHANGELOG written (" + $cl.Length + " chars)")
}

# ================================================================
# STEP 4: HANDOFF - series of surgical edits
# ================================================================
Log "STEP 4: HANDOFF"

$ho = Get-Content -LiteralPath $hoPath -Raw -Encoding UTF8
$hoNl = if ($ho.Contains("`r`n")) { "`r`n" } else { "`n" }
$hoHadCrlf = $ho.Contains("`r`n")
Log ("  HANDOFF newline: " + $(if ($hoHadCrlf) { "CRLF" } else { "LF" }))

# Idempotency check
if ($ho.Contains('**Document version:** 3.1 (post v0.1.3 release prep)')) {
    Log "  HANDOFF already v3.1 - skipping (idempotent)"
} else {
    # Normalize content to LF for consistent anchors
    $ho = ForceLF $ho

    function Rep([string]$c, [string]$o, [string]$n, [string]$t) {
        $oLF = ForceLF $o
        $nLF = ForceLF $n
        return Replace-Exact $c $oLF $nLF $t
    }

    # --- 4.1 Header block ---
    $o = @'
**Document version:** 3.0 (post v0.1.2 release prep)
**Last updated:** 2026-11-14
**Current version:** v0.1.2 (release prep complete, awaiting git tag + GitHub Release)
'@
    $n = @'
**Document version:** 3.1 (post v0.1.3 release prep)
**Last updated:** 2026-11-15
**Current version:** v0.1.3 (release prep complete, awaiting git tag + GitHub Release)
'@
    $ho = Rep $ho $o $n "handoff: header"

    # --- 4.2 Section 1 quick start point 2 ---
    $o = '2. Project state: v0.1.2 release prep is complete (patch 0.5.4 applied). Next step is build-release.ps1 + git tag + GitHub Release.'
    $n = '2. Project state: v0.1.3 release prep is complete (patches 0.5.6a..0.5.6c.1b applied). Next step is build-release.ps1 + git tag + GitHub Release.'
    $ho = Rep $ho $o $n "handoff: section 1"

    # --- 4.3 Section 2 version + patch count ---
    $ho = Rep $ho '- **Version:** 0.1.2 (release prep complete; awaiting tag).' '- **Version:** 0.1.3 (release prep complete; awaiting tag).' "handoff: section 2 version"
    $ho = Rep $ho '- **Patch count since 0.1.0:** ~30 patches (see patches/).' '- **Patch count since 0.1.0:** ~40 patches (see patches/).' "handoff: section 2 patch count"

    # --- 4.4 Section 2 heading ---
    $ho = Rep $ho '### What is fully implemented (v0.1.2)' '### What is fully implemented (v0.1.3)' "handoff: section 2 heading"

    # --- 4.5 Section 2 features - insert new items after Associations line ---
    $o = @'
- Associations: Reference/Photo drag-drop, 256x256 thumbs
- Scale converter: 43 presets, prototype filter, bidirectional auto-calc
'@
    $n = @'
- Associations: Reference/Photo drag-drop, 256x256 thumbs
- Associated files fullscreen viewer (double-click open, Left/Right nav, Esc close); thumbnail context menu (Open fullscreen / Open external / Explorer / Copy path / Replace / Remove with confirmation); "Other" section (render/document/profile) 128x128.
- Multi-select in library grid: plain/Ctrl/Shift click, rubber-band, Ctrl+A/Esc; group toolbar (Add tag with autocomplete / Copy paths / Find duplicates in selection / Remove selected / Clear).
- Collection colors: 8 preset swatches + Clear via context menu.
- Tag autocomplete in Add tag dialogs (card + group).
- Delete-tag dialog: direct vs subtree usage breakdown.
- Scale converter: 43 presets, prototype filter, bidirectional auto-calc
'@
    $ho = Rep $ho $o $n "handoff: section 2 features list"

    # --- 4.6 Section 3 Release row ---
    $ho = Rep $ho '| Release | GitHub (current: v0.1.0-alpha, next: v0.1.2) |' '| Release | GitHub (current: v0.1.2, next: v0.1.3) |' "handoff: section 3 release row"

    # --- 4.7 Section 4 migrations list ---
    $ho = Rep $ho '    - Migrations/ - 0001_InitialSchema, 0002_ModelFile_LastWriteTime, 0003_ModelOrientation, 0004_ModelFile_FileHash' '    - Migrations/ - 0001_InitialSchema, 0002_ModelFile_LastWriteTime, 0003_ModelOrientation, 0004_ModelFile_FileHash, 0005_Collection_Color' "handoff: section 4 migrations"

    # --- 4.8 Section 6 Collection table ---
    $ho = Rep $ho '- Collection (id TEXT PK, name, filter_query, is_smart INTEGER)' '- Collection (id TEXT PK, name, filter_query, is_smart INTEGER, color TEXT)' "handoff: section 6 Collection column"

    # --- 4.9 Section 6 migrations list ---
    $o = @'
4. Add file_hash (SHA-256) to ModelFile.
'@
    $n = @'
4. Add file_hash (SHA-256) to ModelFile.
5. Add color (TEXT) to Collection.
'@
    $ho = Rep $ho $o $n "handoff: section 6 migrations list"

    # --- 4.10 Section 8 checklist - insert new items ---
    $o = @'
- [x] Associations: Reference/Photo drag-drop, 256x256 thumbs
- [x] Scale converter: 43 presets, prototype filter, bidirectional auto-calc
'@
    $n = @'
- [x] Associations: Reference/Photo drag-drop, 256x256 thumbs
- [x] Associated files: fullscreen viewer (double-click, Left/Right nav, Esc), thumbnail context menu (Open fullscreen / Open external / Explorer / Copy path / Replace / Remove with confirmation), Other section (render/document/profile) 128x128
- [x] Multi-select in library grid: plain/Ctrl/Shift click, rubber-band, Ctrl+A/Esc, group toolbar (Add tag / Copy paths / Find duplicates / Remove selected / Clear)
- [x] Collection colors: 8 preset swatches + Clear via context menu
- [x] Tag autocomplete in Add tag dialogs (card + group)
- [x] Delete-tag dialog: direct vs subtree usage breakdown
- [x] Scale converter: 43 presets, prototype filter, bidirectional auto-calc
'@
    $ho = Rep $ho $o $n "handoff: section 8 checklist"

    # --- 4.11 Section 9 - remove shipped deferred items ---
    $o = @'
- WebP cache
- Multi-select in grid
- Tag subtree as collection (currently single TagId, but parent-tag filter already includes descendants)
- Custom hex picker for collection color (collections have no color yet)
- macOS/Linux support
'@
    $n = @'
- WebP cache
- Tag subtree as collection (currently single TagId, but parent-tag filter already includes descendants)
- macOS/Linux support
'@
    $ho = Rep $ho $o $n "handoff: section 9 deferred"

    # --- 4.12 Section 11 - remove stale limitations ---
    $o = @'
- 3D renderer: software, ~50-100ms per frame at 480x480 on 100k triangles. No LOD.
- No multi-select in grid. Delete only via context menu.
- Windows-only.
- Tag hierarchy in UI: works for filtering, but tag rename/delete does not auto-merge children.
- Custom collection color: not implemented (Collections have no color field).
- Right-click on an unselected tag also selects it (Avalonia TreeView default) -> filter applies before the context menu opens. Works fine but unexpected; if it becomes a nuisance, handle ContextRequested with e.Handled = true (deferred).
'@
    $n = @'
- 3D renderer: software, ~50-100ms per frame at 480x480 on 100k triangles. No LOD.
- Windows-only.
- Tag hierarchy in UI: works for filtering, but tag rename/delete does not auto-merge children.
- Right-click on an unselected tag also selects it (Avalonia TreeView default) -> filter applies before the context menu opens. Works fine but unexpected; if it becomes a nuisance, handle ContextRequested with e.Handled = true (deferred).
- Fullscreen image viewer: no zoom/pan, no rotation, no EXIF orientation.
- "Replace" re-imports the file as a new Asset row (old thumbnail stays in cache; harmless).
'@
    $ho = Rep $ho $o $n "handoff: section 11 limitations"

    # --- 4.13 Section 12 - remove resolved open question ---
    $o = @'
- Should MinLambert slider also affect library tile previews? (Currently only card 3D viewer.)
- Do we want "Others" section in Associations for render/document/profile types? (Currently hidden.)
'@
    $n = @'
- Should MinLambert slider also affect library tile previews? (Currently only card 3D viewer.)
'@
    $ho = Rep $ho $o $n "handoff: section 12 open questions"

    # --- 4.14 Section 13 - full rewrite ---
    $o = @'
## 13. Next step - v0.1.2 Release

Prerequisites (already done):
- build-release.ps1 at project root.
- README.md with 5 screenshot references.
- AssemblyName=MiniCodex (exe name), Version 0.1.2, InformationalVersion 0.1.2.
- CHANGELOG.md has [0.1.2] section.
- Screenshots must be saved in docs/screenshots/ with names 01..05.

Release steps:
1. `powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"`
   -> dist/MiniCodex-v0.1.2-win-x64.zip
2. Verify by extracting on clean Windows x64, running MiniCodex.exe.
3. git add . && git commit -m "Release v0.1.2: Smart Collections, Tag Colors, UI polish"
4. git tag -a v0.1.2 -m "MiniCodex v0.1.2"
5. git push origin master && git push origin v0.1.2
6. GitHub Release: tag v0.1.2, pre-release flag, attach zip.
'@
    $n = @'
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
'@
    $ho = Rep $ho $o $n "handoff: section 13 rewrite"

    # --- 4.15 Append section 15 before end marker ---
    $o = '<!-- patch 0.5.5 applied -->'
    $n = @'
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
'@
    $ho = Rep $ho $o $n "handoff: append section 15"

    # Restore CRLF if original had it
    if ($hoHadCrlf) {
        $ho = $ho.Replace("`n", "`r`n")
    }

    Set-Content -LiteralPath $hoPath -Value $ho -Encoding UTF8 -NoNewline
    Log ("  HANDOFF written (" + $ho.Length + " chars)")
}

# ================================================================
# STEP 5: Post-write verification
# ================================================================
Log "STEP 5: Post-write verification"

$csBack = Get-Content -LiteralPath $csprojPath -Raw -Encoding UTF8
Assert ($csBack.Contains('<Version>0.1.3</Version>')) "post-write: csproj Version 0.1.3 missing"
Assert ($csBack.Contains('<InformationalVersion>0.1.3</InformationalVersion>')) "post-write: csproj InformationalVersion 0.1.3 missing"
Assert (-not $csBack.Contains('<Version>0.1.2</Version>')) "post-write: csproj still has Version 0.1.2"

$clBack = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
Assert ($clBack.Contains('## [0.1.3] - 2026-11-15')) "post-write: CHANGELOG [0.1.3] missing"
Assert ($clBack.Contains('## [0.1.2] - 2026-11-14')) "post-write: CHANGELOG [0.1.2] removed - unexpected"

$hoBack = Get-Content -LiteralPath $hoPath -Raw -Encoding UTF8
Assert ($hoBack.Contains('**Document version:** 3.1 (post v0.1.3 release prep)')) "post-write: HANDOFF header not bumped"
Assert ($hoBack.Contains('**Current version:** v0.1.3')) "post-write: HANDOFF current version not bumped"
Assert ($hoBack.Contains('0005_Collection_Color')) "post-write: HANDOFF migrations missing 0005"
Assert ($hoBack.Contains('color TEXT')) "post-write: HANDOFF Collection schema missing color"
Assert ($hoBack.Contains('## 13. Next step - v0.1.3 Release')) "post-write: HANDOFF section 13 not rewritten"
Assert ($hoBack.Contains('## 15. Session 2026-11-15')) "post-write: HANDOFF section 15 missing"
Assert ($hoBack.Contains('<!-- patch 0.5.7 applied -->')) "post-write: HANDOFF 0.5.7 marker missing"
Assert ($hoBack.Contains('<!-- patch 0.5.5 applied -->')) "post-write: HANDOFF 0.5.5 marker lost"
# Sanity: removed lines should be gone
Assert (-not $hoBack.Contains('No multi-select in grid. Delete only via context menu.')) "post-write: stale limitation 'No multi-select' still present"
Assert (-not $hoBack.Contains('Custom collection color: not implemented')) "post-write: stale limitation 'Custom collection color' still present"
Assert (-not $hoBack.Contains('- Multi-select in grid`n')) "post-write: deferred 'Multi-select in grid' still present"
Assert (-not $hoBack.Contains('Do we want "Others" section in Associations')) "post-write: stale open question still present"
Log "  post-write verify OK"

# ================================================================
# STEP 6: CHANGELOG marker for 0.5.7
# ================================================================
Log "STEP 6: CHANGELOG marker 0.5.7"

$clBack2 = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($clBack2.Contains('<!-- patch 0.5.7 applied -->')) {
    Log "  0.5.7 marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.7 - Release prep v0.1.3

- MiniCodex.App.csproj: Version 0.1.2 -> 0.1.3, InformationalVersion 0.1.3.
- CHANGELOG.md: [0.1.3] - 2026-11-15 section (Added/Changed/Fixed).
- docs/HANDOFF.md: Document version 3.0 -> 3.1, current version v0.1.3, features list, migrations 0005_Collection_Color, Collection.color, removed stale deferred items and limitations, resolved open question about "Others" section, rewritten section 13 for v0.1.3 release, appended section 15 (Session 2026-11-15).
<!-- patch 0.5.7 applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; dotnet test; then build-release.ps1 + git tag v0.1.3 + GitHub Release" -ForegroundColor Cyan