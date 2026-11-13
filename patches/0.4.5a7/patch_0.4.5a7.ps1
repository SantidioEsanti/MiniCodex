#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a7 - Two-sided lighting (Math.Abs on lambert) fixes STL inconsistent winding sparkle.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a7'
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

    $rendererPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    $previewGenPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'

    Backup-File $rendererPath
    Backup-File $previewGenPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ 1. Math.Abs on lambert in renderer ============
    $renderer = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    $oldLambert = 'var lambert = MathF.Max(style.MinLambert, Vector3.Dot(normal, lightDir));'
    $newLambert = 'var lambert = MathF.Max(style.MinLambert, MathF.Abs(Vector3.Dot(normal, lightDir)));'
    if ($renderer.Contains($oldLambert)) {
        $renderer = $renderer.Replace($oldLambert, $newLambert)
        [IO.File]::WriteAllText($rendererPath, $renderer, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: SkiaPreviewRenderer.cs (two-sided lighting)'
    } elseif ($renderer.Contains('MathF.Abs(Vector3.Dot(normal, lightDir))')) {
        Write-Log 'SkiaPreviewRenderer.cs: two-sided lighting already present, skipping.' 'WARN'
    } else {
        Write-Log 'SkiaPreviewRenderer.cs: lambert line not found - manual check needed.' 'WARN'
    }

    # ============ 2. Bump RendererVersion to force regen ============
    $previewGen = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($previewGen -match 'RendererVersion\s*=\s*"0\.4\.5a6"') {
        $previewGen = $previewGen -replace 'RendererVersion\s*=\s*"0\.4\.5a6"', 'RendererVersion = "0.4.5a7"'
        [IO.File]::WriteAllText($previewGenPath, $previewGen, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: PreviewGenerator.cs (RendererVersion = 0.4.5a7)'
    } elseif ($previewGen -match 'RendererVersion\s*=\s*"0\.4\.5a7"') {
        Write-Log 'PreviewGenerator.cs: RendererVersion already 0.4.5a7, skipping.' 'WARN'
    } else {
        Write-Log 'PreviewGenerator.cs: RendererVersion string not found - manual check needed.' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a7 - Two-sided lighting

**Iteration:** 0.4.5

## Root cause (from 0.4.5a6 screenshot)

STL files produced by different generators have inconsistent face winding.
Some triangles are CW, some CCW. We compute normal = cross(edge1, edge2) from
the winding, so adjacent triangles on the same surface get opposite normals.

Rendering (single-sided):
- Normal points toward light: dot > 0, lambert = 0.8..1.0 -> WHITE
- Normal points away from light: dot < 0, lambert = MinLambert (0.4) -> DARK GREY

Adjacent triangles on one plane -> white sparkle next to dark grey -> visible "noise".

## Fix

Math.Abs on the dot product (two-sided lighting):

  var lambert = MathF.Max(style.MinLambert, MathF.Abs(Vector3.Dot(normal, lightDir)));

Standard technique for STL rendering when winding is not unified.
Both faces of each triangle render with correct lambert shading based on |angle| to light.

RendererVersion bumped to "0.4.5a7" - forces preview regeneration.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate automatically.
- No white sparkle on any model. All models render as solid shaded silhouettes.
- Layer-line texture (from 3D-printed scans) remains visible as intended surface detail.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a7\README.md'

    # Verify
    $verifyR = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    if ($verifyR -match 'MathF\.Abs\(Vector3\.Dot') {
        Write-Log 'verify OK: two-sided lighting in renderer'
    } else {
        Write-Log 'verify FAIL: MathF.Abs not found' 'WARN'
    }

    $verifyP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($verifyP -match '"0\.4\.5a7"') {
        Write-Log 'verify OK: RendererVersion = 0.4.5a7'
    } else {
        Write-Log 'verify FAIL: RendererVersion not bumped' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a7 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a7] - 2026-11-12`r`n`r`n### Fixed`r`n- STL white-sparkle artifacts: two-sided lighting (MathF.Abs on lambert dot).`r`n`r`n### Changed`r`n- RendererVersion 0.4.5a7 - forces preview regeneration.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a6\].*)$', "$entry`$1"
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