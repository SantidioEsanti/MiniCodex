#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.0d - Adds Anycubic Slicer + Anycubic Slicer Next.
.DESCRIPTION
    Fixes PS 5.1 parser issue from 0.4.0c (indented here-string closer).
    ASCII-only, no here-strings, no Cyrillic.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.0d'
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

    $catalogPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\IntegrationCatalog.cs'
    Backup-File $catalogPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8)

    if ($content -match 'anycubic-slicer') {
        Write-Log 'Anycubic already present, skipping.' 'WARN'
    } else {
        $lines = @(
            '        // ---------- Anycubic ----------',
            '        new IntegrationAppDefinition(',
            '            "anycubic-slicer", "Anycubic Slicer", IntegrationAppKind.Slicer,',
            '            new[]',
            '            {',
            '                @"C:\Program Files\AnycubicSlicer\Anycubic-Slicer.exe",',
            '                @"C:\Program Files\Anycubic\Anycubic-Slicer.exe",',
            '                @"%LOCALAPPDATA%\Programs\AnycubicSlicer\Anycubic-Slicer.exe",',
            '            },',
            '            "Anycubic-Slicer.exe",',
            '            new[] { "Anycubic Slicer" }),',
            '',
            '        new IntegrationAppDefinition(',
            '            "anycubic-slicer-next", "Anycubic Slicer Next", IntegrationAppKind.Slicer,',
            '            new[]',
            '            {',
            '                @"C:\Program Files\AnycubicSlicerNext\AnycubicSlicerNext.exe",',
            '                @"%LOCALAPPDATA%\Programs\AnycubicSlicerNext\AnycubicSlicerNext.exe",',
            '            },',
            '            "AnycubicSlicerNext.exe",',
            '            new[] { "Anycubic Slicer Next", "AnycubicSlicerNext" }),',
            '',
            '        // ---------- Editors ----------'
        )
        $block = $lines -join "`r`n"

        $editorsMarker = '        // ---------- Editors ----------'
        if (-not $content.Contains($editorsMarker)) {
            Write-Log 'Editors marker not found in IntegrationCatalog.cs - abort.' 'ERROR'
            exit 1
        }

        $newContent = $content.Replace($editorsMarker, $block)
        [IO.File]::WriteAllText($catalogPath, $newContent, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.Core\Services\IntegrationCatalog.cs'
    }

    $marker = '<!-- patch 0.4.0d applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Added`r`n- 0.4.0d: Anycubic Slicer, Anycubic Slicer Next.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.0c\].*)$', "$entry`$1"
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