#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a5.1 - Fix StubRenderer signature (CS0535, added supersample param).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a5.1'
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

    $testPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs'
    Backup-File $testPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($testPath, [Text.Encoding]::UTF8)

    # Match both variants: with or without trailing RenderStyle
    $old1 = 'public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null)'
    $old2 = 'public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f)'
    $newSig = 'public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null, int supersample = 2)'

    if ($content.Contains($old1)) {
        $content = $content.Replace($old1, $newSig)
        [IO.File]::WriteAllText($testPath, $content, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: PreviewGeneratorTests.cs (StubRenderer.Render + supersample)'
    } elseif ($content.Contains($old2)) {
        $content = $content.Replace($old2, $newSig)
        [IO.File]::WriteAllText($testPath, $content, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: PreviewGeneratorTests.cs (StubRenderer.Render + supersample, from short signature)'
    } elseif ($content -match 'int supersample = 2') {
        Write-Log 'PreviewGeneratorTests.cs: supersample already present, skipping.' 'WARN'
    } else {
        Write-Log 'PreviewGeneratorTests.cs: Render signature not found - manual check needed.' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a5.1 - Fix StubRenderer signature

**Iteration:** 0.4.5

## Cause
0.4.5a5 added `int supersample = 2` to IPreviewRenderer.Render.
StubRenderer in PreviewGeneratorTests.cs still implemented the old signature (CS0535).

## Fix
Add `RenderStyle? style = null, int supersample = 2` to StubRenderer.Render.

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a5.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a5.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a5.1: StubRenderer signature in PreviewGeneratorTests (added supersample param, CS0535).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a5\].*)$', "$entry`$1"
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