#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3z3.1 - Fix CS1501 in AboutViewModel (Loc.Get takes 1 arg, not 2).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3z3.1'
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

    $vmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\AboutViewModel.cs'
    Backup-File $vmPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)

    # Replace App.Loc?.Get("key", "fallback") with App.Loc?.Get("key") ?? "fallback"
    # (7 occurrences across lines 15, 30, 31, 33, 34, 35, 36)
    $pattern = 'App\.Loc\?\.Get\("([^"]+)",\s*"([^"]+)"\)'
    $fixed = [regex]::Replace($content, $pattern, 'App.Loc?.Get("$1") ?? "$2"')

    if ($fixed -ne $content) {
        [IO.File]::WriteAllText($vmPath, $fixed, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.App\ViewModels\AboutViewModel.cs (Loc.Get single-arg + ?? fallback)'
    } else {
        Write-Log 'AboutViewModel.cs: pattern not matched, checking manually.' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.3z3.1 - Fix CS1501 in AboutViewModel

**Iteration:** 0.4

## Cause
App.Loc.Get(string key) takes one argument. AboutViewModel used App.Loc?.Get("key", "fallback")
(two arguments) - 7 x CS1501.

## Fix
Replace App.Loc?.Get("X", "fallback") with App.Loc?.Get("X") ?? "fallback".

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- About screen works.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3z3.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3z3.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.3z3.1: AboutViewModel - App.Loc.Get single-arg + ?? fallback (CS1501).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3z3\].*)$', "$entry`$1"
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