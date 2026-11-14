$ErrorActionPreference = "Stop"
$ver = "0.5.0a1"
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

Log "Starting patch $ver - UI Design Tokens (Soft Glass) [v3]"

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

# 1. Patch App.axaml
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$content = [IO.File]::ReadAllText($appAxaml)

if ($content -match "patch 0.5.0a1 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with new design tokens..."
    
    $tokens = @"
        <!-- patch 0.5.0a1 applied -->
        <SolidColorBrush x:Key="AppBackgroundBrush" Color="#F4F5F9" />
        <SolidColorBrush x:Key="CardBackgroundBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#E6FFFFFF" />
        <SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#80FFFFFF" />
        <SolidColorBrush x:Key="SoftBorderBrush" Color="#E2E8F0" />
        
        <BoxShadows x:Key="CardShadow">0 8 24 0 #1A000000</BoxShadows>
        <BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0D000000</BoxShadows>
        
        <CornerRadius x:Key="CornerRadiusLarge">16</CornerRadius>
        <CornerRadius x:Key="CornerRadiusMedium">12</CornerRadius>
"@

    # Safest injection point: Right after ThemeDictionaries close, or right before ResourceDictionary close.
    if ($content -match "<\/ResourceDictionary\.ThemeDictionaries>") {
        $content = $content -replace "(<\/ResourceDictionary\.ThemeDictionaries>)", "`$1`n$tokens"
        Log "Injected tokens after ThemeDictionaries."
    } elseif ($content -match "<\/ResourceDictionary>") {
        $content = $content -replace "(<\/ResourceDictionary>)", "$tokens`n`$1"
        Log "Injected tokens before closing ResourceDictionary."
    } else {
        Log "ERROR: Could not find a suitable injection point in App.axaml"
    }
    
    [IO.File]::WriteAllText($appAxaml, $content)
    Log "App.axaml updated."
}

# 2. Generate README.md
$readme = "$patchDir\README.md"
$readmeContent = @"
# Patch 0.5.0a1 - UI Design Tokens (Soft Glass)

## What
Introduces new design tokens for the Soft Glass UI concept.

## Why
To enable a premium, layered light theme without hardcoding colors and shadows in individual XAML files. This is the foundation for subsequent UI patches.

## Files affected
- src/MiniCodex.App/App.axaml
- CHANGELOG.md
"@
[IO.File]::WriteAllText($readme, $readmeContent, [Text.Encoding]::UTF8)
Log "README.md created."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch 0.5.0a1 applied") {
    $entry = @"

## 0.5.0a1
- UI: Added design tokens for Soft Glass theme (backgrounds, shadows, corner radii).
<!-- patch 0.5.0a1 applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."