#requires -Version 5.1
<#
.SYNOPSIS
    Builds portable self-contained single-file zip for MiniCodex.
.DESCRIPTION
    Runs dotnet publish, removes *.pdb, removes data/ if present, packs into
    dist/MiniCodex-v{Version}-win-x64.zip, prints size and SHA-256.
.PARAMETER Version
    Version string used in output zip filename. Default: 0.1.0-alpha.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"
    powershell -ExecutionPolicy Bypass -File ".\build-release.ps1" -Version 0.1.1-alpha
#>
[CmdletBinding()]
param(
    [string]$Version = "0.1.0-alpha"
)

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    Write-Host "ERROR: PSScriptRoot not available; run via -File path."
    exit 1
}

$root = $PSScriptRoot
$appCsproj = Join-Path $root "src\MiniCodex.App\MiniCodex.App.csproj"
$dist = Join-Path $root "dist"
$publishDir = Join-Path $dist ("MiniCodex-v" + $Version + "-win-x64")
$zipPath = Join-Path $dist ("MiniCodex-v" + $Version + "-win-x64.zip")

if (-not (Test-Path -LiteralPath $appCsproj)) {
    Write-Host "ERROR: App csproj not found: $appCsproj"
    exit 1
}

if (-not (Test-Path -LiteralPath $dist)) {
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
}
if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}

Write-Host "== Step 1/4: dotnet publish (Release, win-x64, self-contained, single-file) =="
dotnet publish $appCsproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true -o $publishDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: dotnet publish failed."
    exit 1
}

$exe = Join-Path $publishDir "MiniCodex.exe"
if (-not (Test-Path -LiteralPath $exe)) {
    $fallback = Join-Path $publishDir "MiniCodex.App.exe"
    if (Test-Path -LiteralPath $fallback) {
        $exe = $fallback
        Write-Host "  note: using MiniCodex.App.exe (AssemblyName not set in csproj)"
    } else {
        Write-Host "ERROR: exe not found in publish output. Contents:"
        Get-ChildItem -LiteralPath $publishDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("    " + $_.Name) }
        exit 1
    }
}

Write-Host "== Step 2/4: cleanup (remove *.pdb, remove data/ if present) =="
$pdbFiles = Get-ChildItem -LiteralPath $publishDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue
foreach ($f in $pdbFiles) {
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    Write-Host ("  removed " + $f.Name)
}
$dataDir = Join-Path $publishDir "data"
if (Test-Path -LiteralPath $dataDir) {
    Remove-Item -LiteralPath $dataDir -Recurse -Force
    Write-Host "  removed data/ (should not ship user data)"
}

Write-Host "== Step 3/4: zip =="
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "== Step 4/4: summary =="
$zip = Get-Item -LiteralPath $zipPath
$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$fileCount = (Get-ChildItem -LiteralPath $publishDir -Recurse -File).Count
Write-Host ""
Write-Host ("Zip:        " + $zip.FullName)
Write-Host ("Size:       " + [math]::Round($zip.Length/1MB, 1) + " MB")
Write-Host ("SHA256:     " + $sha)
Write-Host ("File count: " + $fileCount)
Write-Host ""
Write-Host "Verify by extracting the zip to a clean folder and running MiniCodex.exe."