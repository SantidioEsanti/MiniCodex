$ErrorActionPreference = "Stop"
$ver = "0.5.0a3"
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

Log "Starting patch $ver - Apply Soft Glass to Sidebar and Toolbars [v2]"

$files = @(
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\src\MiniCodex.App\Views\MainWindow.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Patch LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$libContent = [IO.File]::ReadAllText($libAxaml)

if ($libContent -match "patch 0.5.0a3 applied") {
    Log "LibraryView.axaml already patched. Skipping."
} else {
    Log "Patching LibraryView.axaml..."
    
    # Sidebar Border
    $libContent = $libContent -replace '(?s)<Border Grid\.Column="0"\s+BorderBrush="\{DynamicResource SystemControlForegroundBaseLowBrush\}"\s+BorderThickness="0,0,1,0" Padding="4">', '<Border Grid.Column="0" Background="{DynamicResource GlassPanelBackgroundBrush}" BorderBrush="{DynamicResource GlassPanelBorderBrush}" BorderThickness="1" CornerRadius="{DynamicResource CornerRadiusMedium}" Margin="8,8,4,8" Padding="8" BoxShadow="{DynamicResource GlassPanelShadow}">'

    # Toolbar StackPanel -> Wrap in Border (using double quotes for newline)
    $libContent = $libContent -replace '(?s)<StackPanel Grid\.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">', "<Border Grid.Row=`"0`" Background=`"{DynamicResource GlassPanelBackgroundBrush}`" BorderBrush=`"{DynamicResource GlassPanelBorderBrush}`" BorderThickness=`"1`" CornerRadius=`"{DynamicResource CornerRadiusMedium}`" Margin=`"8,8,8,4`" Padding=`"8`" BoxShadow=`"{DynamicResource GlassPanelShadow}`">`n            <StackPanel Orientation=`"Horizontal`" Spacing=`"8`">"

    # Close Toolbar Border
    $libContent = $libContent -replace '(?s)(</StackPanel>)\s*(<ScrollViewer Grid\.Row="1">)', "`$1`n            </Border>`n`n            `$2"
    
    # Add marker
    $libContent = $libContent -replace '(<UserControl[^>]*>)', "`$1`n    <!-- patch 0.5.0a3 applied -->"
    
    [IO.File]::WriteAllText($libAxaml, $libContent)
    Log "LibraryView.axaml updated."
}

# 2. Patch MainWindow.axaml
$mainAxaml = "$root\src\MiniCodex.App\Views\MainWindow.axaml"
$mainContent = [IO.File]::ReadAllText($mainAxaml)

if ($mainContent -match "patch 0.5.0a3 applied") {
    Log "MainWindow.axaml already patched. Skipping."
} else {
    Log "Patching MainWindow.axaml..."
    
    # Add Window Background
    $mainContent = $mainContent -replace '(?s)(Title="\{Binding Title\}" Icon="/Assets/icon\.ico")', "`$1`n        Background=`"{DynamicResource AppBackgroundBrush}`""

    # Toolbar StackPanel -> Wrap in Border
    $mainContent = $mainContent -replace '(?s)<StackPanel Orientation="Horizontal" Spacing="8" Margin="8">', "<Border Background=`"{DynamicResource GlassPanelBackgroundBrush}`" BorderBrush=`"{DynamicResource GlassPanelBorderBrush}`" BorderThickness=`"1`" CornerRadius=`"{DynamicResource CornerRadiusMedium}`" Margin=`"8`" Padding=`"8`" BoxShadow=`"{DynamicResource GlassPanelShadow}`">`n        <StackPanel Orientation=`"Horizontal`" Spacing=`"8`">"

    # Close Toolbar Border
    $mainContent = $mainContent -replace '(?s)(</StackPanel>)\s*(<ContentControl Grid\.Row="1")', "`$1`n        </Border>`n        `$2"
    
    # Add marker
    $mainContent = $mainContent -replace '(<Window[^>]*>)', "`$1`n    <!-- patch 0.5.0a3 applied -->"
    
    [IO.File]::WriteAllText($mainAxaml, $mainContent)
    Log "MainWindow.axaml updated."
}

# 3. Generate README.md
$readme = "$patchDir\README.md"
$readmeContent = @"
# Patch 0.5.0a3 - Apply Soft Glass to Sidebar and Toolbars (v2)

## What
Applies GlassPanel background, borders, and shadows to the Library Sidebar, Library Toolbar, and Main Window Toolbar.

## Why
To achieve the layered, floating UI look (Glassmorphism) by making panels semi-transparent and giving them soft shadows.

## Files affected
- src/MiniCodex.App/Views/LibraryView.axaml
- src/MiniCodex.App/Views/MainWindow.axaml
- CHANGELOG.md
"@
[IO.File]::WriteAllText($readme, $readmeContent, [Text.Encoding]::UTF8)
Log "README.md created."

# 4. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch 0.5.0a3 applied") {
    $entry = @"

## 0.5.0a3
- UI: Applied Soft Glass tokens to sidebars and toolbars. Added App background.
<!-- patch 0.5.0a3 applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."