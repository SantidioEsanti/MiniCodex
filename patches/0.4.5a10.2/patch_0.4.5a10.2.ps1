#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a10.2 - Fix CS1061: Mesh.NormalCount -> mesh.Normals.Count (AssimpNet 4.1.0).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a10.2'
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

    $loaderPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'
    Backup-File $loaderPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    $original = $content

    # AssimpNet 4.1.0: mesh.NormalCount does not exist; use mesh.Normals.Count
    $content = $content.Replace(
        'var meshHasNormals = mesh.NormalCount == mesh.VertexCount && mesh.VertexCount > 0;',
        'var meshHasNormals = mesh.Normals != null && mesh.Normals.Count == mesh.VertexCount && mesh.VertexCount > 0;'
    )

    # Also defensive: any other NormalCount references
    $content = $content -replace '\.NormalCount\b', '.Normals.Count'

    if ($content -ne $original) {
        [IO.File]::WriteAllText($loaderPath, $content, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: AssimpMeshLoader.cs (NormalCount -> Normals.Count)'
    } else {
        Write-Log 'AssimpMeshLoader.cs: pattern not found, checking existing content.' 'WARN'
    }

    # Verify
    $verify = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    if ($verify -match 'NormalCount') {
        Write-Log 'verify FAIL: NormalCount still present' 'WARN'
    } else {
        Write-Log 'verify OK: no NormalCount references'
    }
    if ($verify -match 'mesh\.Normals\.Count == mesh\.VertexCount') {
        Write-Log 'verify OK: Normals.Count check in place'
    } else {
        Write-Log 'verify FAIL: Normals.Count check missing' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a10.2 - Fix CS1061 Mesh.NormalCount

**Iteration:** 0.4.5

## Cause

AssimpNet 4.1.0 (the NuGet we use) does not expose Mesh.NormalCount.
Mesh.Normals is List<Vector3D>, so use .Count. Same for Mesh.Vertices.

0.4.5a10 used:
  mesh.NormalCount == mesh.VertexCount

Correct form:
  mesh.Normals != null && mesh.Normals.Count == mesh.VertexCount

## Fix

Replace NormalCount reference with Normals.Count and add null check.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a10.2\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a10.2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a10.2: AssimpMeshLoader NormalCount -> Normals.Count (CS1061, AssimpNet 4.1.0).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a10\.1\].*)$', "$entry`$1"
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