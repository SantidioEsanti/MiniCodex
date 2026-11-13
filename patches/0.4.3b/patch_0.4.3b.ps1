#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3b - Global styles (font, corner radius, amber accent, selection).
.DESCRIPTION
    Program.cs: WithInterFont().
    App.axaml: theme resources (accent + CardBackgroundBrush) + styles.
    ASCII-only.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3b'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

$Files = @{}

# ============ Program.cs ============
$Files['src\MiniCodex.App\Program.cs'] = @'
using Avalonia;

namespace MiniCodex.App;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args) => BuildAvaloniaApp()
        .StartWithClassicDesktopLifetime(args);

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
'@

# ============ App.axaml ============
$Files['src\MiniCodex.App\App.axaml'] = @'
<Application xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             x:Class="MiniCodex.App.App"
             RequestedThemeVariant="Default">

    <Application.DataTemplates>
        <DataTemplate DataType="vm:LibraryViewModel">
            <views:LibraryView/>
        </DataTemplate>
        <DataTemplate DataType="vm:ModelCardPageViewModel">
            <views:ModelCardView/>
        </DataTemplate>
        <DataTemplate DataType="vm:SettingsViewModel">
            <views:SettingsView/>
        </DataTemplate>
    </Application.DataTemplates>

    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.ThemeDictionaries>
                <ResourceDictionary x:Key="Light">
                    <Color x:Key="SystemAccentColor">#E67E22</Color>
                    <Color x:Key="SystemAccentColorLight1">#EB9548</Color>
                    <Color x:Key="SystemAccentColorLight2">#F0AB6F</Color>
                    <Color x:Key="SystemAccentColorLight3">#F5C196</Color>
                    <Color x:Key="SystemAccentColorDark1">#CC6E1C</Color>
                    <Color x:Key="SystemAccentColorDark2">#B25F18</Color>
                    <Color x:Key="SystemAccentColorDark3">#995013</Color>
                    <SolidColorBrush x:Key="SystemAccentColorBrush" Color="#E67E22"/>
                    <SolidColorBrush x:Key="CardBackgroundBrush" Color="White"/>
                </ResourceDictionary>
                <ResourceDictionary x:Key="Dark">
                    <Color x:Key="SystemAccentColor">#E67E22</Color>
                    <Color x:Key="SystemAccentColorLight1">#EB9548</Color>
                    <Color x:Key="SystemAccentColorLight2">#F0AB6F</Color>
                    <Color x:Key="SystemAccentColorLight3">#F5C196</Color>
                    <Color x:Key="SystemAccentColorDark1">#CC6E1C</Color>
                    <Color x:Key="SystemAccentColorDark2">#B25F18</Color>
                    <Color x:Key="SystemAccentColorDark3">#995013</Color>
                    <SolidColorBrush x:Key="SystemAccentColorBrush" Color="#E67E22"/>
                    <SolidColorBrush x:Key="CardBackgroundBrush" Color="#252525"/>
                </ResourceDictionary>
            </ResourceDictionary.ThemeDictionaries>
        </ResourceDictionary>
    </Application.Resources>

    <Application.Styles>
        <FluentTheme />

        <!-- Font family (Inter with Segoe UI fallback) -->
        <Style Selector="Window">
            <Setter Property="FontFamily" Value="Inter, Segoe UI"/>
        </Style>

        <!-- Rounded corners for interactive elements -->
        <Style Selector="Button">
            <Setter Property="CornerRadius" Value="6"/>
        </Style>
        <Style Selector="TextBox">
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="SelectionBrush" Value="#E67E22"/>
            <Setter Property="SelectionForegroundBrush" Value="White"/>
        </Style>
        <Style Selector="ComboBox">
            <Setter Property="CornerRadius" Value="6"/>
        </Style>

        <!-- Amber selection (explicit, in addition to SystemAccentColor override) -->
        <Style Selector="ListBoxItem:selected /template/ ContentPresenter">
            <Setter Property="Background" Value="#E67E22"/>
        </Style>
        <Style Selector="ListBoxItem:selected">
            <Setter Property="Background" Value="#E67E22"/>
            <Setter Property="Foreground" Value="White"/>
        </Style>
        <Style Selector="ComboBoxItem:selected /template/ ContentPresenter">
            <Setter Property="Background" Value="#E67E22"/>
        </Style>
    </Application.Styles>
</Application>
'@

# ============ README ============
$Files['patches\0.4.3b\README.md'] = @'
# Patch 0.4.3b - Global styles

**Iteration:** 0.4

## What it does

- Program.cs: .WithInterFont() (Avalonia.Fonts.Inter package already referenced).
- App.axaml: ThemeDictionaries override SystemAccentColor (+6 shades) and SystemAccentColorBrush to amber #E67E22.
- App.axaml: CardBackgroundBrush (White light / #252525 dark) - prepared for 0.4.3c.
- App.axaml styles:
  - Window: FontFamily = "Inter, Segoe UI".
  - Button / TextBox / ComboBox: CornerRadius=6.
  - TextBox: SelectionBrush = amber, SelectionForegroundBrush = white.
  - ListBoxItem:selected and ComboBoxItem:selected: amber background (explicit backup).
- No C# logic changes.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- All buttons/textboxes/comboboxes have rounded corners.
- Font in main window is Inter (or Segoe UI if Inter failed to load).
- Sidebar tag selection is amber (not blue).
- Tab underline, focus rings, checkboxes, sliders, radio buttons - all amber.
- Text selection in textboxes is amber.
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Program.cs')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    $marker = '<!-- patch 0.4.3b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3b] - 2026-11-10`r`n`r`n### Changed`r`n- Inter font (fallback Segoe UI).`r`n- CornerRadius 6 on Button/TextBox/ComboBox.`r`n- System accent color -> amber #E67E22 (tabs, focus, checkboxes, selection).`r`n- TextBox SelectionBrush amber.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}