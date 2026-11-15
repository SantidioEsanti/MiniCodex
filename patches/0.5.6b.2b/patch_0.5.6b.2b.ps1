# patch_0.5.6b.2b.ps1
# 0.5.6b.2b - Compile fix for 0.5.6b.2
#   LibraryView.axaml.cs: ContentPresenter is in Avalonia.Controls.Presenters.
#   Add missing using. Behavior unchanged.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6b.2b\patch_0.5.6b.2b.ps1"

Write-Host "=== MiniCodex patch 0.5.6b.2b STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6b.2b'
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

Log ("=== MiniCodex patch " + $version + " ===")

$libCsPath = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml.cs'
$clPath    = Join-Path $projectRoot 'CHANGELOG.md'

Assert (Test-Path $libCsPath) ("Missing: " + $libCsPath)

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src\MiniCodex.App\Views\LibraryView.axaml.cs',
    'CHANGELOG.md')) {
    $src = Join-Path $projectRoot $rel
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir $rel
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log ("  backup: " + $rel)
    }
}

# ================================================================
# STEP 2: Add using Avalonia.Controls.Presenters;
# ================================================================
Log "STEP 2: Add using"

$cs = Get-Content -LiteralPath $libCsPath -Raw -Encoding UTF8
$nl = if ($cs.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($cs.Contains('using Avalonia.Controls.Presenters;')) {
    Log "  already has using - skipping (idempotent)"
} else {
    Assert ($cs.Contains('ContentPresenter')) "ContentPresenter not referenced - unexpected, aborting"

    $oldUsing = 'using Avalonia.Controls;'
    $newUsing = 'using Avalonia.Controls;' + $nl + 'using Avalonia.Controls.Presenters;'
    $cs = Replace-Exact $cs $oldUsing $newUsing "using Avalonia.Controls.Presenters"

    Set-Content -LiteralPath $libCsPath -Value $cs -Encoding UTF8 -NoNewline
    Log ("  written (" + $cs.Length + " chars)")
}

# post-write sanity
$back = Get-Content -LiteralPath $libCsPath -Raw -Encoding UTF8
Assert ($back.Contains('using Avalonia.Controls.Presenters;')) "post-write: using missing"
Assert ($back.Contains('ContentPresenter')) "post-write: ContentPresenter still referenced"
Log "  post-write verify OK"

# ================================================================
# STEP 3: CHANGELOG.md
# ================================================================
Log "STEP 3: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6b.2b applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6b.2b - Compile fix for 0.5.6b.2

- LibraryView.axaml.cs: added using Avalonia.Controls.Presenters (CS0246 for ContentPresenter). Behavior unchanged.
<!-- patch 0.5.6b.2b applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then verify multi-select in UI" -ForegroundColor Cyan