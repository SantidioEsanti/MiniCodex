$ErrorActionPreference = "Stop"
$ver = "0.5.0a5"
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

Log "Starting patch $ver - Fix Theme-aware design tokens"

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

if ($content -match "patch 0.5.0a5 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml to use ThemeDictionaries..."
    
    # Remove old static tokens from the root dictionary (introduced in 0.5.0a1)
    $content = $content -replace '<SolidColorBrush x:Key="AppBackgroundBrush" Color="#F4F5F9" />\s*', ''
    $content = $content -replace '<SolidColorBrush x:Key="CardBackgroundBrush" Color="#FFFFFF" />\s*', ''
    $content = $content -replace '<SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#E6FFFFFF" />\s*', ''
    $content = $content -replace '<SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#80FFFFFF" />\s*', ''
    $content = $content -replace '<SolidColorBrush x:Key="SoftBorderBrush" Color="#E2E8F0" />\s*', ''

    # Define Light theme tokens
    $lightTokens = @"
        <SolidColorBrush x:Key="AppBackgroundBrush" Color="#F4F5F9" />
        <SolidColorBrush x:Key="CardBackgroundBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#E6FFFFFF" />
        <SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#80FFFFFF" />
        <SolidColorBrush x:Key="SoftBorderBrush" Color="#E2E8F0" />
"@

    # Define Dark theme tokens
    $darkTokens = @"
        <SolidColorBrush x:Key="AppBackgroundBrush" Color="#1A1A1A" />
        <SolidColorBrush x:Key="CardBackgroundBrush" Color="#252525" />
        <SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#CC252525" />
        <SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#33FFFFFF" />
        <SolidColorBrush x:Key="SoftBorderBrush" Color="#3A3A3A" />
"@

    # Inject into Light dictionary
    if ($content -match '<ResourceDictionary x:Key="Light">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Light">)', "`$1`n$lightTokens"
        Log "Injected Light theme tokens."
    } else {
        Log "WARNING: Could not find Light ThemeDictionary."
    }

    # Inject into Dark dictionary
    if ($content -match '<ResourceDictionary x:Key="Dark">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Dark">)', "`$1`n$darkTokens"
        Log "Injected Dark theme tokens."
    } else {
        Log "WARNING: Could not find Dark ThemeDictionary."
    }
    
    # Add marker
    $content = $content -replace '(<Application[^>]*>)', "`$1`n    <!-- patch 0.5.0a5 applied -->"
    
    [IO.File]::WriteAllText($appAxaml, $content)
    Log "App.axaml updated."
}

# 2. Generate README.md
$readme = "$patchDir\README.md"
$readmeContent = @"
# Patch 0.5.0a5 - Fix Theme-aware design tokens

## What
Moves custom UI colors (AppBackgroundBrush, CardBackgroundBrush, etc.) from the root dictionary into Light and Dark ThemeDictionaries.

## Why
To fix the broken dark theme where white text was rendered on hardcoded white backgrounds.

## Files affected
- src/MiniCodex.App/App.axaml
- CHANGELOG.md
"@
[IO.File]::WriteAllText($readme, $readmeContent, [Text.Encoding]::UTF8)
Log "README.md created."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch 0.5.0a5 applied") {
    $entry = @"

## 0.5.0a5
- UI: Made Soft Glass design tokens theme-aware (fixed Dark theme contrast).
<!-- patch 0.5.0a5 applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."