$ErrorActionPreference = "Stop"
$ver = "0.5.0a14"
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

Log "Starting patch $ver - Fix gradient visibility and deepen colors"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Update App.axaml (Safe removal and injection of gradients)
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$lines = [IO.File]::ReadAllLines($appAxaml)
$newLines = @()
$skip = $false

foreach ($line in $lines) {
    if ($line -match 'x:Key="AppBackgroundBrush"') {
        $skip = $true
        if ($line -match '/>') { $skip = $false; continue } # Handle single-line SolidColorBrush
    }
    if ($skip) {
        if ($line -match '</LinearGradientBrush>') { $skip = $false }
        continue
    }
    $newLines += $line
}
$content = $newLines -join "`n"

$lightBrush = @"
            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#FFFDF8" Offset="0.0" />
                <GradientStop Color="#8C7AE6" Offset="1.0" />
            </LinearGradientBrush>
"@
$darkBrush = @"
            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#4A454E" Offset="0.0" />
                <GradientStop Color="#0F0D12" Offset="1.0" />
            </LinearGradientBrush>
"@

$content = $content -replace '(?s)(<ResourceDictionary x:Key="Light">)', "`$1`n$lightBrush"
$content = $content -replace '(?s)(<ResourceDictionary x:Key="Dark">)', "`$1`n$darkBrush"

[IO.File]::WriteAllText($appAxaml, $content)
Log "App.axaml updated with deeper gradients."

# 2. Update LibraryView.axaml (Make ScrollViewer transparent)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$libContent = [IO.File]::ReadAllText($libAxaml)
$libContent = $libContent -replace '<ScrollViewer Grid.Row="1">', '<ScrollViewer Grid.Row="1" Background="Transparent">'
[IO.File]::WriteAllText($libAxaml, $libContent)
Log "LibraryView.axaml updated (ScrollViewer transparent)."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Fixed ScrollViewer blocking the window background gradient.
- UI: Deepened lavender (Light) and graphite (Dark) gradient colors.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."