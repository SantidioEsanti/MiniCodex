#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.4 - Release prep: README rewrite, build-release.ps1, screenshots dir.
.DESCRIPTION
    Does NOT change src/. Prepares repository for GitHub v0.1.0-alpha release.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.4'
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

# ============ README.md ============
$readme = @'
# MiniCodex

**Portable 3D model library for artists, collectors, and 3D printing enthusiasts.**

Status: pre-release (v0.1.0-alpha) | Platform: Windows x64 | License: MIT

MiniCodex is a portable Windows desktop application for cataloging 3D models
(STL, OBJ, 3MF, PLY) with a unified model card, associations (references,
renders, photos of finished work, print profiles), tags, search, built-in
3D viewer, and scale converter.

## Screenshots

### Library (light theme)
![Library light](docs/screenshots/01-library-light.png)

### Library (dark theme, hover panel with metadata and rotation)
![Library dark](docs/screenshots/02-library-dark-hover.png)

### Model card - Associations (Reference + Photo)
![Card associations](docs/screenshots/03-card-associations.png)

### Model card - Scale converter
![Card scale](docs/screenshots/04-card-scale.png)

### Settings - Integrations (slicers and 3D editors)
![Settings integrations](docs/screenshots/05-settings-integrations.png)

## Features

- **Library grid** with soft shadows, hover metadata (size, polygons, file
  count), 4-angle preview rotation on hover, context menu, double-click to open
- **Incremental scanning** of source folders (by path + size + modification date)
- **Auto-generated 4-angle previews** cached per model, invalidated by source change
- **Built-in 3D viewer** - drag to rotate, mouse wheel to zoom, wireframe toggle,
  adjustable shadow softness
- **Model card** - unified card with 5 tabs: Associations, Files, Tags, Scale, Notes
- **Associations** - attach reference images and photos of finished work via
  drag-and-drop, auto-link by filename
- **Tags** with usage counts and sidebar filter
- **Search** by name, tag, author, source URL
- **Scale converter** - 43 presets in 7 categories, manual input, bidirectional
  real/model height calculation
- **Integrations** with 12 slicers and 3D editors (Bambu Studio, PrusaSlicer,
  OrcaSlicer, UltiMaker Cura, Lychee, CHITUBOX, Anycubic Slicer, Anycubic
  Slicer Next, Blender, ZBrush, 3D-Coat, Meshmixer) - auto-detect via Registry
  plus manual override
- **Themes** light / dark / auto with amber accent
- **Localization** Russian + English, autodetect by system locale

## Supported formats

STL, OBJ, 3MF, PLY.

ZIP / RAR / 7Z archives are planned for v1.1.

## Portable

MiniCodex does not require installation and does not need admin rights.
All data is stored next to the executable in `./data/`:

- `data/library.db` - SQLite database
- `data/cache/previews/` - preview cache (PNG)
- `data/cache/asset-thumbs/` - association thumbnails
- `data/assets/` - associated files (hybrid storage)

First run creates `data/` automatically.

## Installation

1. Download `MiniCodex-v0.1.0-alpha-win-x64.zip` from
   [Releases](https://github.com/SantidioEsanti/MiniCodex/releases).
2. Extract to any folder (for example `D:\Apps\MiniCodex\`).
3. Run `MiniCodex.exe`.

### First-run note

Windows SmartScreen may warn about an unsigned executable.
Click **More info** -> **Run anyway**. Code signing is planned for a future release.

## System requirements

- Windows 10 or 11, x64
- 100 MB free disk space (plus size of your model library)
- No additional software required (self-contained, .NET runtime bundled)

## Build from source

Requires .NET 8 SDK (or .NET 9 SDK; both build net8.0 targets).
