# patch_0.5.6a.2.ps1
# 0.5.6a.2 - Associated files: XAML + code-behind
#   1. AssetRowViewModel.cs: 6 label properties for ContextMenu items
#      (ContextOpenText / ContextOpenExternalText / ContextOpenInExplorerText /
#       ContextCopyPathText / ContextReplaceText / ContextRemoveText).
#   2. ModelCardView.axaml.cs: ReplaceRequested handler (file picker + ReplaceAssetAsync),
#      PropertyChanged handler for IsFullScreenOpen -> focus FullScreenGrid.
#   3. ModelCardView.axaml: fullscreen overlay (Border #E0000000, KeyBindings Escape/Left/Right),
#      context menu on every thumbnail (Reference/Photo/Other), third "Other" section,
#      content hidden when fullscreen is open (prevents Skia overlay conflicts).
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6a.2\patch_0.5.6a.2.ps1"

Write-Host "=== MiniCodex patch 0.5.6a.2 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6a.2'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot ('patches\' + $version)
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir ('patch_' + $version + '.log')

if (-not (Test-Path $projectRoot)) { throw ("Project root not found: " + $projectRoot) }
New-Item -ItemType Directory -Force -Path $patchDir  | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { throw ("ASSERT FAILED: " + $msg) }
}
function Replace-Exact([string]$content, [string]$old, [string]$new, [string]$tag) {
    $cnt = [regex]::Matches($content, [regex]::Escape($old)).Count
    Assert ($cnt -eq 1) ("anchor '" + $tag + "' matched " + $cnt + " times (expected 1)")
    Log ("  replace-exact OK: " + $tag)
    return $content.Replace($old, $new)
}

Log ("=== MiniCodex patch " + $version + " ===")

$assetRowPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\AssetRowViewModel.cs'
$viewCsPath   = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml.cs'
$viewAxPath   = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
$clPath       = Join-Path $projectRoot 'CHANGELOG.md'

Assert (Test-Path $assetRowPath) ("Missing: " + $assetRowPath)
Assert (Test-Path $viewCsPath)   ("Missing: " + $viewCsPath)
Assert (Test-Path $viewAxPath)   ("Missing: " + $viewAxPath)

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
$filesToBackup = @(
    'src\MiniCodex.App\ViewModels\AssetRowViewModel.cs',
    'src\MiniCodex.App\Views\ModelCardView.axaml.cs',
    'src\MiniCodex.App\Views\ModelCardView.axaml',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src = Join-Path $projectRoot $rel
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir $rel
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log ("  backup: " + $rel)
    }
}

# ================================================================
# STEP 2: AssetRowViewModel - insert ContextMenu labels before SetThumbnail
# ================================================================
Log "STEP 2: AssetRowViewModel - context menu labels"

$ar = Get-Content -LiteralPath $assetRowPath -Raw -Encoding UTF8

Assert (-not $ar.Contains('ContextOpenText')) "AssetRowViewModel already has ContextOpenText"

$arOld = '    public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;'
$arNew = @'
    // ---------- Asset context menu labels (bound from ContextMenu items) ----------
    public string ContextOpenText => Loc("Card.Asset.Context.Open", "Open (full screen)");
    public string ContextOpenExternalText => Loc("Card.Asset.Context.OpenExternal", "Open with default viewer");
    public string ContextOpenInExplorerText => Loc("Card.Asset.Context.OpenInExplorer", "Open in Explorer");
    public string ContextCopyPathText => Loc("Card.Asset.Context.CopyPath", "Copy path");
    public string ContextReplaceText => Loc("Card.Asset.Context.Replace", "Replace...");
    public string ContextRemoveText => Loc("Card.Asset.Context.Remove", "Remove");

    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;

    public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;
'@
$arNew = $arNew -replace "`r`n", "`n"
$ar = Replace-Exact $ar $arOld $arNew "AssetRowViewModel: context labels"

Assert ($ar.Contains('public string ContextOpenText')) "post-replace: missing ContextOpenText"
Assert ($ar.Contains('public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;')) "post-replace: SetThumbnail missing"

Set-Content -LiteralPath $assetRowPath -Value $ar -Encoding UTF8 -NoNewline
Log ("  AssetRowViewModel.cs written (" + $ar.Length + " chars)")

