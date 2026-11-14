$ErrorActionPreference = "Stop"
$ver = "0.5.0a8"
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

Log "Starting patch $ver - Gradient Background and Button States Fix"

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

if ($content -match "patch 0.5.0a8 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with gradients and fixed buttons..."
    
    # 1. Replace AppBackgroundBrush with LinearGradientBrush in Light theme
    $lightGradient = @"
            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">
                <GradientStop Color="#F4F5F9" Offset="0.0" />
                <GradientStop Color="#E8EAF6" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace '<SolidColorBrush x:Key="AppBackgroundBrush" Color="#F4F5F9" />', $lightGradient

    # 2. Replace AppBackgroundBrush with LinearGradientBrush in Dark theme
    $darkGradient = @"
            <LinearGradientBrush x:Key="AppBackgroundBrush" StartPoint="0%,0%" EndPoint="100%,100%">
                <GradientStop Color="#1A1A1A" Offset="0.0" />
                <GradientStop Color="#0D0D0D" Offset="1.0" />
            </LinearGradientBrush>
"@
    $content = $content -replace '<SolidColorBrush x:Key="AppBackgroundBrush" Color="#1A1A1A" />', $darkGradient

    # 3. Add explicit Foreground brushes to Themes to ensure readability
    $lightForeground = '<SolidColorBrush x:Key="ButtonForegroundBrush" Color="#000000" />'
    $darkForeground = '<SolidColorBrush x:Key="ButtonForegroundBrush" Color="#FFFFFF" />'
    
    if ($content -match '<ResourceDictionary x:Key="Light">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Light">)', "`$1`n            $lightForeground"
    }
    if ($content -match '<ResourceDictionary x:Key="Dark">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Dark">)', "`$1`n            $darkForeground"
    }

    # 4. Fix Button styles completely (override Fluent defaults)
    # Remove old button styles to prevent conflicts
    $content = $content -replace '(?s)<Style Selector="Button">.*?</Style>', ''
    $content = $content -replace '(?s)<Style Selector="Button:pointerover /template/ ContentPresenter">.*?</Style>', ''
    $content = $content -replace '(?s)<Style Selector="Button:pressed /template/ ContentPresenter">.*?</Style>', ''
    $content = $content -replace '(?s)<Style Selector="Button:checked /template/ ContentPresenter">.*?</Style>', ''
    $content = $content -replace '(?s)<Style Selector="ToggleButton:checked /template/ ContentPresenter">.*?</Style>', ''

    $newButtonStyles = @"
        <Style Selector="Button">
            <Setter Property="CornerRadius" Value="{DynamicResource CornerRadiusMedium}"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource SoftBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
        </Style>
        
        <Style Selector="Button:pointerover /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonHoverBrush}"/>
            <Setter Property="TextElement.Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
        </Style>
        
        <Style Selector="Button:pressed /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
            <Setter Property="TextElement.Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
        </Style>

        <Style Selector="Button:checked /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
            <Setter Property="TextElement.Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
        </Style>

        <Style Selector="ToggleButton:checked /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
            <Setter Property="TextElement.Foreground" Value="{DynamicResource ButtonForegroundBrush}"/>
        </Style>
"@

    # Insert new button styles before </Application.Styles>
    if ($content -match '(</Application.Styles>)') {
        $content = $content -replace '(</Application.Styles>)', "$newButtonStyles`n    `$1"
    }

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
- UI: Added gradient background for Light/Dark themes.
- UI: Fixed Button text readability in Dark theme and for checked states.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."