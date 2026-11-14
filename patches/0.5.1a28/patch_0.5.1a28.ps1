$ErrorActionPreference = "Stop"
$ver = "0.5.1a28"
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

Log "Starting patch $ver - Optimize card grid density"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\src\MiniCodex.App\Views\ModelCardTile.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Update App.axaml (reduce shadow blur/offset)
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$lines = [IO.File]::ReadAllLines($appAxaml)
$newLines = @()
$currentTheme = "base"
$modified = $false

foreach ($line in $lines) {
    if ($line -match '<ResourceDictionary x:Key="Light">') { $currentTheme = "light" }
    elseif ($line -match '<ResourceDictionary x:Key="Dark">') { $currentTheme = "dark" }
    elseif ($line -match '</ResourceDictionary>') { $currentTheme = "base" }
    
    if ($line -match '<BoxShadows x:Key="CardShadow">.*?</BoxShadows>') {
        if ($currentTheme -eq "light") {
            $line = '            <BoxShadows x:Key="CardShadow">0 8 20 0 #2E000000</BoxShadows>'
        } elseif ($currentTheme -eq "dark") {
            $line = '            <BoxShadows x:Key="CardShadow">0 8 24 0 #CC000000</BoxShadows>'
        } else {
            $line = '        <BoxShadows x:Key="CardShadow">0 8 20 0 #2E000000</BoxShadows>'
        }
        $modified = $true
    }
    $newLines += $line
}

if ($modified) {
    [IO.File]::WriteAllLines($appAxaml, $newLines)
    Log "App.axaml: CardShadow reduced (blur 32->20/24, offset 12->8)."
} else {
    Log "WARNING: No CardShadow lines found in App.axaml."
}

# 2. Update ModelCardTile.axaml (reduce margins)
$cardAxaml = "$root\src\MiniCodex.App\Views\ModelCardTile.axaml"
$cardContent = [IO.File]::ReadAllText($cardAxaml)

if ($cardContent -match 'Margin="8,8,8,28"') {
    $cardContent = $cardContent -replace 'Margin="8,8,8,28"', 'Margin="6,6,6,20"'
    Log "ModelCardTile.axaml: Margin reduced from 8,8,8,28 to 6,6,6,20."
} elseif ($cardContent -match 'Margin="[0-9,]+"') {
    # Fallback: replace any margin found on UserControl
    $cardContent = $cardContent -replace '(<UserControl[^>]*?)Margin="[0-9,]+"', '$1Margin="6,6,6,20"'
    Log "ModelCardTile.axaml: Margin normalized to 6,6,6,20."
} else {
    Log "WARNING: Could not find Margin attribute in ModelCardTile.axaml."
}

[IO.File]::WriteAllText($cardAxaml, $cardContent)
Log "ModelCardTile.axaml updated."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Reduced card margins (8,8,8,28 -> 6,6,6,20) and shadow blur to increase grid density while keeping soft shadows visible.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."