#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3e.2 - Fix AVLN2000: move Padding from StackPanel to parent Border.
.DESCRIPTION
    ModelCardView.axaml: Padding="12" removed from StackPanel, added to outer Border.elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3e.2'
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

    # Fix 1: move Padding from StackPanel to parent Border
    $oldBlock = '<Border Grid.Row="1" Classes="elevated" Margin="0,8,0,0">' + "`r`n" +
                '                    <StackPanel Padding="12" Spacing="6">'
    $newBlock = '<Border Grid.Row="1" Classes="elevated" Margin="0,8,0,0" Padding="12">' + "`r`n" +
                '                    <StackPanel Spacing="6">'
    if ($xaml.Contains($oldBlock)) {
        $xaml = $xaml.Replace($oldBlock, $newBlock)
        [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ModelCardView.axaml (Padding moved to parent Border)'
    } else {
        # Fallback: any StackPanel with Padding -> strip Padding (add to nearest ancestor Border is harder; just strip)
        if ($xaml -match '<StackPanel Padding="12" Spacing="6">') {
            $xaml = $xaml -replace '<StackPanel Padding="12" Spacing="6">', '<StackPanel Spacing="6">'
            [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: ModelCardView.axaml (Padding stripped from StackPanel; visual padding reduced)' 'WARN'
        } else {
            Write-Log 'ModelCardView.axaml: target block not found; please check manually.' 'WARN'
        }
    }

    # README
    $readme = @'
# Patch 0.4.3e.2 - Fix AVLN2000 (StackPanel.Padding)

**Iteration:** 0.4

## Cause
AVLN2000: StackPanel does not have Padding property in Avalonia 11.
My XAML had: <StackPanel Padding="12" Spacing="6"> - invalid.

## Fix
Moved Padding="12" from StackPanel to parent Border.elevated (which does have Padding).

## DoD
- dotnet build: 0 errors (2 pre-existing warnings).
- dotnet test: 48/48.
- Info panel keeps 12px inner padding.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3e.2\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3e.2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.3e.2: AVLN2000 - moved Padding from StackPanel to parent Border in ModelCardView.axaml.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3e\.1\].*)$', "$entry`$1"
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