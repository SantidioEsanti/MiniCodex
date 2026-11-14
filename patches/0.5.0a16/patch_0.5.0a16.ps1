$ErrorActionPreference = "Stop"
$ver = "0.5.0a16"
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

Log "Starting patch $ver - Fix shadow corners and clipping"

$files = @(
    "$root\src\MiniCodex.App\Views\ModelCardTile.axaml",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\src\MiniCodex.App\Views\MainWindow.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

function Fix-ShadowElement($filePath) {
    if (-not (Test-Path $filePath)) { return }
    $lines = [IO.File]::ReadAllLines($filePath)
    $newLines = @()
    $modified = $false

    foreach ($line in $lines) {
        if ($line -match 'BoxShadow="\{DynamicResource (CardShadow|GlassPanelShadow)\}"') {
            # Replace existing CornerRadius or add if missing
            if ($line -match 'CornerRadius="[^"]*"') {
                $line = $line -replace 'CornerRadius="[^"]*"', 'CornerRadius="{DynamicResource CornerRadiusLarge}"'
            } else {
                $line = $line -replace '(\s*)/?>$', ' CornerRadius="{DynamicResource CornerRadiusLarge}"$1>'
            }
            
            # Add ClipToBounds if missing
            if ($line -notmatch 'ClipToBounds=') {
                $line = $line -replace '(\s*)/?>$', ' ClipToBounds="True"$1>'
            }
            $modified = $true
        }
        $newLines += $line
    }

    if ($modified) {
        [IO.File]::WriteAllLines($filePath, $newLines)
        Log "Updated shadow corners and clipping in $(Split-Path $filePath -Leaf)"
    }
}

# 1. Fix ModelCardTile.axaml
Fix-ShadowElement "$root\src\MiniCodex.App\Views\ModelCardTile.axaml"

# 2. Fix LibraryView.axaml
Fix-ShadowElement "$root\src\MiniCodex.App\Views\LibraryView.axaml"

# 3. Fix MainWindow.axaml
Fix-ShadowElement "$root\src\MiniCodex.App\Views\MainWindow.axaml"

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Ensured elements with BoxShadow have CornerRadius and ClipToBounds to prevent rectangular "tile" shadows.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."