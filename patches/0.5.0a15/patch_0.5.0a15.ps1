$ErrorActionPreference = "Stop"
$ver = "0.5.0a15"
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

Log "Starting patch $ver - Theme-specific shadows and card colors"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$content = [IO.File]::ReadAllText($appAxaml)

if ($content -match "patch 0.5.0a15 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml..."
    
    # 1. Remove old shadows from the root dictionary to prevent duplication
    $content = $content -replace '\s*<BoxShadows x:Key="CardShadow">.*?</BoxShadows>', ''
    $content = $content -replace '\s*<BoxShadows x:Key="GlassPanelShadow">.*?</BoxShadows>', ''

    # 2. Update Light Theme
    # Revert gradient to soft lavender
    $content = $content -replace '<GradientStop Color="#8C7AE6" Offset="1.0" />', '<GradientStop Color="#C8BFF0" Offset="1.0" />'
    
    # Inject stronger Light-theme shadows
    $lightShadows = @"
            <BoxShadows x:Key="CardShadow">0 12 28 0 #3A4B4460</BoxShadows>
            <BoxShadows x:Key="GlassPanelShadow">0 8 16 0 #1F3B3347</BoxShadows>
"@
    $content = $content -replace '(<ResourceDictionary x:Key="Light">)', "`$1`n$lightShadows"

    # 3. Update Dark Theme
    # Make card background lighter
    $content = $content -replace '<SolidColorBrush x:Key="CardBackgroundBrush" Color="#252525" />', '<SolidColorBrush x:Key="CardBackgroundBrush" Color="#383838" />'
    
    # Inject strong black shadows for Dark theme
    $darkShadows = @"
            <BoxShadows x:Key="CardShadow">0 12 32 0 #CC000000</BoxShadows>
            <BoxShadows x:Key="GlassPanelShadow">0 8 16 0 #99000000</BoxShadows>
"@
    $content = $content -replace '(<ResourceDictionary x:Key="Dark">)', "`$1`n$darkShadows"

    # Add marker
    $content = $content -replace '(<Application[^>]*>)', "`$1`n    <!-- patch $ver applied -->"
    
    [IO.File]::WriteAllText($appAxaml, $content)
    Log "App.axaml updated."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Moved shadows into ThemeDictionaries for theme-specific depth.
- UI: Reverted Light theme gradient to soft lavender.
- UI: Lightened dark theme card background and added deep black shadows.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."