#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a13.1 - Fix CS0103 (Log using) + CS8602 (mesh.Normals null deref).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a13.1'
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

    $cardVmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $loaderPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'

    Backup-File $cardVmPath
    Backup-File $loaderPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ 1. Add using MiniCodex.Core.Logging to ModelCardPageViewModel ============
    $cardVm = [IO.File]::ReadAllText($cardVmPath, [Text.Encoding]::UTF8)
    if ($cardVm -notmatch 'using MiniCodex\.Core\.Logging;') {
        $anchor = 'using MiniCodex.Core.Models;'
        if ($cardVm.Contains($anchor)) {
            $cardVm = $cardVm.Replace($anchor, 'using MiniCodex.Core.Logging;' + "`r`n" + $anchor)
            [IO.File]::WriteAllText($cardVmPath, $cardVm, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: ModelCardPageViewModel.cs (using MiniCodex.Core.Logging)'
        } else {
            Write-Log 'ModelCardPageViewModel.cs: anchor "using MiniCodex.Core.Models;" not found' 'WARN'
        }
    } else {
        Write-Log 'ModelCardPageViewModel.cs: using MiniCodex.Core.Logging already present' 'WARN'
    }

    # ============ 2. Fix CS8602 in AssimpMeshLoader ============
    $loader = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    $original = $loader

    # mesh.Normals[i] -> mesh.Normals![i]
    $loader = $loader -replace '(\s)var n = mesh\.Normals\[i\];', '$1var n = mesh.Normals![i];'

    if ($loader -ne $original) {
        [IO.File]::WriteAllText($loaderPath, $loader, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: AssimpMeshLoader.cs (mesh.Normals![i] - null-forgiving)'
    } else {
        Write-Log 'AssimpMeshLoader.cs: pattern not matched, checking current state.' 'WARN'
    }

    # Verify
    $vLoader = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    if ($vLoader -match 'mesh\.Normals!\[i\]') {
        Write-Log 'verify OK: null-forgiving on mesh.Normals[i]'
    } else {
        Write-Log 'verify FAIL: null-forgiving not applied' 'WARN'
    }

    $vCard = [IO.File]::ReadAllText($cardVmPath, [Text.Encoding]::UTF8)
    if ($vCard -match 'using MiniCodex\.Core\.Logging;') {
        Write-Log 'verify OK: Logging using present'
    } else {
        Write-Log 'verify FAIL: Logging using missing' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a13.1 - Fix compile errors

**Iteration:** 0.4.5

## Cause

1. CS0103: ModelCardPageViewModel uses Log.Exception in ScheduleSave/DebouncedSaveAsync,
   but no `using MiniCodex.Core.Logging;` was added.

2. CS8602 (warning): AssimpMeshLoader line ~99 `mesh.Normals[i]` - compiler cannot prove
   non-null even though meshHasNormals guarantees it.

## Fix

1. Add `using MiniCodex.Core.Logging;` to ModelCardPageViewModel.cs.
2. Use null-forgiving operator: `mesh.Normals![i]`.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a13.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a13.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a13.1: ModelCardPageViewModel missing `using MiniCodex.Core.Logging;` (CS0103).`r`n- 0.4.5a13.1: AssimpMeshLoader mesh.Normals![i] null-forgiving (CS8602).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a13\].*)$', "$entry`$1"
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