# ================================================================
# STEP 3: ModelCardView.axaml.cs - full replacement
# ================================================================
Log "STEP 3: ModelCardView.axaml.cs"

$viewCs = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    private ModelCardPageViewModel? _vm;

    public ModelCardView()
    {
        InitializeComponent();
        DragDrop.SetAllowDrop(this, true);
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object? sender, EventArgs e)
    {
        if (_vm != null)
        {
            _vm.PropertyChanged -= OnVmPropertyChanged;
            _vm.ReplaceRequested -= OnReplaceRequested;
        }
        _vm = DataContext as ModelCardPageViewModel;
        if (_vm != null)
        {
            _vm.PropertyChanged += OnVmPropertyChanged;
            _vm.ReplaceRequested += OnReplaceRequested;
        }
    }

    private void OnVmPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ModelCardPageViewModel.IsFullScreenOpen))
        {
            if (_vm != null && _vm.IsFullScreenOpen)
            {
                // Force focus so overlay KeyBindings (Esc/Left/Right) fire
                // regardless of which thumbnail Button had focus before.
                Dispatcher.UIThread.Post(() =>
                {
                    if (FullScreenGrid != null) FullScreenGrid.Focus();
                }, DispatcherPriority.Input);
            }
        }
    }

    private async void OnReplaceRequested(object? sender, AssetRowViewModel row)
    {
        if (_vm == null) return;
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Replace asset",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("All files") { Patterns = new[] { "*" } },
            }
        });
        if (files.Count == 0) return;
        var path = files[0].TryGetLocalPath();
        if (string.IsNullOrEmpty(path)) return;
        await _vm.ReplaceAssetAsync(row, path);
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        e.DragEffects = e.Data.Contains(DataFormats.Files)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private async void OnDropReference(object? sender, DragEventArgs e)
    {
        await HandleDropAsync(e, "reference");
    }

    private async void OnDropPhoto(object? sender, DragEventArgs e)
    {
        await HandleDropAsync(e, "photo");
    }

    private async Task HandleDropAsync(DragEventArgs e, string assetType)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        if (!e.Data.Contains(DataFormats.Files)) return;

        var files = e.Data.GetFiles();
        if (files == null) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths, assetType);
        e.Handled = true;
    }

    private async void OnAddReferenceClick(object? sender, RoutedEventArgs e)
    {
        await AddFromPickerAsync("reference");
    }

    private async void OnAddPhotoClick(object? sender, RoutedEventArgs e)
    {
        await AddFromPickerAsync("photo");
    }

    private async Task AddFromPickerAsync(string assetType)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Add associations",
            AllowMultiple = true,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Images") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp" } },
                new FilePickerFileType("Documents") { Patterns = new[] { "*.pdf" } },
                new FilePickerFileType("All files") { Patterns = new[] { "*" } },
            }
        });
        if (files.Count == 0) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths, assetType);
    }
}
'@
$viewCs = $viewCs -replace "`r`n", "`n"
Set-Content -LiteralPath $viewCsPath -Value $viewCs -Encoding UTF8 -NoNewline
Log ("  ModelCardView.axaml.cs written (" + $viewCs.Length + " chars)")

# ================================================================
# STEP 4: ModelCardView.axaml - full replacement
# ================================================================
Log "STEP 4: ModelCardView.axaml"

