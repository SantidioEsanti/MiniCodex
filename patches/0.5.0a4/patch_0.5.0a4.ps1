$ErrorActionPreference = "Stop"
$ver = "0.5.0a4"
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

Log "Starting patch $ver - Apply Soft Glass global control styles"

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

# 1. Patch App.axaml
$appAxaml = "$root\src\MiniCodex.App\App.axaml"
$content = [IO.File]::ReadAllText($appAxaml)

if ($content -match "patch 0.5.0a4 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with global control styles..."
    
    $styles = @"
        
        <!-- patch 0.5.0a4 applied -->
        <Style Selector="Button">
            <Setter Property="CornerRadius" Value="{DynamicResource CornerRadiusMedium}"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource SoftBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style Selector="Button:pointerover /template/ ContentPresenter">
            <Setter Property="Background" Value="#F4F5F9"/>
        </Style>
        
        <Style Selector="TextBox">
            <Setter Property="CornerRadius" Value="{DynamicResource CornerRadiusMedium}"/>
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource SoftBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
        </Style>
        
        <Style Selector="ComboBox">
            <Setter Property="CornerRadius" Value="{DynamicResource CornerRadiusMedium}"/>
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource SoftBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
        </Style>

        <Style Selector="ListBoxItem">
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Margin" Value="0,2"/>
        </Style>
"@

    # Inject right before closing Application.Styles
    if ($content -match "(</Application.Styles>)") {
        $content = $content -replace "(</Application.Styles>)", "$styles`n    `$1"
        Log "Injected global styles before </Application.Styles>."
    } else {
        Log "ERROR: Could not find </Application.Styles> in App.axaml"
    }
    
    [IO.File]::WriteAllText($appAxaml, $content)
    Log "App.axaml updated."
}

# 2. Generate README.md
$readme = "$patchDir\README.md"
$readmeContent = @"
# Patch 0.5.0a4 - Global Control Styles

## What
Adds global styles for Button, TextBox, ComboBox, and ListBoxItem.

## Why
To make all interactive elements match the soft, rounded Soft Glass aesthetic (Glassmorphism) introduced in previous patches.

## Files affected
- src/MiniCodex.App/App.axaml
- CHANGELOG.md
"@
[IO.File]::WriteAllText($readme, $readmeContent, [Text.Encoding]::UTF8)
Log "README.md created."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch 0.5.0a4 applied") {
    $entry = @"

## 0.5.0a4
- UI: Added global styles for Buttons, TextBoxes, ComboBoxes, and ListBoxItems.
<!-- patch 0.5.0a4 applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."