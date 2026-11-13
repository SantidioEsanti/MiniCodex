#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a10.1 - Fix CS1061: BaseSupersample -> Supersample in PreviewGenerator.cs.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a10.1'
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

    $pgPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    Backup-File $pgPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($pgPath, [Text.Encoding]::UTF8)
    $original = $content

    # BaseSupersample -> Supersample (BaseSupersample removed from options in 0.4.5a10)
    $content = $content.Replace('_options.BaseSupersample', '_options.Supersample')

    # Defensive: any remaining PickSupersample calls (should already be replaced in 0.4.5a10)
    $content = $content -replace '_options\.PickSupersample\s*\([^)]*\)', '_options.Supersample'

    if ($content -ne $original) {
        [IO.File]::WriteAllText($pgPath, $content, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: PreviewGenerator.cs (BaseSupersample -> Supersample)'
    } else {
        Write-Log 'PreviewGenerator.cs: pattern not found; checking existing content.' 'WARN'
    }

    # Verify: no BaseSupersample and no PickSupersample references remain
    $verify = [IO.File]::ReadAllText($pgPath, [Text.Encoding]::UTF8)
    if ($verify -match 'BaseSupersample') {
        Write-Log 'verify FAIL: BaseSupersample still present' 'WARN'
    } else {
        Write-Log 'verify OK: no BaseSupersample references'
    }
    if ($verify -match 'PickSupersample') {
        Write-Log 'verify FAIL: PickSupersample still present' 'WARN'
    } else {
        Write-Log 'verify OK: no PickSupersample references'
    }
    if ($verify -match '_options\.Supersample') {
        Write-Log 'verify OK: _options.Supersample in use'
    } else {
        Write-Log 'verify FAIL: _options.Supersample not found' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a10.1 - Fix CS1061

**Iteration:** 0.4.5

## Cause

0.4.5a10 removed `BaseSupersample` from PreviewGeneratorOptions
(replaced with fixed `Supersample = 2`), but one reference remained in
PreviewGenerator.cs: `int chosenSS = _options.BaseSupersample;` -> CS1061.

## Fix

Replace `_options.BaseSupersample` with `_options.Supersample`
(+ defensive regex for any leftover `PickSupersample` calls).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a10.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a10.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a10.1: PreviewGenerator.cs BaseSupersample -> Supersample (CS1061).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a10\].*)$', "$entry`$1"
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