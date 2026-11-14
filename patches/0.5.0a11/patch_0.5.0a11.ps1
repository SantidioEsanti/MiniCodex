$ErrorActionPreference = "Stop"
$ver = "0.5.0a11"
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

Log "Starting patch $ver - Safe line-by-line gradient update"

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
$patched = $false

foreach ($line in $lines) {
    if ($line -match 'x:Key="AppBackgroundBrush" Color="#F4F5F9"') {
        $newLines += '            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">'
        $newLines += '                <GradientStop Color="#FFFDF8" Offset="0.0" />'
        $newLines += '                <GradientStop Color="#E3E0F7" Offset="1.0" />'
        $newLines += '            </LinearGradientBrush>'
        $patched = $true
    } 
    elseif ($line -match 'x:Key="AppBackgroundBrush" Color="#1A1A1A"') {
        $newLines += '            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">'
        $newLines += '                <GradientStop Color="#1C1A1B" Offset="0.0" />'
        $newLines += '                <GradientStop Color="#0F0E11" Offset="1.0" />'
        $newLines += '            </LinearGradientBrush>'
        $patched = $true
    }
    elseif ($line -match 'x:Key="CardShadow"') {
        $newLines += '        <BoxShadows x:Key="CardShadow">0 8 24 0 #1F3B3347</BoxShadows>'
        $patched = $true
    }
    elseif ($line -match 'x:Key="GlassPanelShadow"') {
        $newLines += '        <BoxShadows x:Key="GlassPanelShadow">0 4 12 0 #0F3B3347</BoxShadows>'
        $patched = $true
    }
    else {
        $newLines += $line
    }
}

if ($patched) {
    [IO.File]::WriteAllLines($appAxaml, $newLines)
    Log "App.axaml updated safely."
} else {
    Log "WARNING: No matching SolidColorBrush or BoxShadows found to replace."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Safely applied warm sunlight gradient and tinted shadows using line-by-line replacement.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."