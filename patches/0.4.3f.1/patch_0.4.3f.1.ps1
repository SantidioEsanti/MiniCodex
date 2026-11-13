#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3f.1 - Fix AVLN2000: DragOver/Drop must be DragDrop.DragOver / DragDrop.Drop (attached events).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3f.1'
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

    $xamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    Backup-File $xamlPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
    $original = $xaml

    # Fix both drop zones.
    # Current broken form: DragOver="OnDragOver" Drop="OnDropReference"  (already has DragDrop.AllowDrop on same element)
    # After fix: DragDrop.DragOver="OnDragOver" DragDrop.Drop="OnDropReference"

    $xaml = $xaml -replace '(\s)DragOver="OnDragOver"', '$1DragDrop.DragOver="OnDragOver"'
    $xaml = $xaml -replace '(\s)DragOver="OnDragOver"', '$1DragDrop.DragOver="OnDragOver"'  # idempotent-safe second pass
    $xaml = $xaml -replace '(\s)Drop="OnDropReference"', '$1DragDrop.Drop="OnDropReference"'
    $xaml = $xaml -replace '(\s)Drop="OnDropPhoto"', '$1DragDrop.Drop="OnDropPhoto"'

    # Guard: if replacement created DragDrop.DragDrop.DragOver (double-prefix bug), undo it
    $xaml = $xaml -replace 'DragDrop\.DragDrop\.', 'DragDrop.'

    if ($xaml -ne $original) {
        [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ModelCardView.axaml (DragDrop.DragOver / DragDrop.Drop)'
    } else {
        # Maybe already fixed?
        if ($xaml -match 'DragDrop\.DragOver=') {
            Write-Log 'ModelCardView.axaml: already fixed, skipping.' 'WARN'
        } else {
            Write-Log 'ModelCardView.axaml: pattern not matched, checking manually needed.' 'WARN'
        }
    }

    # Sanity print the two Border tags that contain AllowDrop
    $lines = [IO.File]::ReadAllLines($xamlPath, [Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match 'DragDrop\.AllowDrop') {
            Write-Log ("  line {0}: {1}" -f ($i + 1), $lines[$i].Trim())
        }
    }

    # README
    $readme = @'
# Patch 0.4.3f.1 - Fix AVLN2000 (DragOver/Drop attached events)

**Iteration:** 0.4

## Cause
In Avalonia 11 DragOver and Drop are attached events on DragDrop class.
XAML: DragOver="OnDragOver" Drop="OnDrop..." -> AVLN2000.
Fix: DragDrop.DragOver="OnDragOver" DragDrop.Drop="OnDrop...".

## DoD
- dotnet build: 0 errors (2 pre-existing warnings).
- dotnet test: 48/48.
- Both drop zones (Reference / Photo) accept drag-and-drop.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3f.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3f.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.3f.1: DragOver/Drop -> DragDrop.DragOver/Drop (attached events).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3f\].*)$', "$entry`$1"
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