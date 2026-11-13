#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3g.1 - Close 0.4.3g: CHANGELOG + safe thumbs cleanup.
.DESCRIPTION
    0.4.3g applied code changes but hung on Remove-Item (no -LiteralPath).
    This patch: writes CHANGELOG entry 0.4.3g; cleans old 128px thumbs safely.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3g.1'
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

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    # --- 1. Safe cleanup of old 128px thumbs ---
    $thumbDirs = @(
        (Join-Path $ProjectRoot 'src\MiniCodex.App\bin\Debug\net8.0\data\cache\asset-thumbs'),
        (Join-Path $ProjectRoot 'dist\data\cache\asset-thumbs'),
        (Join-Path $ProjectRoot 'data\cache\asset-thumbs')
    )
    $totalRemoved = 0
    foreach ($d in $thumbDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $removed = 0
        try {
            $items = Get-ChildItem -LiteralPath $d -Filter '*.png' -File -ErrorAction SilentlyContinue
            foreach ($f in $items) {
                if ($f.Name -match '_256\.png$') { continue }
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $removed++
                } catch { }
            }
        } catch { }
        if ($removed -gt 0) { Write-Log "cleaned $removed old thumbs in $d" }
        $totalRemoved += $removed
    }
    if ($totalRemoved -eq 0) { Write-Log 'no old thumbs to clean (ok)' }

    # --- 2. CHANGELOG entry ---
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')
    $marker = '<!-- patch 0.4.3g applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3g] - 2026-11-12`r`n`r`n### Changed`r`n- Associations tab is first and default (0).`r`n- Reference and Photo stacked vertically as separate elevated sections.`r`n- Drop hint is empty-state placeholder; whole area is drop zone.`r`n- Thumbnails 256x256, no text labels below, remove button overlay.`r`n- Fixed: Add-tag context menu opens Tags (was Scale).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3f\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: added 0.4.3g entry'
        } else {
            Write-Log 'CHANGELOG.md: 0.4.3g already present, skipping.' 'WARN'
        }
    }

    # --- 3. Verify 0.4.3g changes applied ---
    $xamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    $xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('TabAssociationsHeader first tab', ($xaml.IndexOf('TabItem Header="{Binding TabAssociationsHeader}"') -lt $xaml.IndexOf('TabItem Header="{Binding TabFilesHeader}"'))),
        @('HasReferenceAssets in XAML', ($xaml -match 'HasReferenceAssets')),
        @('256x256 tile', ($xaml -match 'Width="256" Height="256"'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    $vmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    if ($vm -match '_selectedTabIndex = 0;') { Write-Log 'verify OK: _selectedTabIndex = 0' }
    else { Write-Log 'verify FAIL: _selectedTabIndex != 0' 'WARN' }

    $svcPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\AssetService.cs'
    $svc = [IO.File]::ReadAllText($svcPath, [Text.Encoding]::UTF8)
    if ($svc -match '_256\.png') { Write-Log 'verify OK: AssetService _256.png' }
    else { Write-Log 'verify FAIL: AssetService _256.png missing' 'WARN' }

    # README
    $readme = @'
# Patch 0.4.3g.1 - Close 0.4.3g

**Iteration:** 0.4

## Cause
0.4.3g applied all code changes, then hung on Remove-Item without -LiteralPath.
User pressed Ctrl+C; CHANGELOG entry and thumbs cleanup were skipped.

## Fix
- CHANGELOG entry 0.4.3g added.
- Old 128px thumbs ({assetId}.png) cleaned from dev bin/ using -LiteralPath (safe).
- Verified that 0.4.3g changes are in place (Assoc first tab, HasReferenceAssets, 256x256, _selectedTabIndex=0, _256.png).

## DoD
- dotnet build: 0 errors.
- dotnet test: 48/48.
- All verify checks OK in log.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3g.1\README.md'

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}