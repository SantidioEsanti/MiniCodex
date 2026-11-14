$ErrorActionPreference = "Stop"
$ver = "0.5.1a30"
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

Log "Starting patch $ver - Fix App.axaml resource injection and remove unused field"

$files = @(
    "$root\src\MiniCodex.App\App.axaml",
    "$root\src\MiniCodex.App\Views\ModelCardView.axaml",
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Restore App.axaml from 0.5.1a29 backup to remove the broken injection
$latestBackup = (Get-ChildItem "$root\backups" -Filter "0.5.1a29_*" | Sort-Object Name -Descending | Select-Object -First 1).FullName
if ($latestBackup -and (Test-Path "$latestBackup\App.axaml")) {
    Copy-Item -LiteralPath "$latestBackup\App.axaml" -Destination "$root\src\MiniCodex.App\App.axaml" -Force
    Log "Restored App.axaml from $latestBackup"
} else {
    Log "WARNING: Backup App.axaml not found. Trying to fix current file."
}

$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$appContent = [IO.File]::ReadAllText($appAxaml)

# 2. Inject StreamGeometry icons inside the root ResourceDictionary
if ($appContent -notmatch "IconClock") {
    $icons = @"
        <!-- patch 0.5.1a30 applied -->
        <StreamGeometry x:Key="IconClock">M11.99,2C6.47,2,2,6.48,2,12s4.47,10,9.99,10C17.52,22,22,17.52,22,12S17.52,2,11.99,2z M12,20c-4.42,0-8-3.58-8-8s3.58-8,8-8s8,3.58,8,8S16.42,20,12,20z M12.5,7H11v6l5.25,3.15l0.75-1.23l-4.5-2.67V7z</StreamGeometry>
        <StreamGeometry x:Key="Icon3DPrinter">M19,3H5C3.9,3,3,3.9,3,5v14c0,1.1,0.9,2,2,2h14c1.1,0,2-0.9,2-2V5C21,3.9,20.1,3,19,3z M19,19H5V5h14V19z M8,7h8v6H8V7z M10,17h4v2h-4V17z M11,13h2v4h-2V13z</StreamGeometry>
        <StreamGeometry x:Key="IconBrush">M7,14c-1.66,0-3,1.34-3,3c0,1.31-1.16,2-2,2c0.92,1.22,2.49,2,4,2c2.21,0,4-1.79,4-4C10,15.34,8.66,14,7,14z M20.71,4.63l-1.34-1.34c-0.39-0.39-1.02-0.39-1.41,0L9,12.25L11.75,15l8.96-8.96C21.1,5.65,21.1,5.02,20.71,4.63z</StreamGeometry>
"@
    # Inject right after the opening <ResourceDictionary> tag
    $appContent = $appContent -replace '(<ResourceDictionary[^>]*>)', "`$1`n$icons"
    [IO.File]::WriteAllText($appAxaml, $appContent)
    Log "App.axaml correctly updated with StreamGeometry icons."
} else {
    Log "Icons already present in App.axaml."
}

# 3. Update ModelCardView.axaml
$cardView = "$root\src\MiniCodex.App\Views\ModelCardView.axaml"
$cardContent = [IO.File]::ReadAllText($cardView)

# Replace the TextBlock elements with PathIcon
$cardContent = $cardContent -replace '(?s)<TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"\s*/>', '<PathIcon Data="{DynamicResource IconClock}" Width="18" Height="18" />'
$cardContent = $cardContent -replace '(?s)<TextBlock Text="&#xE749;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"\s*/>', '<PathIcon Data="{DynamicResource Icon3DPrinter}" Width="18" Height="18" />'
$cardContent = $cardContent -replace '(?s)<TextBlock Text="&#xE8FB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"\s*/>', '<PathIcon Data="{DynamicResource IconBrush}" Width="18" Height="18" />'

[IO.File]::WriteAllText($cardView, $cardContent)
Log "ModelCardView.axaml updated with PathIcon."

# 4. Clean up _disposed in LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$libContent = [IO.File]::ReadAllText($libVm)
$libContent = $libContent -replace 'private bool _disposed;', ''
$libContent = $libContent -replace '// if \(_disposed\) return; // Removed for singleton pattern', ''

[IO.File]::WriteAllText($libVm, $libContent)
Log "LibraryViewModel.cs updated (removed unused _disposed field)."

# 5. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Properly injected StreamGeometry icons into the root ResourceDictionary to fix AVLN3000.
- Clean: Removed unused `_disposed` field from LibraryViewModel to clear CS0169 warning.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."