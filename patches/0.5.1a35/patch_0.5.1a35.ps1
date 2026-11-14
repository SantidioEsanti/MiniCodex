$ErrorActionPreference = "Stop"
$ver = "0.5.1a35"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Register Migration_0004 in DatabaseInitializer"

$files = @(
    "$root\src\MiniCodex.Data\DatabaseInitializer.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$initPath = "$root\src\MiniCodex.Data\DatabaseInitializer.cs"
$content = [IO.File]::ReadAllText($initPath)

$oldCode = "new Migration_0003_ModelOrientation(),"
$newCode = "new Migration_0003_ModelOrientation(),`r`n        new Migration_0004_ModelFile_Hash(),"

if ($content -match [regex]::Escape($oldCode) -and $content -notmatch "Migration_0004_ModelFile_Hash") {
    $content = $content -replace [regex]::Escape($oldCode), $newCode
    [IO.File]::WriteAllText($initPath, $content)
    Log "DatabaseInitializer.cs updated with Migration_0004."
} else {
    Log "WARNING: Could not find Migration_0003 to inject after, or Migration_0004 already present."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Data: Registered Migration_0004_ModelFile_Hash to enable `file_hash` column creation.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."