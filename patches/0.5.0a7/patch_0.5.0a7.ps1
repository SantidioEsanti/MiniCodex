$ErrorActionPreference = "Stop"
$ver = "0.5.0a7"
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

Log "Starting patch $ver - Fix Button hover/pressed colors in Dark theme"

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

if ($content -match "patch 0.5.0a7 applied") {
    Log "App.axaml already patched. Skipping."
} else {
    Log "Patching App.axaml with theme-aware button states..."
    
    # 1. Add Button state brushes to Light and Dark ThemeDictionaries
    $lightBrushes = @"
            <SolidColorBrush x:Key="ButtonHoverBrush" Color="#E2E8F0" />
            <SolidColorBrush x:Key="ButtonPressedBrush" Color="#CBD5E1" />
"@
    $darkBrushes = @"
            <SolidColorBrush x:Key="ButtonHoverBrush" Color="#3A3A3A" />
            <SolidColorBrush x:Key="ButtonPressedBrush" Color="#4A4A4A" />
"@

    if ($content -match '<ResourceDictionary x:Key="Light">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Light">)', "`$1`n$lightBrushes"
    }
    if ($content -match '<ResourceDictionary x:Key="Dark">') {
        $content = $content -replace '(<ResourceDictionary x:Key="Dark">)', "`$1`n$darkBrushes"
    }

    # 2. Replace hardcoded pointerover color with DynamicResource
    $content = $content -replace '<Setter Property="Background" Value="#F4F5F9" />', '<Setter Property="Background" Value="{DynamicResource ButtonHoverBrush}" />'

    # 3. Add missing pressed and checked states to ensure text readability
    $buttonStates = @"
        <Style Selector="Button:pressed /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
        </Style>
        <Style Selector="Button:checked /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
        </Style>
        <Style Selector="ToggleButton:checked /template/ ContentPresenter">
            <Setter Property="Background" Value="{DynamicResource ButtonPressedBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource SystemControlForegroundBaseHighBrush}"/>
        </Style>
"@

    # Insert new button states right after the existing pointerover style
    if ($content -match '(?s)(<Style Selector="Button:pointerover /template/ ContentPresenter">.*?</Style>)') {
        $content = $content -replace '(?s)(<Style Selector="Button:pointerover /template/ ContentPresenter">.*?</Style>)', "`$1`n$buttonStates"
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
- UI: Fixed unreadable button text in Dark theme by adding theme-aware hover and pressed states.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."