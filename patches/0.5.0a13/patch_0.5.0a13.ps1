$ErrorActionPreference = "Stop"
$ver = "0.5.0a13"
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

Log "Starting patch $ver - Fix transparent backgrounds and enhance gradients"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\src\MiniCodex.App\Views\MainWindow.axaml",
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

# 1. Update App.axaml (Stronger Gradients)
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$content = [IO.File]::ReadAllText($appAxaml)

$lightOld = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush".*?</LinearGradientBrush>'
$lightNew = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#FFFDF8" Offset="0.0" />
                <GradientStop Color="#B3A7E6" Offset="1.0" />
            </LinearGradientBrush>
"@
$content = $content -replace $lightOld, $lightNew

$darkOld = '(?s)<LinearGradientBrush x:Key="AppBackgroundBrush".*?</LinearGradientBrush>'
$darkNew = @"
<LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="100%,0%" EndPoint="0%,100%">
                <GradientStop Color="#38343E" Offset="0.0" />
                <GradientStop Color="#141118" Offset="1.0" />
            </LinearGradientBrush>
"@
$content = $content -replace $darkOld, $darkNew

[IO.File]::WriteAllText($appAxaml, $content)
Log "App.axaml updated with stronger gradients."

# 2. Update MainWindow.axaml (Make Grid transparent)
$mainAxaml = "$root\src\MiniCodex.App\Views\MainWindow.axaml"
$mainContent = [IO.File]::ReadAllText($mainAxaml)
$mainContent = $mainContent -replace '<Grid RowDefinitions="Auto,\*">', '<Grid RowDefinitions="Auto,*" Background="Transparent">'
$mainContent = $mainContent -replace '<ContentControl Grid.Row="1" Content="{Binding CurrentPage}"/>', '<ContentControl Grid.Row="1" Content="{Binding CurrentPage}" Background="Transparent"/>'
[IO.File]::WriteAllText($mainAxaml, $mainContent)
Log "MainWindow.axaml updated."

# 3. Update LibraryView.axaml (Make Panel/Grid transparent)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$libContent = [IO.File]::ReadAllText($libAxaml)
$libContent = $libContent -replace '<Panel>', '<Panel Background="Transparent">'
$libContent = $libContent -replace '<Grid ColumnDefinitions="200,\*">', '<Grid ColumnDefinitions="200,*" Background="Transparent">'
$libContent = $libContent -replace '<Grid Grid.Column="1" RowDefinitions="Auto,\*">', '<Grid Grid.Column="1" RowDefinitions="Auto,*" Background="Transparent">'
[IO.File]::WriteAllText($libAxaml, $libContent)
Log "LibraryView.axaml updated."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Fixed background overrides by setting inner containers to Transparent.
- UI: Enhanced gradient depth and contrast for both Light and Dark themes.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."