# patch_0.5.6a.1d.ps1
# 0.5.6a.1d - Fix for 0.5.6a.1
#   ModelCardPageViewModel.cs:898 CS1929. _fullScreenList was IReadOnlyList<T>,
#   which has no IndexOf. Change to List<AssetRowViewModel> and update both
#   initializers (field + CloseFullScreen). Behavior unchanged.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6a.1d\patch_0.5.6a.1d.ps1"

Write-Host "=== MiniCodex patch 0.5.6a.1d STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6a.1d'
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

$pageVmPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
$clPath     = Join-Path $projectRoot 'CHANGELOG.md'
$hoPath     = Join-Path $projectRoot 'docs\HANDOFF.md'

Assert (Test-Path $pageVmPath) ("ModelCardPageViewModel.cs missing: " + $pageVmPath)

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
$filesToBackup = @(
    'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
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
# STEP 2: Fix _fullScreenList type
# ================================================================
Log "STEP 2: Fix _fullScreenList type"

$vm = Get-Content -LiteralPath $pageVmPath -Raw -Encoding UTF8

# 2a. Field declaration + initializer
$oldField = @'
    private IReadOnlyList<AssetRowViewModel> _fullScreenList = Array.Empty<AssetRowViewModel>();
'@
$newField = @'
    private List<AssetRowViewModel> _fullScreenList = new List<AssetRowViewModel>();
'@
while ($oldField.EndsWith("`r`n")) { $oldField = $oldField.Substring(0, $oldField.Length - 2) }
while ($oldField.EndsWith("`n"))   { $oldField = $oldField.Substring(0, $oldField.Length - 1) }
$vm = Replace-Exact $vm $oldField $newField "field _fullScreenList"

# 2b. CloseFullScreen reset
$oldReset = @'
        _fullScreenList = Array.Empty<AssetRowViewModel>();
'@
$newReset = @'
        _fullScreenList = new List<AssetRowViewModel>();
'@
while ($oldReset.EndsWith("`r`n")) { $oldReset = $oldReset.Substring(0, $oldReset.Length - 2) }
while ($oldReset.EndsWith("`n"))   { $oldReset = $oldReset.Substring(0, $oldReset.Length - 1) }
$vm = Replace-Exact $vm $oldReset $newReset "CloseFullScreen reset"

# 2c. Guard: no more IReadOnlyList<AssetRowViewModel> for the field
Assert (-not $vm.Contains('IReadOnlyList<AssetRowViewModel> _fullScreenList')) "IReadOnlyList field still present"
Assert (-not $vm.Contains('_fullScreenList = Array.Empty<AssetRowViewModel>()')) "Array.Empty reset still present"

# 2d. Guard: IndexOf now valid (List<T> has it)
Assert ($vm.Contains('_fullScreenList.IndexOf(row)')) "IndexOf usage missing - unexpected, check file"
Assert ($vm.Contains('private List<AssetRowViewModel> _fullScreenList = new List<AssetRowViewModel>();')) "new field decl missing"

Set-Content -LiteralPath $pageVmPath -Value $vm -Encoding UTF8 -NoNewline
Log ("  ModelCardPageViewModel.cs written (" + $vm.Length + " chars)")

# post-write verify
$back = Get-Content -LiteralPath $pageVmPath -Raw -Encoding UTF8
Assert ($back.Length -eq $vm.Length) "post-write length mismatch"
Assert ($back.Contains('private List<AssetRowViewModel> _fullScreenList = new List<AssetRowViewModel>();')) "post-write field decl mismatch"
Log "  post-write verify OK"

# ================================================================
# STEP 3: CHANGELOG.md
# ================================================================
Log "STEP 3: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6a.1d applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6a.1d - Compile fix for 0.5.6a.1

- ModelCardPageViewModel._fullScreenList: IReadOnlyList<AssetRowViewModel> -> List<AssetRowViewModel>. IReadOnlyList<T> has no IndexOf; List<T> does. Initializers (field + CloseFullScreen) updated to new List<...>(). Behavior unchanged.
<!-- patch 0.5.6a.1d applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; expect 0 errors. Then 0.5.6a.2 (ModelCardView.axaml + code-behind)." -ForegroundColor Cyan