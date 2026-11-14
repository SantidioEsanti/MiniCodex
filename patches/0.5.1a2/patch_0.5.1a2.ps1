$ErrorActionPreference = "Stop"
$ver = "0.5.1a2"
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

Log "Starting patch $ver - Update HANDOFF.md with recent changes"

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

$handoff = "$root\docs\HANDOFF.md"
$content = [IO.File]::ReadAllText($handoff)

if ($content -match "patch 0.5.1a2 applied") {
    Log "HANDOFF.md already updated. Skipping."
} else {
    $appendix = @"

---

## 17. Development state (2026-11-13 - post UI/3D updates)

### 17.1 UI Soft Glass (v0.5.0a1..a18)
- Implemented Glassmorphism UI (soft shadows, rounded corners, glass panels).
- Added gradient backgrounds for Light (warm white to soft lavender) and Dark (warm gray to graphite) themes.
- Moved design tokens (colors, shadows) into ThemeDictionaries for proper Light/Dark support.
- Known issue: Card grid margins are currently large (added for shadows). Needs optimization in future UI patches.

### 17.2 Spatial Deduplication (v0.5.1a1)
- Added `MeshNormalSmoother` in `MiniCodex.Render.Rendering`.
- Triggered for meshes with >500,000 triangles to weld vertices by spatial position (precision 1e-3) and average normals.
- Fixes "layer lines" on 3D-scanned STL models.
- Added unit tests (50 total now).

### 17.3 Next steps (v0.1.1 backlog)
1. Single-instance lock (Mutex) to prevent SQLite race conditions.
2. Grid virtualization (ItemsRepeater + UniformGridLayout) for 1000+ models.
3. Tag hierarchy in UI.

<!-- patch 0.5.1a2 applied -->
"@
    [IO.File]::AppendAllText($handoff, $appendix)
    Log "HANDOFF.md updated with new sections."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Docs: Updated HANDOFF.md with Soft Glass UI and Spatial Deduplication details.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."