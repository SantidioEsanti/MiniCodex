$ErrorActionPreference = "Stop"
$ver = "0.5.1a15"
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

Log "Starting patch $ver - Hotfix for Cards read-only assignment"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$lines = [IO.File]::ReadAllLines($libVm)
$newLines = @()
$modified = $false

foreach ($line in $lines) {
    # Remove any line that tries to assign to the get-only Cards property
    if ($line -match '^\s*Cards\s*=\s*') {
        $modified = $true
        continue
    }
    
    # Remove the obsolete newCards variable declaration
    if ($line -match 'var newCards = Cards\.ToList\(\);') {
        $modified = $true
        continue
    }
    
    # Replace newCards.Remove with Cards.Remove
    if ($line -match 'newCards\.Remove\(card\);') {
        $line = $line -replace 'newCards\.Remove\(card\);', 'Cards.Remove(card);'
        $modified = $true
    }
    
    $newLines += $line
}

if ($modified) {
    [IO.File]::WriteAllLines($libVm, $newLines)
    Log "Cleaned up read-only Cards assignments in LibraryViewModel."
} else {
    Log "WARNING: No changes made. File may already be clean."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Resolved compilation errors (CS0200/CS0103) by removing leftover Cards assignments from virtualization revert.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."