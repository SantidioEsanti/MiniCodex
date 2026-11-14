$ErrorActionPreference = "Stop"
$ver = "0.5.1a9"
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

Log "Starting patch $ver - Fix Cards.Remove compilation error"

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
$content = [IO.File]::ReadAllText($libVm)

$oldCode = @"
            var card = Cards.FirstOrDefault(c => c.Model.Id == m.Id);
            if (card != null) Cards.Remove(card);
"@

$newCode = @"
            var card = Cards.FirstOrDefault(c => c.Model.Id == m.Id);
            if (card != null)
            {
                var newCards = Cards.ToList();
                newCards.Remove(card);
                Cards = newCards;
            }
"@

if ($content -match [regex]::Escape($oldCode)) {
    $content = $content -replace [regex]::Escape($oldCode), $newCode
    [IO.File]::WriteAllText($libVm, $content)
    Log "Fixed Cards.Remove error in OnRemoveFromLibrary."
} else {
    Log "WARNING: Could not find Cards.Remove block. It may have been modified."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Resolved compilation error (CS7036) caused by Cards.Remove on IReadOnlyList.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."