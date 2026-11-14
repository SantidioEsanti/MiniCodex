$ErrorActionPreference = "Stop"
$ver = "0.5.0a10"
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

Log "Starting patch $ver - Warm Sunlight Gradient (Safe Replace)"

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

if ($content -match "patch 0.5.0a10 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with warm gradients and tinted shadows..."
    
    # 1. Replace Light Theme Gradient
    $lightPattern = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush".*?#F4F5F9.*?</LinearGradientBrush>'
    $newLight = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">
                <GradientStop Color="#FFFDF8" Offset="0.0" />
                <GradientStop Color="#E3E0F7" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace $lightPattern, $newLight

    # 2. Replace Dark Theme Gradient
    $darkPattern = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush".*?#1A1A1A.*?</LinearGradientBrush>'
    $newDark = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">
                <GradientStop Color="#1C1A1B" Offset="0.0" />
                <GradientStop Color="#0F0E11" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace $darkPattern, $newDark

    # 3. Update CardShadow (Warm tint instead of pure black)
    $content = $content -replace '<BoxShadows x:Key="CardShadow">.*?</BoxShadows>', '<BoxShadows x:Key="CardShadow">0 8 24 0 #1F3B3347</BoxShadows>'
    
    # 4. Update GlassPanelShadow
    $content = $content -replace '<BoxShadows x:Key="GlassPanelShadow">.*?</BoxShadows>', '<BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0F3B3347</BoxShadows>'

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
- UI: Safely applied warm sunlight gradient (warm white to lavender) and tinted shadows.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."