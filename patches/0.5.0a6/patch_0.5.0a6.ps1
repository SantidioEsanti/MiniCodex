$ErrorActionPreference = "Stop"
$ver = "0.5.0a6"
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

Log "Starting patch $ver - Sanitize and Fix ThemeDictionaries"

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
$lines = [IO.File]::ReadAllLines($appAxaml)
$newLines = @()
$customKeys = @("AppBackgroundBrush", "CardBackgroundBrush", "GlassPanelBackgroundBrush", "GlassPanelBorderBrush", "SoftBorderBrush", "CardShadow", "GlassPanelShadow", "CornerRadiusLarge", "CornerRadiusMedium")

# 1. Strip all old custom resources to prevent duplicate keys
foreach ($line in $lines) {
    $skip = $false
    foreach ($key in $customKeys) {
        if ($line -match "x:Key=`"$key`"") { $skip = $true; break }
    }
    if (-not $skip) {
        $newLines += $line
    }
}
$content = $newLines -join "`n"

# 2. Inject Light theme tokens
$lightTokens = @"
            <SolidColorBrush x:Key="AppBackgroundBrush" Color="#F4F5F9" />
            <SolidColorBrush x:Key="CardBackgroundBrush" Color="#FFFFFF" />
            <SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#E6FFFFFF" />
            <SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#80FFFFFF" />
            <SolidColorBrush x:Key="SoftBorderBrush" Color="#E2E8F0" />
"@
if ($content -match '<ResourceDictionary x:Key="Light">') {
    $content = $content -replace '(<ResourceDictionary x:Key="Light">)', "`$1`n$lightTokens"
    Log "Injected Light theme tokens."
}

# 3. Inject Dark theme tokens
$darkTokens = @"
            <SolidColorBrush x:Key="AppBackgroundBrush" Color="#1A1A1A" />
            <SolidColorBrush x:Key="CardBackgroundBrush" Color="#252525" />
            <SolidColorBrush x:Key="GlassPanelBackgroundBrush" Color="#CC252525" />
            <SolidColorBrush x:Key="GlassPanelBorderBrush" Color="#33FFFFFF" />
            <SolidColorBrush x:Key="SoftBorderBrush" Color="#3A3A3A" />
"@
if ($content -match '<ResourceDictionary x:Key="Dark">') {
    $content = $content -replace '(<ResourceDictionary x:Key="Dark">)', "`$1`n$darkTokens"
    Log "Injected Dark theme tokens."
}

# 4. Inject Shadows and Radii into the base dictionary
$baseTokens = @"
        <BoxShadows x:Key="CardShadow">0 8 24 0 #1A000000</BoxShadows>
        <BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0D000000</BoxShadows>
        <CornerRadius x:Key="CornerRadiusLarge">16</CornerRadius>
        <CornerRadius x:Key="CornerRadiusMedium">12</CornerRadius>
"@

if ($content -match '</ResourceDictionary.ThemeDictionaries>') {
    $content = $content -replace '(<\/ResourceDictionary\.ThemeDictionaries>)', "`$1`n$baseTokens"
    Log "Injected base tokens after ThemeDictionaries."
} else {
    $content = $content -replace '(<ResourceDictionary[^>]*>)', "`$1`n$baseTokens"
    Log "Injected base tokens at the top of ResourceDictionary."
}

# Add marker
$content = $content -replace '(<Application[^>]*>)', "`$1`n    <!-- patch $ver applied -->"

[IO.File]::WriteAllText($appAxaml, $content)
Log "App.axaml sanitized and updated."

# 5. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Fixed theme dictionary crashes by sanitizing and properly placing theme-aware design tokens.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."