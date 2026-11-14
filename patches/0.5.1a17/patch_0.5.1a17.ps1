$ErrorActionPreference = "Stop"
$ver = "0.5.1a17"
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

Log "Starting patch $ver - Fix literal backtick-n in C# code"

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
    # Check if the line contains the literal backtick-n sequence
    if ($line.Contains('`n')) {
        # Split it into multiple lines and add to the new collection
        $parts = $line.Split([string[]]@('`n'), [StringSplitOptions]::None)
        foreach ($p in $parts) {
            $newLines += $p
        }
        $modified = $true
    } else {
        $newLines += $line
    }
}

if ($modified) {
    [IO.File]::WriteAllLines($libVm, $newLines)
    Log "Fixed literal backtick-n by splitting into new lines."
} else {
    Log "No literal backtick-n found. File may already be clean."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Resolved C# compilation errors (CS1056/CS1002) caused by literal backtick-n characters in LibraryViewModel.cs.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."