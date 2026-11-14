$ErrorActionPreference = "Stop"
$ver = "0.5.0a9"
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

Log "Starting patch $ver - Warm Sunlight Gradient and Tinted Shadows"

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

if ($content -match "patch 0.5.0a9 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with warm gradients and tinted shadows..."
    
    # 1. Light Theme Gradient: Top-Left (Warm White) -> Bottom-Right (Soft Lavender)
    $content = $content -replace '(?s)(<LinearGradientBrush x:Key="AppBackgroundBrush".*?<GradientStop Color=")#F4F5F9(" Offset="0.0" />.*?<GradientStop Color=")#E8EAF6(" Offset="1.0" />)', '$1#FFFDF8$2$3#E3E0F7$4'

    # 2. Dark Theme Gradient: Slightly warmer dark tones
    $content = $content -replace '(?s)(<LinearGradientBrush x:Key="AppBackgroundBrush".*?<GradientStop Color=")#1A1A1A(" Offset="0.0" />.*?<GradientStop Color=")#0D0D0D(" Offset="1.0" />)', '$1#1C1A1B$2$3#0F0E11$4'

    # 3. Update CardShadow (Warm dark purple/brown instead of pure black)
    # Old: 0 8 24 0 #1A000000 -> New: 0 8 24 0 #1A3B3347
    $content = $content -replace '<BoxShadows x:Key="CardShadow">0 8 24 0 #1A000000</BoxShadows>', '<BoxShadows x:Key="CardShadow">0 8 24 0 #1F3B3347</BoxShadows>'
    
    # 4. Update GlassPanelShadow
    # Old: 0 4 12 0 #0D000000 -> New: 0 4 12 0 #0F3B3347
    $content = $content -replace '<BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0D000000</BoxShadows>', '<BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0F3B3347</BoxShadows>'

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
- UI: Enhanced background gradient to simulate warm sunlight (warm white to lavender).
- UI: Tinted card and panel shadows with a warm dark hue for a more natural look.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."