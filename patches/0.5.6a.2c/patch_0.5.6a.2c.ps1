# patch_0.5.6a.2c.ps1
# 0.5.6a.2c - Open image in fullscreen on DOUBLE-click (was single-click).
#   ModelCardView.axaml.cs: OnThumbnailPointerPressed now requires e.ClickCount == 2.
#   Single click does nothing (click on the small X Button still goes through its own handler).
#   No XAML changes (handler name unchanged).
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6a.2c\patch_0.5.6a.2c.ps1"

Write-Host "=== MiniCodex patch 0.5.6a.2c STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6a.2c'
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

$viewCsPath = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml.cs'
$clPath     = Join-Path $projectRoot 'CHANGELOG.md'

Assert (Test-Path $viewCsPath) ("Missing: " + $viewCsPath)

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src\MiniCodex.App\Views\ModelCardView.axaml.cs',
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
# STEP 2: ModelCardView.axaml.cs - require ClickCount == 2
# ================================================================
Log "STEP 2: ModelCardView.axaml.cs"

$cs = Get-Content -LiteralPath $viewCsPath -Raw -Encoding UTF8
$cs = $cs -replace "`r`n", "`n"

Assert (-not $cs.Contains('e.ClickCount != 2')) "already patched (ClickCount check present)"
Assert ($cs.Contains('private void OnThumbnailPointerPressed')) "unexpected file - OnThumbnailPointerPressed missing"

$oldAnchor = @'
        if (e.Handled) return;
        var point = e.GetCurrentPoint(this);
        if (!point.Properties.IsLeftButtonPressed) return;
        if (sender is Control c && c.DataContext is AssetRowViewModel row)
'@
$newAnchor = @'
        if (e.Handled) return;
        var point = e.GetCurrentPoint(this);
        if (!point.Properties.IsLeftButtonPressed) return;
        if (e.ClickCount != 2) return;  // double-click opens fullscreen
        if (sender is Control c && c.DataContext is AssetRowViewModel row)
'@
$oldAnchor = $oldAnchor -replace "`r`n", "`n"
$newAnchor = $newAnchor -replace "`r`n", "`n"

$cs = Replace-Exact $cs $oldAnchor $newAnchor "OnThumbnailPointerPressed: ClickCount == 2"

Assert ($cs.Contains('if (e.ClickCount != 2) return;  // double-click opens fullscreen')) "post-replace: ClickCount check missing"

Set-Content -LiteralPath $viewCsPath -Value $cs -Encoding UTF8 -NoNewline
Log ("  written (" + $cs.Length + " chars)")

$back = Get-Content -LiteralPath $viewCsPath -Raw -Encoding UTF8
Assert ($back.Contains('if (e.ClickCount != 2) return;  // double-click opens fullscreen')) "post-write: ClickCount check missing"
$cnt = [regex]::Matches($back, [regex]::Escape('e.ClickCount != 2')).Count
Assert ($cnt -eq 1) ("post-write: ClickCount check count = $cnt (expected 1)")
Log "  post-write verify OK"

# ================================================================
# STEP 3: CHANGELOG.md
# ================================================================
Log "STEP 3: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6a.2c applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6a.2c - Double-click to open image

- ModelCardView.axaml.cs: OnThumbnailPointerPressed now requires e.ClickCount == 2. Single-click no longer opens fullscreen; double-click does. The small X Button still works via its own Click handler (it marks the pointer event Handled, our handler bails early). Context menu commands unchanged.
<!-- patch 0.5.6a.2c applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then 0.5.6b.1 (multi-select backend) - need LibraryViewModel.cs etc." -ForegroundColor Cyan