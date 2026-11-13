#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.4a - Create build-release.ps1 (no here-strings; line array).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.4a'
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
    '#requires -Version 5.1',
    '<#',
    '.SYNOPSIS',
    '    Builds portable self-contained single-file zip for MiniCodex.',
    '.DESCRIPTION',
    '    Runs dotnet publish, removes *.pdb, removes data/ if present, packs into',
    '    dist/MiniCodex-v{Version}-win-x64.zip, prints size and SHA-256.',
    '.PARAMETER Version',
    '    Version string used in output zip filename. Default: 0.1.0-alpha.',
    '.EXAMPLE',
    '    powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"',
    '    powershell -ExecutionPolicy Bypass -File ".\build-release.ps1" -Version 0.1.1-alpha',
    '#>',
    '[CmdletBinding()]',
    'param(',
    '    [string]$Version = "0.1.0-alpha"',
    ')',
    '',
    '$ErrorActionPreference = "Stop"',
    '',
    'if (-not $PSScriptRoot) {',
    '    Write-Host "ERROR: PSScriptRoot not available; run via -File path."',
    '    exit 1',
    '}',
    '',
    '$root = $PSScriptRoot',
    '$appCsproj = Join-Path $root "src\MiniCodex.App\MiniCodex.App.csproj"',
    '$dist = Join-Path $root "dist"',
    '$publishDir = Join-Path $dist ("MiniCodex-v" + $Version + "-win-x64")',
    '$zipPath = Join-Path $dist ("MiniCodex-v" + $Version + "-win-x64.zip")',
    '',
    'if (-not (Test-Path -LiteralPath $appCsproj)) {',
    '    Write-Host "ERROR: App csproj not found: $appCsproj"',
    '    exit 1',
    '}',
    '',
    'if (-not (Test-Path -LiteralPath $dist)) {',
    '    New-Item -ItemType Directory -Path $dist -Force | Out-Null',
    '}',
    '',
    'Write-Host "== Step 1/4: dotnet publish (Release, win-x64, self-contained, single-file) =="',
    'dotnet publish $appCsproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true -o $publishDir',
    'if ($LASTEXITCODE -ne 0) {',
    '    Write-Host "ERROR: dotnet publish failed."',
    '    exit 1',
    '}',
    '',
    '$exe = Join-Path $publishDir "MiniCodex.exe"',
    'if (-not (Test-Path -LiteralPath $exe)) {',
    '    Write-Host "ERROR: MiniCodex.exe not found in publish output."',
    '    exit 1',
    '}',
    '',
    'Write-Host "== Step 2/4: cleanup (remove *.pdb, remove data/ if present) =="',
    '$pdbFiles = Get-ChildItem -LiteralPath $publishDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue',
    'foreach ($f in $pdbFiles) {',
    '    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue',
    '    Write-Host ("  removed " + $f.Name)',
    '}',
    '$dataDir = Join-Path $publishDir "data"',
    'if (Test-Path -LiteralPath $dataDir) {',
    '    Remove-Item -LiteralPath $dataDir -Recurse -Force',
    '    Write-Host "  removed data/ (should not ship user data)"',
    '}',
    '',
    'Write-Host "== Step 3/4: zip =="',
    'if (Test-Path -LiteralPath $zipPath) {',
    '    Remove-Item -LiteralPath $zipPath -Force',
    '}',
    'Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath -CompressionLevel Optimal',
    '',
    'Write-Host "== Step 4/4: summary =="',
    '$zip = Get-Item -LiteralPath $zipPath',
    '$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash',
    '$fileCount = (Get-ChildItem -LiteralPath $publishDir -Recurse -File).Count',
    'Write-Host ""',
    'Write-Host ("Zip:        " + $zip.FullName)',
    'Write-Host ("Size:       " + [math]::Round($zip.Length/1MB, 1) + " MB")',
    'Write-Host ("SHA256:     " + $sha)',
    'Write-Host ("File count: " + $fileCount)',
    'Write-Host ""',
    'Write-Host "Verify by extracting the zip to a clean folder and running MiniCodex.exe."'
)

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $target = Join-Path $ProjectRoot 'build-release.ps1'
    Backup-File $target
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = $lines -join "`r`n"
    Write-Text -Path $target -Content $content
    Write-Log 'created: build-release.ps1'

    # Sanity checks
    $verify = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)
    if ($verify -match 'param\(') { Write-Log 'verify OK: build-release.ps1 has param block' }
    else { Write-Log 'verify FAIL: param block missing' 'WARN' }
    if ($verify -match 'Compress-Archive') { Write-Log 'verify OK: build-release.ps1 has Compress-Archive' }
    else { Write-Log 'verify FAIL: Compress-Archive missing' 'WARN' }
    if ($verify -match 'Get-FileHash') { Write-Log 'verify OK: build-release.ps1 has SHA-256 hash' }
    else { Write-Log 'verify FAIL: Get-FileHash missing' 'WARN' }

    $sizeBytes = (Get-Item -LiteralPath $target).Length
    $lineCount = (Get-Content -LiteralPath $target).Count
    Write-Log ("build-release.ps1 size: {0} bytes, {1} lines" -f $sizeBytes, $lineCount)

    # Patch README
    $readme = @(
        '# Patch 0.4.4a - build-release.ps1',
        '',
        '**Iteration:** 0.4',
        '',
        '## What it does',
        '',
        'Creates build-release.ps1 at project root. No src/ changes, no README rewrite.',
        '',
        'Script contents (generated via line array, no here-strings):',
        '- param(-Version "0.1.0-alpha")',
        '- dotnet publish -c Release -r win-x64 --self-contained /p:PublishSingleFile=true',
        '- remove *.pdb',
        '- remove data/ if present',
        '- Compress-Archive to dist/MiniCodex-v{Version}-win-x64.zip',
        '- print zip path, size, SHA-256, file count',
        '- uses $PSScriptRoot, works from any cwd',
        '',
        '## DoD',
        '',
        '- build-release.ps1 present at root.',
        '- Verify checks OK in log (param, Compress-Archive, Get-FileHash).',
        '- User can run: powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\build-release.ps1"'
    ) -join "`r`n"
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.4a\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.4a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Added`r`n- 0.4.4a: build-release.ps1 (portable zip builder) at project root.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3z3\.1\].*)$', "$entry`$1"
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