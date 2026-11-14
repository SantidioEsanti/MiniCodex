$ErrorActionPreference = "Stop"
$ver = "0.5.1a39"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Update HANDOFF.md with v0.1.1 state"

$files = @(
    "$root\docs\HANDOFF.md",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$handoffPath = "$root\docs\HANDOFF.md"
if (Test-Path $handoffPath) {
    $content = [IO.File]::ReadAllText($handoffPath)
    if ($content -notmatch "patch 0.5.1a39 applied") {
        $appendix = @"

---

## 18. Post-release state v0.1.1 (2026-11-13)

### 18.1 UI Soft Glass (v0.5.0a1..a18, a28)
- Implemented Glassmorphism UI (soft shadows, rounded corners, glass panels).
- Added gradient backgrounds for Light (warm white to soft lavender) and Dark (warm gray to graphite) themes.
- Moved design tokens (colors, shadows) into ThemeDictionaries for proper Light/Dark support.
- Replaced Unicode status icons (Segoe Fluent Icons) with native `StreamGeometry` + `PathIcon` (Clock, 3D Printer, Brush).
- Reduced card margins (6,6,6,20) and shadow blur to increase grid density.

### 18.2 Critical Architecture Changes (v0.5.1a20..a27)
- **Virtualization Reverted:** We tried `ItemsRepeater` with `UniformGridLayout` (Avalonia 11.1.5), but it caused severe UI update bugs (cards disappearing, stuck filters). We reverted to stable `ItemsControl` + `WrapPanel` and a get-only `ObservableCollection`.
- **Singleton ViewModel:** `LibraryViewModel` is no longer disposed on navigation (`DisposeAsync` is a no-op). It must survive navigation to/from model cards.
- **Direct UI Updates:** Removed complex `Dispatcher.InvokeAsync` for collection replacement. Now `Cards.Clear()` + `Cards.Add()` is done directly, and `ReloadModelsCoreAsync` uses a `SemaphoreSlim` to prevent overlapping loads.

### 18.3 New Features (v0.5.1a33..a38)
- **Spatial Deduplication:** `MeshNormalSmoother` in `MiniCodex.Render` smooths normals for meshes with >500K triangles.
- **Duplicate Detection:** 
  - Migration_0004 adds `file_hash` (SHA-256) to `ModelFile`.
  - `ScannerService` computes SHA-256 on scan for new/updated files.
  - `ModelRepository.GetDuplicateModelIdsAsync()` finds duplicates.
  - "Find duplicates" button added to Library toolbar.
- **Single-instance lock:** Named Mutex in `Program.cs` prevents multiple instances (protects SQLite).

### 18.4 Known Issues
- **First scan after v0.5.1a35:** If you didn't scan after the hash migration, the "Find duplicates" button will return an empty list until you scan folders again (to populate hashes).
- **Card margins:** We reduced them to 6,6,6,20, but some users may still find the grid sparse. Future optimization: use dynamic `Margin` based on viewport width.

### 18.5 Next steps (v1.1 backlog)
1. **Bed Fit Check:** Add model dimensions to DB, compare with printer bed size.
2. **Archives:** Support ZIP/RAR/7Z scanning.
3. **Tag color picker:** UI for `Tag.color` field.
4. **Multi-select:** In library grid.

<!-- patch 0.5.1a39 applied -->
"@
        [IO.File]::AppendAllText($handoffPath, $appendix)
        Log "HANDOFF.md updated with v0.1.1 state."
    } else {
        Log "HANDOFF.md already updated."
    }
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Docs: Updated HANDOFF.md with post-release v0.1.1 state (UI Soft Glass, architecture fixes, duplicate detection, known issues).
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."