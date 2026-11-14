$ErrorActionPreference = "Stop"
$ver = "0.5.1a34"
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

Log "Starting patch $ver - Fix ModelFileRepository Map for missing columns"

$files = @(
    "$root\src\MiniCodex.Data\Repositories\ModelFileRepository.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$repoPath = "$root\src\MiniCodex.Data\Repositories\ModelFileRepository.cs"
$repoContent = [IO.File]::ReadAllText($repoPath)

# Fix Map function to safely check FieldCount before accessing column 8
$oldMap = 'FileHash = r.IsDBNull(8) ? null : r.GetString(8),'
$newMap = 'FileHash = r.FieldCount > 8 && !r.IsDBNull(8) ? r.GetString(8) : null,'

if ($repoContent -match [regex]::Escape($oldMap)) {
    $repoContent = $repoContent -replace [regex]::Escape($oldMap), $newMap
    [IO.File]::WriteAllText($repoPath, $repoContent)
    Log "ModelFileRepository.cs: Fixed Map to safely check FieldCount."
} else {
    Log "WARNING: Could not find the FileHash Map line to fix."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Prevented IndexOutOfRangeException in ModelFileRepository.Map when file_hash column is missing.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."