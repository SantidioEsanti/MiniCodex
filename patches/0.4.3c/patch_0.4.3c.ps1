#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3c - Card shadow, distinct background, double-click to open.
.DESCRIPTION
    App.axaml: WindowBackgroundBrush + Border.card styles (with hover).
    ModelCardTile.axaml: remove hard border, use Classes="card".
    ModelCardTile.axaml.cs: DoubleTapped -> OpenCommand.
    ASCII-only.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3c'
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

# ============ App.axaml (full rewrite) ============
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
                    <SolidColorBrush x:Key="WindowBackgroundBrush" Color="#F2F2F2"/>
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
                    <SolidColorBrush x:Key="WindowBackgroundBrush" Color="#1A1A1A"/>
                </ResourceDictionary>
            </ResourceDictionary.ThemeDictionaries>
        </ResourceDictionary>
    </Application.Resources>

    <Application.Styles>
        <FluentTheme />

        <Style Selector="Window">
            <Setter Property="FontFamily" Value="Inter, Segoe UI"/>
            <Setter Property="Background" Value="{DynamicResource WindowBackgroundBrush}"/>
        </Style>

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

        <Style Selector="Border.card">
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="BoxShadow" Value="0 2 8 0 #18000000"/>
            <Setter Property="Transitions">
                <Transitions>
                    <BoxShadowsTransition Property="BoxShadow" Duration="0:0:0.18"/>
                </Transitions>
            </Setter>
        </Style>
        <Style Selector="Border.card:pointerover">
            <Setter Property="BoxShadow" Value="0 4 16 0 #30000000"/>
        </Style>
    </Application.Styles>
</Application>
'@

# ============ ModelCardTile.axaml (full rewrite, no hard border) ============
$Files['src\MiniCodex.App\Views\ModelCardTile.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardTile"
             x:DataType="vm:ModelCardViewModel">
    <Border Classes="card" Width="220" Height="260" Margin="6" Padding="6">
        <Border.ContextMenu>
            <ContextMenu>
                <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                <Separator/>
                <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                <Separator/>
                <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
            </ContextMenu>
        </Border.ContextMenu>
        <Grid RowDefinitions="180,*,Auto">
            <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}" CornerRadius="4">
                <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
            </Border>

            <Border Grid.Row="0" VerticalAlignment="Bottom" IsVisible="{Binding IsHovered}"
                    Background="#A0000000" CornerRadius="0,0,4,4" Padding="6,3">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <TextBlock Text="{Binding TotalSizeText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding PolygonsText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding FileCountText}" Foreground="#D0D0D0" FontSize="10"
                               IsVisible="{Binding HasMultipleFiles}"/>
                </StackPanel>
            </Border>

            <Button Grid.Row="0"
                    HorizontalAlignment="Right" VerticalAlignment="Top"
                    Margin="4" Padding="6,0" MinWidth="26" MinHeight="26"
                    Content="&#x22EF;"
                    ToolTip.Tip="{Binding MoreActionsTooltip}"
                    IsVisible="{Binding IsHovered}">
                <Button.Flyout>
                    <MenuFlyout Placement="BottomEdgeAlignedRight">
                        <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                        <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                        <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                        <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                        <Separator/>
                        <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                        <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                        <Separator/>
                        <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
                    </MenuFlyout>
                </Button.Flyout>
            </Button>

            <TextBlock Grid.Row="1" Text="{Binding Title}"
                       FontWeight="Bold" TextTrimming="CharacterEllipsis"
                       Margin="0,6,0,0"/>
            <TextBlock Grid.Row="2" FontSize="11"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                       Text="{Binding StatusText}"/>
        </Grid>
    </Border>
</UserControl>
'@

# ============ ModelCardTile.axaml.cs (add DoubleTapped) ============
$Files['src\MiniCodex.App\Views\ModelCardTile.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardTile : UserControl
{
    public ModelCardTile()
    {
        InitializeComponent();
        DoubleTapped += OnDoubleTapped;
    }

    private void OnDoubleTapped(object? sender, TappedEventArgs e)
    {
        if (DataContext is ModelCardViewModel vm)
        {
            if (vm.OpenCommand.CanExecute(null))
                vm.OpenCommand.Execute(null);
            e.Handled = true;
        }
    }

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = true;
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = false;
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (DataContext is not ModelCardViewModel vm) return;
        if (!vm.IsHovered || !vm.HasRotation) return;

        var pos = e.GetPosition(this);
        var width = Bounds.Width;
        if (width <= 0) return;

        var relative = Math.Clamp(pos.X / width, 0.0, 0.9999);
        var index = (int)(relative * 4);
        vm.RotateTo(index);
    }
}
'@

# ============ README ============
$Files['patches\0.4.3c\README.md'] = @'
# Patch 0.4.3c - Card shadow, distinct background, double-click

**Iteration:** 0.4

## What it does

- App.axaml: WindowBackgroundBrush (Light #F2F2F2, Dark #1A1A1A); Window.Background uses it.
- App.axaml: Border.card style - soft BoxShadow (0 2 8 #18000000), CardBackgroundBrush, CornerRadius 8, transition.
- App.axaml: Border.card:pointerover - enhanced BoxShadow (0 4 16 #30000000).
- ModelCardTile.axaml: removed BorderBrush / BorderThickness; Classes="card"; no inline Background/CornerRadius.
- ModelCardTile.axaml.cs: DoubleTapped -> OpenCommand.Execute (returns navigation lost in 0.4.1).
- No logic changes.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Cards have no hard grey border, only soft shadow.
- Light theme: window grey #F2F2F2, cards white. Dark: window #1A1A1A, cards #252525.
- Hover on card: shadow grows smoothly.
- Double-click on card preview: opens model card.
- Single click does nothing (except context menu / "...").
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardTile.axaml')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardTile.axaml.cs')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    $marker = '<!-- patch 0.4.3c applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3c] - 2026-11-12`r`n`r`n### Changed`r`n- Card border replaced with soft BoxShadow (hover enhanced).`r`n- Window background distinct from card background (Light #F2F2F2 vs White).`r`n- Double-click card opens model card.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3b\.1\].*)$', "$entry`$1"
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