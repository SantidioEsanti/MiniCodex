$ErrorActionPreference = "Stop"
$ver = "0.5.0a12"
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

Log "Starting patch $ver - Adjust Gradient Direction and Colors"

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

if ($content -match "patch 0.5.0a12 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml gradients..."
    
    # 1. Update Light Theme Gradient (Right-Top to Left-Bottom, deeper lavender)
    $lightOld = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">\s*<GradientStop Color="#FFFDF8" Offset="0.0" />\s*<GradientStop Color="#E3E0F7" Offset="1.0" />\s*</LinearGradientBrush>'
    $lightNew = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#FFFDF8" Offset="0.0" />
                <GradientStop Color="#C8BFF0" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace $lightOld, $lightNew

    # 2. Update Dark Theme Gradient (Right-Top to Left-Bottom, warm grey to graphite-purple)
    $darkOld = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">\s*<GradientStop Color="#1C1A1B" Offset="0.0" />\s*<GradientStop Color="#0F0E11" Offset="1.0" />\s*</LinearGradientBrush>'
    $darkNew = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#2B2A2D" Offset="0.0" />
                <GradientStop Color="#141217" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace $darkOld, $darkNew

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
- UI: Reversed gradient direction to top-right to bottom-left.
- UI: Deepened lavender color in Light theme and adjusted Dark theme to graphite-purple.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."