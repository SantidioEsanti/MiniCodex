$ErrorActionPreference = "Stop"
$ver = "0.5.0a18"
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

Log "Starting patch $ver - Add margin for shadow space"

$files = @(
    "$root\src\MiniCodex.App\Views\ModelCardTile.axaml",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Update ModelCardTile.axaml
$cardAxaml = "$root\src\MiniCodex.App\Views\ModelCardTile.axaml"
$content = [IO.File]::ReadAllText($cardAxaml)

# Add margin and clip to bounds to UserControl
if ($content -match '<UserControl[^>]*>') {
    $oldTag = $matches[0]
    $newTag = $oldTag -replace '\s*Margin="[^"]*"', ''
    $newTag = $newTag -replace '\s*ClipToBounds="[^"]*"', ''
    $newTag = $newTag -replace '>$', ' Margin="8,8,8,28" ClipToBounds="False">'
    $content = $content -replace $oldTag, $newTag
}

# Ensure root Border inside tile does not clip the shadow
if ($content -match '(<Border[^>]*BoxShadow="\{DynamicResource CardShadow\}")') {
    $borderTag = $matches[1]
    if ($borderTag -notmatch 'ClipToBounds=') {
        $content = $content -replace $borderTag, "$borderTag ClipToBounds=`"False`""
    }
}

[IO.File]::WriteAllText($cardAxaml, $content)
Log "ModelCardTile.axaml updated with margin and no clipping."

# 2. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$libContent = [IO.File]::ReadAllText($libAxaml)

# Disable clipping on ItemsControl and WrapPanel
$libContent = $libContent -replace '<ItemsControl ItemsSource="\{Binding Cards\}"', '<ItemsControl ItemsSource="{Binding Cards}" ClipToBounds="False"'
$libContent = $libContent -replace '<WrapPanel Orientation="Horizontal"/>', '<WrapPanel Orientation="Horizontal" ClipToBounds="False"/>'

[IO.File]::WriteAllText($libAxaml, $libContent)
Log "LibraryView.axaml updated to disable clipping."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Added Margin to ModelCardTile and disabled ClipToBounds on ItemsControl/WrapPanel so shadows are no longer cut off.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."