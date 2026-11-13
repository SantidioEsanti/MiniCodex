#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.4c - Fix exe name: set AssemblyName=MiniCodex, make build-release.ps1 accept both names, clean publish dir.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.4c'
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
    $buildPath  = Join-Path $ProjectRoot 'build-release.ps1'

    Backup-File $csprojPath
    Backup-File $buildPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ---- 1. csproj: add AssemblyName=MiniCodex ----
    $csproj = [IO.File]::ReadAllText($csprojPath, [Text.Encoding]::UTF8)
    if ($csproj -notmatch '<AssemblyName>') {
        $oldLine = '    <OutputType>WinExe</OutputType>'
        $newLine = '    <OutputType>WinExe</OutputType>' + "`r`n" +
                   '    <AssemblyName>MiniCodex</AssemblyName>'
        if ($csproj.Contains($oldLine)) {
            $csproj = $csproj.Replace($oldLine, $newLine)
            [IO.File]::WriteAllText($csprojPath, $csproj, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: MiniCodex.App.csproj (AssemblyName=MiniCodex)'
        } else {
            Write-Log 'csproj: OutputType WinExe line not found' 'WARN'
        }
    } else {
        Write-Log 'csproj: AssemblyName already present' 'WARN'
    }

    # ---- 2. build-release.ps1: cleanup publish dir before publish ----
    $build = [IO.File]::ReadAllText($buildPath, [Text.Encoding]::UTF8)

    $oldDistBlock = 'if (-not (Test-Path -LiteralPath $dist)) {' + "`r`n" +
                    '    New-Item -ItemType Directory -Path $dist -Force | Out-Null' + "`r`n" +
                    '}'
    $newDistBlock = $oldDistBlock + "`r`n" +
                    'if (Test-Path -LiteralPath $publishDir) {' + "`r`n" +
                    '    Remove-Item -LiteralPath $publishDir -Recurse -Force' + "`r`n" +
                    '}'
    if ($build.Contains($oldDistBlock) -and ($build -notmatch 'Remove-Item -LiteralPath \$publishDir -Recurse')) {
        $build = $build.Replace($oldDistBlock, $newDistBlock)
        Write-Log 'build-release.ps1: add cleanup of old publish dir'
    }

    # ---- 3. build-release.ps1: accept both exe names ----
    $oldCheck = '$exe = Join-Path $publishDir "MiniCodex.exe"' + "`r`n" +
                'if (-not (Test-Path -LiteralPath $exe)) {' + "`r`n" +
                '    Write-Host "ERROR: MiniCodex.exe not found in publish output."' + "`r`n" +
                '    exit 1' + "`r`n" +
                '}'
    $newCheck = '$exe = Join-Path $publishDir "MiniCodex.exe"' + "`r`n" +
                'if (-not (Test-Path -LiteralPath $exe)) {' + "`r`n" +
                '    $fallback = Join-Path $publishDir "MiniCodex.App.exe"' + "`r`n" +
                '    if (Test-Path -LiteralPath $fallback) {' + "`r`n" +
                '        $exe = $fallback' + "`r`n" +
                '        Write-Host "  note: using MiniCodex.App.exe (AssemblyName not set in csproj)"' + "`r`n" +
                '    } else {' + "`r`n" +
                '        Write-Host "ERROR: exe not found in publish output. Contents:"' + "`r`n" +
                '        Get-ChildItem -LiteralPath $publishDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("    " + $_.Name) }' + "`r`n" +
                '        exit 1' + "`r`n" +
                '    }' + "`r`n" +
                '}'
    if ($build.Contains($oldCheck)) {
        $build = $build.Replace($oldCheck, $newCheck)
        Write-Log 'build-release.ps1: accept both MiniCodex.exe and MiniCodex.App.exe'
    } else {
        Write-Log 'build-release.ps1: exe check block not found (may already be patched)' 'WARN'
    }

    [IO.File]::WriteAllText($buildPath, $build, [Text.UTF8Encoding]::new($false))

    # ---- Verify ----
    $verifyCsproj = [IO.File]::ReadAllText($csprojPath, [Text.Encoding]::UTF8)
    if ($verifyCsproj -match '<AssemblyName>MiniCodex</AssemblyName>') {
        Write-Log 'verify OK: csproj AssemblyName=MiniCodex'
    } else { Write-Log 'verify FAIL: AssemblyName not set' 'WARN' }

    $verifyBuild = [IO.File]::ReadAllText($buildPath, [Text.Encoding]::UTF8)
    if ($verifyBuild -match 'MiniCodex\.App\.exe') {
        Write-Log 'verify OK: build-release.ps1 has fallback for MiniCodex.App.exe'
    } else { Write-Log 'verify FAIL: fallback not added' 'WARN' }
    if ($verifyBuild -match 'Remove-Item -LiteralPath \$publishDir -Recurse') {
        Write-Log 'verify OK: build-release.ps1 cleans old publish dir'
    } else { Write-Log 'verify WARN: publish dir cleanup may not be present' 'WARN' }

    # ---- README patch ----
    $readme = @(
        '# Patch 0.4.4c - Fix exe name',
        '',
        '**Iteration:** 0.4',
        '',
        '## Cause',
        '',
        'dotnet publish produced MiniCodex.App.exe (from csproj name),',
        'but build-release.ps1 checked for MiniCodex.exe and exited with error',
        'before running Compress-Archive. No zip was created.',
        '',
        '## Fix',
        '',
        '1. MiniCodex.App.csproj: add AssemblyName=MiniCodex',
        '   -> exe becomes MiniCodex.exe (user-friendly)',
        '2. build-release.ps1: remove old publish dir before publishing',
        '   (avoids stale MiniCodex.App.exe alongside new MiniCodex.exe)',
        '3. build-release.ps1: accept both MiniCodex.exe and MiniCodex.App.exe',
        '   (defensive fallback; print publish dir contents on failure)',
        '',
        '## DoD',
        '',
        '- csproj has AssemblyName=MiniCodex.',
        '- build-release.ps1 has fallback + cleanup.',
        '- Re-run build-release.ps1 -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip created.',
        '- Zip contains MiniCodex.exe.'
    ) -join "`r`n"
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.4c\README.md'

    # ---- CHANGELOG ----
    $marker = '<!-- patch 0.4.4c applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.4c: exe name MiniCodex.exe (csproj AssemblyName), build-release.ps1 accepts both names, cleans old publish dir.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.1\.0-alpha\].*)$', "$entry`$1"
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