$viewAx = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid>
        <!-- ============================================================
             Normal content (hidden when fullscreen overlay is open)
             ============================================================ -->
        <Grid RowDefinitions="Auto,Auto,*" IsVisible="{Binding !IsFullScreenOpen}">
            <!-- Row 0: toolbar -->
            <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">
                <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
                <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                <Button Content="{Binding ResetOrientationText}" Command="{Binding ResetOrientationCommand}"/>
                <Button Content="{Binding SaveOrientationText}" Command="{Binding SaveOrientationCommand}"/>
                <Button Content="{Binding RegeneratePreviewsText}" Command="{Binding RegeneratePreviewsCommand}"
                        IsEnabled="{Binding CanRegeneratePreviews}"/>
                <TextBlock Text="{Binding OrientationStatusText}" VerticalAlignment="Center"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
                <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="100" VerticalAlignment="Center"/>
                <CheckBox Content="{Binding LabelWireframe}" IsChecked="{Binding WireframeMode}" VerticalAlignment="Center"/>
            </StackPanel>

            <!-- Row 1: integrations -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" Spacing="8" Margin="8,0,8,4" IsVisible="{Binding HasAnyIntegration}">
                <TextBlock Text="{Binding SlicerLabel}" VerticalAlignment="Center"/>
                <ComboBox ItemsSource="{Binding AvailableSlicers}" SelectedItem="{Binding SelectedSlicer}"
                          DisplayMemberBinding="{Binding DisplayName}" Width="180" IsVisible="{Binding HasSlicers}"/>
                <Button Content="{Binding OpenInSlicerText}" Command="{Binding LaunchInSlicerCommand}"
                        IsEnabled="{Binding CanLaunchSlicer}" IsVisible="{Binding HasSlicers}"/>
                <TextBlock Text="{Binding NoSlicerText}" VerticalAlignment="Center" Foreground="#888"
                           IsVisible="{Binding !HasSlicers}"/>
                <TextBlock Text="{Binding EditorLabel}" VerticalAlignment="Center" Margin="16,0,0,0"/>
                <ComboBox ItemsSource="{Binding AvailableEditors}" SelectedItem="{Binding SelectedEditor}"
                          DisplayMemberBinding="{Binding DisplayName}" Width="180" IsVisible="{Binding HasEditors}"/>
                <Button Content="{Binding OpenInEditorText}" Command="{Binding LaunchInEditorCommand}"
                        IsEnabled="{Binding CanLaunchEditor}" IsVisible="{Binding HasEditors}"/>
                <TextBlock Text="{Binding NoEditorText}" VerticalAlignment="Center" Foreground="#888"
                           IsVisible="{Binding !HasEditors}"/>
            </StackPanel>

            <!-- Row 2: main content -->
            <Grid Grid.Row="2" ColumnDefinitions="480,*" Margin="8">
                <Grid Grid.Column="0" RowDefinitions="*,Auto" Margin="0,0,8,0">
                    <Border Grid.Row="0" Classes="elevated" MinHeight="200">
                        <views:ThreeDViewer
                            MeshFilePath="{Binding MeshFilePath}"
                            MinLambert="{Binding MinLambertValue}"
                            Wireframe="{Binding WireframeMode}"
                            Yaw="{Binding ViewerYaw, Mode=TwoWay}"
                            Pitch="{Binding ViewerPitch, Mode=TwoWay}"/>
                    </Border>

                    <Border Grid.Row="1" Classes="elevated" Margin="0,8,0,0" Padding="12">
                        <StackPanel Spacing="6">
                            <TextBox Text="{Binding Title}" Watermark="{Binding LabelTitle}"/>
                            <TextBox Text="{Binding Author}" Watermark="{Binding LabelAuthor}"/>
                            <TextBox Text="{Binding SourceUrl}" Watermark="{Binding LabelSourceUrl}"/>
                            <StackPanel Orientation="Horizontal" Spacing="6">
                                <TextBlock Text="{Binding LabelStatus}" VerticalAlignment="Center" Width="90"/>
                                <Button Classes.statusActive="{Binding IsPlanned}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="planned"
                                        ToolTip.Tip="{Binding StatusPlannedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="32">
                                    <PathIcon Data="{DynamicResource IconClock}" Width="18" Height="18" />
                                </Button>
                                <Button Classes.statusActive="{Binding IsPrinted}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="printed"
                                        ToolTip.Tip="{Binding StatusPrintedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="32">
                                    <PathIcon Data="{DynamicResource Icon3DPrinter}" Width="18" Height="18" />
                                </Button>
                                <Button Classes.statusActive="{Binding IsPainted}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="painted"
                                        ToolTip.Tip="{Binding StatusPaintedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="32">
                                    <PathIcon Data="{DynamicResource IconBrush}" Width="18" Height="18" />
                                </Button>
                            </StackPanel>
                            <StackPanel Orientation="Horizontal" Spacing="0">
                                <TextBlock Text="{Binding LabelDifficulty}" VerticalAlignment="Center" Width="90"/>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="1">
                                    <TextBlock Text="{Binding Star1Glyph}" FontSize="20" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="2">
                                    <TextBlock Text="{Binding Star2Glyph}" FontSize="20" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="3">
                                    <TextBlock Text="{Binding Star3Glyph}" FontSize="20" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="4">
                                    <TextBlock Text="{Binding Star4Glyph}" FontSize="20" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="5">
                                    <TextBlock Text="{Binding Star5Glyph}" FontSize="20" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </Grid>

                <Border Grid.Column="1" Classes="elevated">
                    <TabControl SelectedIndex="{Binding SelectedTabIndex}">
                        <TabItem Header="{Binding TabAssociationsHeader}">
                            <Grid RowDefinitions="Auto,*">
                                <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                                    <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                                    <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                </StackPanel>

                                <Grid Grid.Row="1" RowDefinitions="*,*,Auto" Margin="6">
                                    <!-- Reference -->
                                    <Border Grid.Row="0" Classes="elevated" Margin="0,0,0,4">
                                        <Grid RowDefinitions="Auto,*">
                                            <Grid Grid.Row="0" ColumnDefinitions="*,Auto" Margin="8,6">
                                                <TextBlock Text="{Binding ReferenceColumnHeader}"
                                                           FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
                                                <Button Grid.Column="1" Content="{Binding AddFileButtonText}"
                                                        Click="OnAddReferenceClick" Padding="10,4"/>
                                            </Grid>
                                            <Border Grid.Row="1" Margin="8,0,8,8" MinHeight="100"
                                                    Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                    CornerRadius="6" ClipToBounds="True"
                                                    DragDrop.AllowDrop="True"
                                                    DragDrop.DragOver="OnDragOver"
                                                    DragDrop.Drop="OnDropReference">
                                                <Grid>
                                                    <ScrollViewer IsVisible="{Binding HasReferenceAssets}">
                                                        <ItemsControl ItemsSource="{Binding ReferenceAssets}" Margin="4">
                                                            <ItemsControl.ItemsPanel>
                                                                <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                                            </ItemsControl.ItemsPanel>
                                                            <ItemsControl.ItemTemplate>
                                                                <DataTemplate>
                                                                    <Border Width="256" Height="256" Margin="4"
                                                                            Background="{DynamicResource CardBackgroundBrush}"
                                                                            CornerRadius="6" ClipToBounds="True"
                                                                            ToolTip.Tip="{Binding PathText}">
                                                                        <Border.ContextMenu>
                                                                            <ContextMenu>
                                                                                <MenuItem Header="{Binding ContextOpenText}"
                                                                                          Command="{Binding OpenFullScreenCommand}"
                                                                                          IsVisible="{Binding IsImage}"/>
                                                                                <MenuItem Header="{Binding ContextOpenExternalText}"
                                                                                          Command="{Binding OpenExternalCommand}"/>
                                                                                <MenuItem Header="{Binding ContextOpenInExplorerText}"
                                                                                          Command="{Binding OpenInExplorerCommand}"/>
                                                                                <Separator/>
                                                                                <MenuItem Header="{Binding ContextCopyPathText}"
                                                                                          Command="{Binding CopyPathCommand}"/>
                                                                                <MenuItem Header="{Binding ContextReplaceText}"
                                                                                          Command="{Binding ReplaceCommand}"/>
                                                                                <Separator/>
                                                                                <MenuItem Header="{Binding ContextRemoveText}"
                                                                                          Command="{Binding RemoveCommand}"/>
                                                                            </ContextMenu>
                                                                        </Border.ContextMenu>
                                                                        <Grid>
                                                                            <Border CornerRadius="6" ClipToBounds="True">
                                                                                <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>
                                                                            </Border>
                                                                            <Button Content="&#x00D7;"
                                                                                    Command="{Binding RemoveCommand}"
                                                                                    HorizontalAlignment="Right" VerticalAlignment="Top"
                                                                                    Margin="4" Padding="6,0" MinWidth="26" MinHeight="26"
                                                                                    Background="#80000000" Foreground="White"/>
                                                                        </Grid>
                                                                    </Border>
                                                                </DataTemplate>
                                                            </ItemsControl.ItemTemplate>
                                                        </ItemsControl>
                                                    </ScrollViewer>
                                                    <TextBlock Text="{Binding DropReferenceHintText}"
                                                               IsVisible="{Binding !HasReferenceAssets}"
                                                               HorizontalAlignment="Center" VerticalAlignment="Center"
                                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                                </Grid>
                                            </Border>
                                        </Grid>
                                    </Border>

                                    <!-- Photo -->
                                    <Border Grid.Row="1" Classes="elevated" Margin="0,4,0,0">
                                        <Grid RowDefinitions="Auto,*">
                                            <Grid Grid.Row="0" ColumnDefinitions="*,Auto" Margin="8,6">
                                                <TextBlock Text="{Binding PhotoColumnHeader}"
                                                           FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
                                                <Button Grid.Column="1" Content="{Binding AddFileButtonText}"
                                                        Click="OnAddPhotoClick" Padding="10,4"/>
                                            </Grid>
                                            <Border Grid.Row="1" Margin="8,0,8,8" MinHeight="100"
                                                    Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                    CornerRadius="6" ClipToBounds="True"
                                                    DragDrop.AllowDrop="True"
                                                    DragDrop.DragOver="OnDragOver"
                                                    DragDrop.Drop="OnDropPhoto">
                                                <Grid>
                                                    <ScrollViewer IsVisible="{Binding HasPhotoAssets}">
                                                        <ItemsControl ItemsSource="{Binding PhotoAssets}" Margin="4">
                                                            <ItemsControl.ItemsPanel>
                                                                <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                                            </ItemsControl.ItemsPanel>
                                                            <ItemsControl.ItemTemplate>
                                                                <DataTemplate>
                                                                    <Border Width="256" Height="256" Margin="4"
                                                                            Background="{DynamicResource CardBackgroundBrush}"
                                                                            CornerRadius="6" ClipToBounds="True"
                                                                            ToolTip.Tip="{Binding PathText}">
                                                                        <Border.ContextMenu>
                                                                            <ContextMenu>
                                                                                <MenuItem Header="{Binding ContextOpenText}"
                                                                                          Command="{Binding OpenFullScreenCommand}"
                                                                                          IsVisible="{Binding IsImage}"/>
                                                                                <MenuItem Header="{Binding ContextOpenExternalText}"
                                                                                          Command="{Binding OpenExternalCommand}"/>
                                                                                <MenuItem Header="{Binding ContextOpenInExplorerText}"
                                                                                          Command="{Binding OpenInExplorerCommand}"/>
                                                                                <Separator/>
                                                                                <MenuItem Header="{Binding ContextCopyPathText}"
                                                                                          Command="{Binding CopyPathCommand}"/>
                                                                                <MenuItem Header="{Binding ContextReplaceText}"
                                                                                          Command="{Binding ReplaceCommand}"/>
                                                                                <Separator/>
                                                                                <MenuItem Header="{Binding ContextRemoveText}"
                                                                                          Command="{Binding RemoveCommand}"/>
                                                                            </ContextMenu>
                                                                        </Border.ContextMenu>
                                                                        <Grid>
                                                                            <Border CornerRadius="6" ClipToBounds="True">
                                                                                <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>
                                                                            </Border>
                                                                            <Button Content="&#x00D7;"
                                                                                    Command="{Binding RemoveCommand}"
                                                                                    HorizontalAlignment="Right" VerticalAlignment="Top"
                                                                                    Margin="4" Padding="6,0" MinWidth="26" MinHeight="26"
                                                                                    Background="#80000000" Foreground="White"/>
                                                                        </Grid>
                                                                    </Border>
                                                                </DataTemplate>
                                                            </ItemsControl.ItemTemplate>
                                                        </ItemsControl>
                                                    </ScrollViewer>
                                                    <TextBlock Text="{Binding DropPhotoHintText}"
                                                               IsVisible="{Binding !HasPhotoAssets}"
                                                               HorizontalAlignment="Center" VerticalAlignment="Center"
                                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                                </Grid>
                                            </Border>
                                        </Grid>
                                    </Border>

                                    <!-- Other (render/document/profile) - collapsed when empty -->
                                    <Border Grid.Row="2" Classes="elevated" Margin="0,4,0,0"
                                            IsVisible="{Binding HasOtherAssets}">
                                        <Grid RowDefinitions="Auto,*">
                                            <Grid Grid.Row="0" ColumnDefinitions="*" Margin="8,6">
                                                <TextBlock Text="{Binding OtherColumnHeader}"
                                                           FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
                                            </Grid>
                                            <Border Grid.Row="1" Margin="8,0,8,8" MinHeight="60"
                                                    Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                    CornerRadius="6" ClipToBounds="True">
                                                <ScrollViewer MaxHeight="400">
                                                    <ItemsControl ItemsSource="{Binding OtherAssets}" Margin="4">
                                                        <ItemsControl.ItemsPanel>
                                                            <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                                        </ItemsControl.ItemsPanel>
                                                        <ItemsControl.ItemTemplate>
                                                            <DataTemplate>
                                                                <Border Width="128" Height="128" Margin="4"
                                                                        Background="{DynamicResource CardBackgroundBrush}"
                                                                        CornerRadius="6" ClipToBounds="True"
                                                                        ToolTip.Tip="{Binding PathText}">
                                                                    <Border.ContextMenu>
                                                                        <ContextMenu>
                                                                            <MenuItem Header="{Binding ContextOpenText}"
                                                                                      Command="{Binding OpenFullScreenCommand}"
                                                                                      IsVisible="{Binding IsImage}"/>
                                                                            <MenuItem Header="{Binding ContextOpenExternalText}"
                                                                                      Command="{Binding OpenExternalCommand}"/>
                                                                            <MenuItem Header="{Binding ContextOpenInExplorerText}"
                                                                                      Command="{Binding OpenInExplorerCommand}"/>
                                                                            <Separator/>
                                                                            <MenuItem Header="{Binding ContextCopyPathText}"
                                                                                      Command="{Binding CopyPathCommand}"/>
                                                                            <MenuItem Header="{Binding ContextReplaceText}"
                                                                                      Command="{Binding ReplaceCommand}"/>
                                                                            <Separator/>
                                                                            <MenuItem Header="{Binding ContextRemoveText}"
                                                                                      Command="{Binding RemoveCommand}"/>
                                                                        </ContextMenu>
                                                                    </Border.ContextMenu>
                                                                    <Grid>
                                                                        <Border CornerRadius="6" ClipToBounds="True">
                                                                            <Grid>
                                                                                <TextBlock Text="{Binding AssetIconGlyph}"
                                                                                           FontSize="32"
                                                                                           HorizontalAlignment="Center" VerticalAlignment="Center"
                                                                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                                                                <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>
                                                                            </Grid>
                                                                        </Border>
                                                                        <TextBlock Text="{Binding DisplayName}"
                                                                                   HorizontalAlignment="Stretch" VerticalAlignment="Bottom"
                                                                                   Margin="4" Padding="4,2"
                                                                                   FontSize="10"
                                                                                   Background="#80000000" Foreground="White"
                                                                                   TextTrimming="CharacterEllipsis"/>
                                                                        <Button Content="&#x00D7;"
                                                                                Command="{Binding RemoveCommand}"
                                                                                HorizontalAlignment="Right" VerticalAlignment="Top"
                                                                                Margin="2" Padding="4,0" MinWidth="22" MinHeight="22"
                                                                                Background="#80000000" Foreground="White"/>
                                                                    </Grid>
                                                                </Border>
                                                            </DataTemplate>
                                                        </ItemsControl.ItemTemplate>
                                                    </ItemsControl>
                                                </ScrollViewer>
                                            </Border>
                                        </Grid>
                                    </Border>
                                </Grid>
                            </Grid>
                        </TabItem>

                        <TabItem Header="{Binding TabFilesHeader}">
                            <ListBox ItemsSource="{Binding FileRows}">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Grid ColumnDefinitions="Auto,*,Auto,Auto,Auto" Margin="4">
                                            <RadioButton Grid.Column="0"
                                                         IsChecked="{Binding IsPrimary, Mode=OneWay}"
                                                         Command="{Binding $parent[ListBox].((vm:ModelCardPageViewModel)DataContext).SetPrimaryCommand}"
                                                         CommandParameter="{Binding}"
                                                         GroupName="PrimaryFile"/>
                                            <TextBlock Grid.Column="1" Text="{Binding DisplayName}" VerticalAlignment="Center" Margin="6,0"/>
                                            <TextBlock Grid.Column="2" Text="{Binding RoleText}" VerticalAlignment="Center" Width="80"/>
                                            <TextBlock Grid.Column="3" Text="{Binding SizeText}" VerticalAlignment="Center" Width="80"/>
                                            <TextBlock Grid.Column="4" Text="{Binding PolygonsText}" VerticalAlignment="Center" Width="80"/>
                                        </Grid>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>
                        </TabItem>

                        <TabItem Header="{Binding TabTagsHeader}">
                            <Grid RowDefinitions="Auto,*">
                                <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="8">
                                    <TextBox Text="{Binding NewTagName}" Watermark="{Binding TagPlaceholderText}" Width="200"/>
                                    <Button Content="{Binding AddTagButtonText}" Command="{Binding AddTagCommand}"/>
                                </StackPanel>
                                <ScrollViewer Grid.Row="1">
                                    <ItemsControl ItemsSource="{Binding TagRows}" Margin="8">
                                        <ItemsControl.ItemsPanel>
                                            <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                        </ItemsControl.ItemsPanel>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                        CornerRadius="12" Padding="8,2" Margin="4">
                                                    <StackPanel Orientation="Horizontal" Spacing="4">
                                                        <TextBlock Text="{Binding Name}" VerticalAlignment="Center"/>
                                                        <Button Content="&#x00D7;" Command="{Binding RemoveCommand}"
                                                                Padding="4,0" MinWidth="20" MinHeight="20"
                                                                Background="Transparent" BorderThickness="0"/>
                                                    </StackPanel>
                                                </Border>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </ScrollViewer>
                            </Grid>
                        </TabItem>

                        <TabItem Header="{Binding TabScaleHeader}">
                            <ScrollViewer>
                                <StackPanel Margin="12" Spacing="6">
                                    <TextBlock Text="Prototype type:"/>
                                    <ComboBox ItemsSource="{Binding PrototypeTypeChoices}"
                                              SelectedItem="{Binding PrototypeType}" Width="200"/>
                                    <TextBlock Text="Scale:"/>
                                    <StackPanel Orientation="Horizontal" Spacing="8">
                                        <ComboBox ItemsSource="{Binding ScaleChoices}" SelectedItem="{Binding SelectedScale}"
                                                  DisplayMemberBinding="{Binding Label}" Width="200"/>
                                        <TextBlock Text="Manual:" VerticalAlignment="Center"/>
                                        <TextBox Text="{Binding ManualScaleText}" Width="80" Watermark="1:24"/>
                                        <Button Content="Apply" Command="{Binding ApplyManualScaleCommand}"/>
                                    </StackPanel>
                                    <TextBlock Text="Real prototype height (mm):"/>
                                    <TextBox Text="{Binding RealHeightMmText}" Width="150"/>
                                    <TextBlock Text="Model height (mm):"/>
                                    <TextBox Text="{Binding ModelHeightMmText}" Width="150"/>
                                    <TextBlock Text="{Binding ScaleStatus}" Foreground="#888" FontStyle="Italic"/>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>

                        <TabItem Header="{Binding TabNotesHeader}">
                            <TextBox Text="{Binding Notes}" AcceptsReturn="True"
                                     TextWrapping="Wrap" VerticalContentAlignment="Top"
                                     Margin="8" MinHeight="200"/>
                        </TabItem>
                    </TabControl>
                </Border>
            </Grid>
        </Grid>

        <!-- ============================================================
             Fullscreen overlay (last = topmost; content above is hidden)
             ============================================================ -->
        <Border IsVisible="{Binding IsFullScreenOpen}"
                Background="#E0000000">
            <Grid x:Name="FullScreenGrid" Focusable="True">
                <Grid.KeyBindings>
                    <KeyBinding Gesture="Escape" Command="{Binding CloseFullScreenCommand}"/>
                    <KeyBinding Gesture="Left"   Command="{Binding PrevAssetCommand}"/>
                    <KeyBinding Gesture="Right"  Command="{Binding NextAssetCommand}"/>
                </Grid.KeyBindings>

                <!-- Image (fills area minus margins for buttons) -->
                <Image Source="{Binding FullScreenBitmap}" Stretch="Uniform" Margin="72,56,72,56"/>

                <!-- Title -->
                <TextBlock Text="{Binding FullScreenTitle}"
                           HorizontalAlignment="Center" VerticalAlignment="Top"
                           Margin="0,14,0,0"
                           Foreground="White" FontSize="14"
                           TextTrimming="CharacterEllipsis" MaxWidth="720"/>

                <!-- Counter -->
                <TextBlock Text="{Binding FullScreenCounterText}"
                           HorizontalAlignment="Center" VerticalAlignment="Bottom"
                           Margin="0,0,0,14"
                           Foreground="#CCCCCC" FontSize="12"/>

                <!-- Close (x) -->
                <Button Content="&#x00D7;"
                        Command="{Binding CloseFullScreenCommand}"
                        ToolTip.Tip="{Binding FullScreenCloseText}"
                        HorizontalAlignment="Right" VerticalAlignment="Top"
                        Margin="14" Padding="10,4" MinWidth="38" MinHeight="38"
                        FontSize="22"
                        Background="#80000000" Foreground="White"/>

                <!-- Prev -->
                <Button Content="&#x2039;"
                        Command="{Binding PrevAssetCommand}"
                        IsVisible="{Binding CanNavigateFullScreen}"
                        HorizontalAlignment="Left" VerticalAlignment="Center"
                        Margin="14" Padding="10,4" MinWidth="40" MinHeight="56"
                        FontSize="28"
                        Background="#80000000" Foreground="White"/>

                <!-- Next -->
                <Button Content="&#x203A;"
                        Command="{Binding NextAssetCommand}"
                        IsVisible="{Binding CanNavigateFullScreen}"
                        HorizontalAlignment="Right" VerticalAlignment="Center"
                        Margin="14" Padding="10,4" MinWidth="40" MinHeight="56"
                        FontSize="28"
                        Background="#80000000" Foreground="White"/>
            </Grid>
        </Border>
    </Grid>
