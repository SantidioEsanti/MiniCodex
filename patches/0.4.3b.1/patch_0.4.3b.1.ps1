#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3b.1 - Add Avalonia.Fonts.Inter package (fixes CS1061 WithInterFont).
.DESCRIPTION
    Adds <PackageReference Include="Avalonia.Fonts.Inter" Version="11.2.3" />
    to MiniCodex.App.csproj. Idempotent: skips if already present.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3b.1'
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

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $csprojPath = Join-Path $ProjectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
    Backup-File $csprojPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($csprojPath, [Text.Encoding]::UTF8)

    if ($content -match 'Avalonia\.Fonts\.Inter') {
        Write-Log 'Avalonia.Fonts.Inter already present, skipping.' 'WARN'
    } else {
        # Insert right after Avalonia.Themes.Fluent line (or before </ItemGroup> of PackageReferences)
        $marker = '<PackageReference Include="Avalonia.Themes.Fluent" Version="11.2.3" />'
        if ($content.Contains($marker)) {
            $replacement = $marker + "`r`n    " + '<PackageReference Include="Avalonia.Fonts.Inter" Version="11.2.3" />'
            $content = $content.Replace($marker, $replacement)
        } else {
            # Fallback: before the first </ItemGroup> that closes PackageReferences
            $rgx = [regex]'(<PackageReference Include="[^"]+" Version="[^"]+" />)'
            $m = $rgx.Match($content)
            if ($m.Success) {
                $content = $content.Substring(0, $m.Index + $m.Length) +
                           "`r`n    " + '<PackageReference Include="Avalonia.Fonts.Inter" Version="11.2.3" />' +
                           $content.Substring($m.Index + $m.Length)
            } else {
                Write-Log 'Cannot find insertion point in csproj - abort.' 'ERROR'
                exit 1
            }
        }
        [IO.File]::WriteAllText($csprojPath, $content, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.App\MiniCodex.App.csproj (Avalonia.Fonts.Inter)'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.3b.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.3b.1: added Avalonia.Fonts.Inter package (fixes CS1061 WithInterFont).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3b\].*)$', "$entry`$1"
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