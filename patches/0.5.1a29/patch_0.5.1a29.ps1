$ErrorActionPreference = "Stop"
$ver = "0.5.1a29"
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

Log "Starting patch $ver - Custom SVG icons for Status buttons"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\src\MiniCodex.App\Views\ModelCardView.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Add StreamGeometry icons to App.axaml
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$appContent = [IO.File]::ReadAllText($appAxaml)

if ($appContent -notmatch "IconClock") {
    $icons = @"
        <!-- patch 0.5.1a29 applied -->
        <StreamGeometry x:Key="IconClock">M11.99,2C6.47,2,2,6.48,2,12s4.47,10,9.99,10C17.52,22,22,17.52,22,12S17.52,2,11.99,2z M12,20c-4.42,0-8-3.58-8-8s3.58-8,8-8s8,3.58,8,8S16.42,20,12,20z M12.5,7H11v6l5.25,3.15l0.75-1.23l-4.5-2.67V7z</StreamGeometry>
        <StreamGeometry x:Key="Icon3DPrinter">M19,3H5C3.9,3,3,3.9,3,5v14c0,1.1,0.9,2,2,2h14c1.1,0,2-0.9,2-2V5C21,3.9,20.1,3,19,3z M19,19H5V5h14V19z M8,7h8v6H8V7z M10,17h4v2h-4V17z M11,13h2v4h-2V13z</StreamGeometry>
        <StreamGeometry x:Key="IconBrush">M7,14c-1.66,0-3,1.34-3,3c0,1.31-1.16,2-2,2c0.92,1.22,2.49,2,4,2c2.21,0,4-1.79,4-4C10,15.34,8.66,14,7,14z M20.71,4.63l-1.34-1.34c-0.39-0.39-1.02-0.39-1.41,0L9,12.25L11.75,15l8.96-8.96C21.1,5.65,21.1,5.02,20.71,4.63z</StreamGeometry>
"@
    $appContent = $appContent -replace '(<Application.Resources>)', "`$1`n$icons"
    [IO.File]::WriteAllText($appAxaml, $appContent)
    Log "App.axaml updated with StreamGeometry icons."
}

# 2. Replace TextBlocks with PathIcons in ModelCardView.axaml
$cardView = "$root\src\MiniCodex.App\Views\ModelCardView.axaml"
$cardContent = [IO.File]::ReadAllText($cardView)

$cardContent = $cardContent -replace '<TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>', '<PathIcon Data="{DynamicResource IconClock}" Width="18" Height="18" />'
$cardContent = $cardContent -replace '<TextBlock Text="&#xE749;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>', '<PathIcon Data="{DynamicResource Icon3DPrinter}" Width="18" Height="18" />'
$cardContent = $cardContent -replace '<TextBlock Text="&#xE8FB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>', '<PathIcon Data="{DynamicResource IconBrush}" Width="18" Height="18" />'

[IO.File]::WriteAllText($cardView, $cardContent)
Log "ModelCardView.axaml updated with PathIcon."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Replaced Unicode status icons with native vector StreamGeometry (Clock, 3D Printer, Brush).
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."