</UserControl>
'@
$viewAx = $viewAx -replace "`r`n", "`n"
Set-Content -LiteralPath $viewAxPath -Value $viewAx -Encoding UTF8 -NoNewline
Log ("  ModelCardView.axaml written (" + $viewAx.Length + " chars)")

# Post-write sanity
$axBack = Get-Content -LiteralPath $viewAxPath -Raw -Encoding UTF8
Assert ($axBack.Contains('x:Name="FullScreenGrid"')) "post-write: FullScreenGrid missing"
Assert ($axBack.Contains('IsVisible="{Binding IsFullScreenOpen}"')) "post-write: overlay IsVisible missing"
Assert ($axBack.Contains('<KeyBinding Gesture="Escape" Command="{Binding CloseFullScreenCommand}"/>')) "post-write: Escape KeyBinding missing"
Assert ($axBack.Contains('IsVisible="{Binding HasOtherAssets}"')) "post-write: Other section visibility missing"
Assert ($axBack.Contains('ContextOpenText')) "post-write: ContextOpenText binding missing"
$ctxCount = [regex]::Matches($axBack, [regex]::Escape('<Border.ContextMenu>')).Count
Assert ($ctxCount -eq 3) ("post-write: expected 3 ContextMenus, found $ctxCount")
Log "  post-write verify OK"

