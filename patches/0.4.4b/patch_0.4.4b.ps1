#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.4b - Rewrite README.md (line array, no here-strings).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.4b'
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

$lines = @(
    '# MiniCodex',
    '',
    '**Portable 3D model library for artists, collectors, and 3D printing enthusiasts.**',
    '',
    'Status: pre-release (v0.1.0-alpha) | Platform: Windows x64 | License: MIT',
    '',
    'MiniCodex is a portable Windows desktop application for cataloging 3D models',
    '(STL, OBJ, 3MF, PLY) with a unified model card, associations (references,',
    'renders, photos of finished work, print profiles), tags, search, built-in',
    '3D viewer, and scale converter.',
    '',
    '## Screenshots',
    '',
    '### Library (light theme)',
    '![Library light](docs/screenshots/01-library-light.png)',
    '',
    '### Library (dark theme, hover panel with metadata and rotation)',
    '![Library dark](docs/screenshots/02-library-dark-hover.png)',
    '',
    '### Model card - Associations (Reference + Photo)',
    '![Card associations](docs/screenshots/03-card-associations.png)',
    '',
    '### Model card - Scale converter',
    '![Card scale](docs/screenshots/04-card-scale.png)',
    '',
    '### Settings - Integrations (slicers and 3D editors)',
    '![Settings integrations](docs/screenshots/05-settings-integrations.png)',
    '',
    '## Features',
    '',
    '- **Library grid** with soft shadows, hover metadata (size, polygons, file',
    '  count), 4-angle preview rotation on hover, context menu, double-click to open',
    '- **Incremental scanning** of source folders (by path, size, and modification date)',
    '- **Auto-generated 4-angle previews** cached per model, invalidated by source change',
    '- **Built-in 3D viewer** - drag to rotate, mouse wheel to zoom, wireframe toggle,',
    '  adjustable shadow softness',
    '- **Model card** - unified card with 5 tabs: Associations, Files, Tags, Scale, Notes',
    '- **Associations** - attach reference images and photos of finished work via',
    '  drag-and-drop, auto-link by filename',
    '- **Tags** with usage counts and sidebar filter',
    '- **Search** by name, tag, author, source URL',
    '- **Scale converter** - 43 presets in 7 categories, manual input, bidirectional',
    '  real/model height calculation',
    '- **Integrations** with 12 slicers and 3D editors (Bambu Studio, PrusaSlicer,',
    '  OrcaSlicer, UltiMaker Cura, Lychee, CHITUBOX, Anycubic Slicer, Anycubic',
    '  Slicer Next, Blender, ZBrush, 3D-Coat, Meshmixer) - auto-detect via Registry',
    '  plus manual override',
    '- **Themes** light / dark / auto with amber accent',
    '- **Localization** Russian + English, autodetect by system locale',
    '',
    '## Supported formats',
    '',
    'STL, OBJ, 3MF, PLY.',
    '',
    'ZIP / RAR / 7Z archives are planned for v1.1.',
    '',
    '## Portable',
    '',
    'MiniCodex does not require installation and does not need admin rights.',
    'All data is stored next to the executable in `./data/`:',
    '',
    '- `data/library.db` - SQLite database',
    '- `data/cache/previews/` - preview cache (PNG)',
    '- `data/cache/asset-thumbs/` - association thumbnails',
    '- `data/assets/` - associated files (hybrid storage)',
    '',
    'First run creates `data/` automatically.',
    '',
    '## Installation',
    '',
    '1. Download `MiniCodex-v0.1.0-alpha-win-x64.zip` from the',
    '   [Releases](https://github.com/SantidioEsanti/MiniCodex/releases) page.',
    '2. Extract to any folder (for example `D:\Apps\MiniCodex\`).',
    '3. Run `MiniCodex.exe`.',
    '',
    '### First-run note',
    '',
    'Windows SmartScreen may warn about an unsigned executable.',
    'Click **More info** -> **Run anyway**. Code signing is planned for a future release.',
    '',
    '## System requirements',
    '',
    '- Windows 10 or 11, x64',
    '- 100 MB free disk space (plus size of your model library)',
    '- No additional software required (self-contained, .NET runtime bundled)',
    '',
    '## Build from source',
    '',
    'Requires .NET 8 SDK (or .NET 9 SDK; both build net8.0 targets).',
    '',
    '```',
    'git clone https://github.com/SantidioEsanti/MiniCodex.git',
    'cd MiniCodex',
    'dotnet build src/MiniCodex.sln',
    'dotnet test src/MiniCodex.sln',
    '```',
    '',
    '### Build portable zip',
    '',
    '```',
    'powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"',
    '```',
    '',
    'Output: `dist/MiniCodex-v0.1.0-alpha-win-x64.zip`.',
    '',
    '## Documentation',
    '',
    '- [HANDOFF](docs/HANDOFF.md) - current project state, architecture, patch workflow',
    '- [ROADMAP](docs/ROADMAP.md) - MVP roadmap',
    '- [ARCHITECTURE](docs/ARCHITECTURE.md) - architectural decisions',
    '- [DB_SCHEMA](docs/DB_SCHEMA.md) - database schema',
    '- [UI_UX](docs/UI_UX.md) - screens specification',
    '- [SCALES](docs/SCALES.md) - scale presets table',
    '',
    '## Development status',
    '',
    'MVP is complete. v0.1.0-alpha is the first pre-release.',
    'See [ROADMAP](docs/ROADMAP.md) for the list of deferred features (v1.1+).',
    '',
    'Solo development. Feedback welcome via GitHub Issues.',
    '',
    '## Support the author',
    '',
    'If MiniCodex is useful to you, you can support the author on',
    '[Boosty](https://boosty.to/santidioesanti).',
    'Completely optional - the project is and will remain free.',
    '',
    '## Trademarks',
    '',
    'Names of slicers and 3D editors (Bambu Studio, PrusaSlicer, OrcaSlicer, UltiMaker',
    'Cura, Lychee Slicer, CHITUBOX, Anycubic Slicer, Anycubic Slicer Next, Blender,',
    'ZBrush, 3D-Coat, Meshmixer) are property of their respective owners. MiniCodex',
    'is not affiliated with them and does not claim their trademarks. Integrations',
    'work by launching external executables configured by the user.',
    '',
    '## License',
    '',
    'MIT. See [LICENSE](LICENSE).',
    '',
    'Copyright (c) 2026 Santidio Esanti.'
)

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $readmePath = Join-Path $ProjectRoot 'README.md'
    Backup-File $readmePath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = $lines -join "`r`n"
    Write-Text -Path $readmePath -Content $content
    Write-Log 'updated: README.md'

    # Sanity checks
    $verify = [IO.File]::ReadAllText($readmePath, [Text.Encoding]::UTF8)
    $checks = @(
        @('screenshot 01', ($verify -match '01-library-light\.png')),
        @('screenshot 05', ($verify -match '05-settings-integrations\.png')),
        @('GitHub releases link', ($verify -match 'github\.com/SantidioEsanti/MiniCodex')),
        @('Boosty link', ($verify -match 'boosty\.to/santidioesanti')),
        @('portable section', ($verify -match 'data/library\.db')),
        @('MIT license', ($verify -match 'MIT\. See'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }
    $sizeBytes = (Get-Item -LiteralPath $readmePath).Length
    $lineCount = (Get-Content -LiteralPath $readmePath).Count
    Write-Log ("README.md size: {0} bytes, {1} lines" -f $sizeBytes, $lineCount)

    # Patch README (patches\0.4.4b\README.md)
    $patchReadme = @(
        '# Patch 0.4.4b - README rewrite',
        '',
        '**Iteration:** 0.4',
        '',
        '## What it does',
        '',
        'README.md rewritten via line array (no here-strings - safe from parser issues).',
        '',
        'Sections: description, 5 screenshots, features, supported formats, portable',
        'structure, installation (with SmartScreen note), system requirements, build',
        'from source, documentation links, development status, Boosty, trademarks, MIT.',
        '',
        '## DoD',
        '',
        '- README.md ~135 lines, 5 screenshot references.',
        '- Verify checks OK: screenshot 01/05, GitHub, Boosty, portable, MIT.',
        '- Next: save 5 screenshots to docs/screenshots/, then run build-release.ps1.'
    ) -join "`r`n"
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $patchReadme
    Write-Log 'created: patches\0.4.4b\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.4b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.1.0-alpha] - 2026-11-12`r`n`r`n### Released`r`n- First public pre-release. Portable Windows x64 build.`r`n- README rewritten with 5 screenshots, features, install instructions.`r`n- build-release.ps1 for reproducible portable build.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3z3\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated (0.1.0-alpha entry).'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}