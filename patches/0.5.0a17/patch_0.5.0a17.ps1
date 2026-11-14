$ErrorActionPreference = "Stop"
$ver = "0.5.0a17"
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

Log "Starting patch $ver - Restore and widen shadows, remove clipping"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
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

# 1. Update Shadows in App.axaml to be wider and softer
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$appContent = [IO.File]::ReadAllText($appAxaml)

$appContent = $appContent -replace '<BoxShadows x:Key="CardShadow">.*?</BoxShadows>', '<BoxShadows x:Key="CardShadow">0 12 32 0 #2E000000</BoxShadows>'
$appContent = $appContent -replace '<BoxShadows x:Key="GlassPanelShadow">.*?</BoxShadows>', '<BoxShadows x:Key="GlassPanelShadow">0 8 24 0 #1A000000</BoxShadows>'

[IO.File]::WriteAllText($appAxaml, $appContent)
Log "App.axaml updated with wider shadows."

# 2. Remove ClipToBounds and ensure CornerRadius on shadowed elements
function Fix-ShadowElement($filePath) {
    if (-not (Test-Path $filePath)) { return }
    $lines = [IO.File]::ReadAllLines($filePath)
    $newLines = @()
    $modified = $false

    foreach ($line in $lines) {
        if ($line -match 'BoxShadow="\{DynamicResource (CardShadow|GlassPanelShadow)\}"') {
            # Remove ClipToBounds completely
            $line = $line -replace '\s*ClipToBounds="True"', ''
            $line = $line -replace '\s*ClipToBounds="False"', ''
            
            # Ensure CornerRadius is present
            if ($line -match 'CornerRadius="[^"]*"') {
                $line = $line -replace 'CornerRadius="[^"]*"', 'CornerRadius="{DynamicResource CornerRadiusLarge}"'
            } else {
                $line = $line -replace '(\s*)/?>$', ' CornerRadius="{DynamicResource CornerRadiusLarge}"$1>'
            }
            $modified = $true
        }
        $newLines += $line
    }

    if ($modified) {
        [IO.File]::WriteAllLines($filePath, $newLines)
        Log "Updated shadow settings in $(Split-Path $filePath -Leaf)"
    }
}

Fix-ShadowElement "$root\src\MiniCodex.App\Views\ModelCardTile.axaml"
Fix-ShadowElement "$root\src\MiniCodex.App\Views\LibraryView.axaml"
Fix-ShadowElement "$root\src\MiniCodex.App\Views\MainWindow.axaml"

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Removed ClipToBounds from shadowed elements to restore visibility.
- UI: Increased shadow blur radius for softer, more natural depth.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."