# ================================================================
# STEP 5: CHANGELOG.md
# ================================================================
Log "STEP 5: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6a.2 applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6a.2 - Associated files (UI)

- ModelCardView.axaml: fullscreen overlay (Border #E0000000, Focusable Grid with KeyBindings for Escape/Left/Right, Image Stretch=Uniform); content grid hidden when IsFullScreenOpen (prevents Skia 3D viewer overlaying the popup).
- ModelCardView.axaml: ContextMenu on every thumbnail (Reference/Photo/Other) - Open (full screen), Open with default viewer, Open in Explorer, Copy path, Replace..., Remove.
- ModelCardView.axaml: third "Other" section (render/document/profile) collapsed when empty; thumbnails 128x128 with icon fallback (AssetIconGlyph) and filename overlay.
- ModelCardView.axaml.cs: ReplaceRequested handler (file picker -> vm.ReplaceAssetAsync); IsFullScreenOpen -> focus FullScreenGrid (guarantees overlay KeyBindings fire).
- AssetRowViewModel.cs: 6 label properties (ContextOpenText/ContextOpenExternalText/ContextOpenInExplorerText/ContextCopyPathText/ContextReplaceText/ContextRemoveText) bound from ContextMenu items.
<!-- patch 0.5.6a.2 applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build (expect 0 errors), then 0.5.6b.1 (multi-select backend)" -ForegroundColor Cyan