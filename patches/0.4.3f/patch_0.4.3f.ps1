#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3f - Associations tab: 2 columns (Reference / Photo), per-column drop zones.
.DESCRIPTION
    VM: ReferenceAssets/PhotoAssets, ImportAssetsAsync(paths, type), RebuildAssetColumns.
    XAML: full rewrite of Associations TabItem + full rewrite of ModelCardView.axaml.cs.
    lang: Card.Assoc.DropReference, Card.Assoc.DropPhoto.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3f'
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

# ============ ModelCardView.axaml (full rewrite) ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid RowDefinitions="Auto,Auto,*">
        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
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
                                <TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>
                            </Button>
                            <Button Classes.statusActive="{Binding IsPrinted}"
                                    Command="{Binding SetStatusCommand}" CommandParameter="printed"
                                    ToolTip.Tip="{Binding StatusPrintedLabel}"
                                    Padding="10,6" MinWidth="44" MinHeight="32">
                                <TextBlock Text="&#xE749;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>
                            </Button>
                            <Button Classes.statusActive="{Binding IsPainted}"
                                    Command="{Binding SetStatusCommand}" CommandParameter="painted"
                                    ToolTip.Tip="{Binding StatusPaintedLabel}"
                                    Padding="10,6" MinWidth="44" MinHeight="32">
                                <TextBlock Text="&#xE8FB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16"/>
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

                    <TabItem Header="{Binding TabAssociationsHeader}">
                        <Grid RowDefinitions="Auto,*">
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                                <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                                <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                            </StackPanel>

                            <Grid Grid.Row="1" ColumnDefinitions="*,*" Margin="6">
                                <!-- Reference column -->
                                <Border Grid.Column="0" Classes="elevated" Margin="0,0,3,0">
                                    <Grid RowDefinitions="Auto,Auto,Auto,*">
                                        <TextBlock Grid.Row="0" Text="{Binding ReferenceColumnHeader}"
                                                   FontWeight="Bold" FontSize="13" Margin="10,8,10,6"/>
                                        <Border Grid.Row="1" Margin="8,0,8,6" Padding="8" MinHeight="60"
                                                CornerRadius="6" Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                DragDrop.AllowDrop="True"
                                                DragOver="OnDragOver" Drop="OnDropReference">
                                            <TextBlock Text="{Binding DropReferenceHintText}"
                                                       HorizontalAlignment="Center" VerticalAlignment="Center"
                                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                        </Border>
                                        <Button Grid.Row="2" Content="{Binding AddFileButtonText}"
                                                Click="OnAddReferenceClick"
                                                HorizontalAlignment="Left" Margin="8,0,0,6"/>
                                        <ScrollViewer Grid.Row="3">
                                            <ItemsControl ItemsSource="{Binding ReferenceAssets}" Margin="4">
                                                <ItemsControl.ItemsPanel>
                                                    <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                                </ItemsControl.ItemsPanel>
                                                <ItemsControl.ItemTemplate>
                                                    <DataTemplate>
                                                        <Border Width="140" Margin="4" Padding="6"
                                                                Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                                CornerRadius="6">
                                                            <Grid RowDefinitions="100,*,Auto">
                                                                <Border Background="{DynamicResource SystemControlBackgroundBaseHighBrush}"
                                                                        CornerRadius="4" ClipToBounds="True">
                                                                    <Image Source="{Binding Thumbnail}" Stretch="Uniform" Margin="2"/>
                                                                </Border>
                                                                <TextBlock Grid.Row="1" Text="{Binding DisplayName}" FontSize="11"
                                                                           TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
                                                                <Grid Grid.Row="2" ColumnDefinitions="*,Auto" Margin="0,4,0,0">
                                                                    <TextBlock Text="{Binding AssetTypeText}" FontSize="10"
                                                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                                                               VerticalAlignment="Center"/>
                                                                    <Button Grid.Column="1" Content="&#x00D7;"
                                                                            Command="{Binding RemoveCommand}"
                                                                            Padding="6,0" MinWidth="24"/>
                                                                </Grid>
                                                            </Grid>
                                                        </Border>
                                                    </DataTemplate>
                                                </ItemsControl.ItemTemplate>
                                            </ItemsControl>
                                        </ScrollViewer>
                                    </Grid>
                                </Border>

                                <!-- Photo column -->
                                <Border Grid.Column="1" Classes="elevated" Margin="3,0,0,0">
                                    <Grid RowDefinitions="Auto,Auto,Auto,*">
                                        <TextBlock Grid.Row="0" Text="{Binding PhotoColumnHeader}"
                                                   FontWeight="Bold" FontSize="13" Margin="10,8,10,6"/>
                                        <Border Grid.Row="1" Margin="8,0,8,6" Padding="8" MinHeight="60"
                                                CornerRadius="6" Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                DragDrop.AllowDrop="True"
                                                DragOver="OnDragOver" Drop="OnDropPhoto">
                                            <TextBlock Text="{Binding DropPhotoHintText}"
                                                       HorizontalAlignment="Center" VerticalAlignment="Center"
                                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                                        </Border>
                                        <Button Grid.Row="2" Content="{Binding AddFileButtonText}"
                                                Click="OnAddPhotoClick"
                                                HorizontalAlignment="Left" Margin="8,0,0,6"/>
                                        <ScrollViewer Grid.Row="3">
                                            <ItemsControl ItemsSource="{Binding PhotoAssets}" Margin="4">
                                                <ItemsControl.ItemsPanel>
                                                    <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                                </ItemsControl.ItemsPanel>
                                                <ItemsControl.ItemTemplate>
                                                    <DataTemplate>
                                                        <Border Width="140" Margin="4" Padding="6"
                                                                Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                                CornerRadius="6">
                                                            <Grid RowDefinitions="100,*,Auto">
                                                                <Border Background="{DynamicResource SystemControlBackgroundBaseHighBrush}"
                                                                        CornerRadius="4" ClipToBounds="True">
                                                                    <Image Source="{Binding Thumbnail}" Stretch="Uniform" Margin="2"/>
                                                                </Border>
                                                                <TextBlock Grid.Row="1" Text="{Binding DisplayName}" FontSize="11"
                                                                           TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
                                                                <Grid Grid.Row="2" ColumnDefinitions="*,Auto" Margin="0,4,0,0">
                                                                    <TextBlock Text="{Binding AssetTypeText}" FontSize="10"
                                                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                                                               VerticalAlignment="Center"/>
                                                                    <Button Grid.Column="1" Content="&#x00D7;"
                                                                            Command="{Binding RemoveCommand}"
                                                                            Padding="6,0" MinWidth="24"/>
                                                                </Grid>
                                                            </Grid>
                                                        </Border>
                                                    </DataTemplate>
                                                </ItemsControl.ItemTemplate>
                                            </ItemsControl>
                                        </ScrollViewer>
                                    </Grid>
                                </Border>
                            </Grid>
                        </Grid>
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
</UserControl>
'@

# ============ ModelCardView.axaml.cs (full rewrite) ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml.cs'] = @'
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    public ModelCardView()
    {
        InitializeComponent();
        DragDrop.SetAllowDrop(this, true);
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

# ============ README ============
$Files['patches\0.4.3f\README.md'] = @'
# Patch 0.4.3f - Associations: 2 columns (Reference / Photo)

**Iteration:** 0.4

## What it does

- VM:
  - Removed AssetTypeChoices, SelectedAssetType, AssetFilterChoices, SelectedAssetFilter, FilteredAssets.
  - Added ReferenceAssets, PhotoAssets (ObservableCollections).
  - RebuildFilteredAssets -> RebuildAssetColumns: split by type (reference/null -> Reference, photo -> Photo).
  - ImportAssetsAsync(paths, assetType): explicit type from drop zone / Add button.
  - ReferenceColumnHeader / PhotoColumnHeader from Card.AssetType.*.
  - DropReferenceHintText / DropPhotoHintText from Card.Assoc.DropReference / DropPhoto.
- ModelCardView.axaml: Associations TabItem fully rewritten - two equal columns.
  - Each column: header + drop zone + "Add" button + gallery of cards.
  - Toolbar at top: Auto-link + status text.
  - Removed type/filter ComboBoxes (no longer relevant).
- ModelCardView.axaml.cs: full rewrite.
  - OnDragOver, OnDropReference, OnDropPhoto.
  - OnAddReferenceClick, OnAddPhotoClick with file picker.

## Limitation (MVP)

- Assets with type render/document/profile are stored in DB but NOT displayed.
- Fix in 0.4.3f.1: add "Others" section if needed.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Open card -> Associations tab -> 2 columns visible.
- Drag PNG onto Reference column -> asset created with type=reference.
- Drag PNG onto Photo column -> asset created with type=photo.
- Add button in each column -> file picker -> imports with the column's type.
- Auto-link still works, populates Reference.
- Remove (x) button on each card removes from DB, file on disk stays.
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $vmPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    Backup-File $vmPath
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml.cs')
    Backup-File (Join-Path $ProjectRoot 'lang\en.json')
    Backup-File (Join-Path $ProjectRoot 'lang\ru.json')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ VM: replace associations block ============
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)

    $oldAssocBlock = @'
    public ObservableCollection<AssetRowViewModel> AssetRows { get; } = new();
    public ObservableCollection<AssetRowViewModel> FilteredAssets { get; } = new();

    public ObservableCollection<string> AssetTypeChoices { get; } = new()
    { "reference", "render", "photo", "document", "profile" };

    private string _selectedAssetType = "reference";
    public string SelectedAssetType { get => _selectedAssetType; set { _selectedAssetType = value; Raise(); } }

    public ObservableCollection<string> AssetFilterChoices { get; } = new()
    { "all", "reference", "render", "photo", "document", "profile" };

    private string _selectedAssetFilter = "all";
    public string SelectedAssetFilter
    {
        get => _selectedAssetFilter;
        set { _selectedAssetFilter = value; Raise(); RebuildFilteredAssets(); }
    }
'@
    $newAssocBlock = @'
    public ObservableCollection<AssetRowViewModel> AssetRows { get; } = new();
    public ObservableCollection<AssetRowViewModel> ReferenceAssets { get; } = new();
    public ObservableCollection<AssetRowViewModel> PhotoAssets { get; } = new();

    public string ReferenceColumnHeader => Loc("Card.AssetType.Reference", "Reference");
    public string PhotoColumnHeader => Loc("Card.AssetType.Photo", "Photo");
    public string DropReferenceHintText => Loc("Card.Assoc.DropReference", "Drop reference here");
    public string DropPhotoHintText => Loc("Card.Assoc.DropPhoto", "Drop photo here");
'@
    $oldNorm = $oldAssocBlock -replace "`r`n", "`n"
    $vmNorm = $vm -replace "`r`n", "`n"
    if ($vmNorm.Contains($oldNorm)) {
        $vmNorm = $vmNorm.Replace($oldNorm, ($newAssocBlock -replace "`r`n", "`n"))
        $vm = $vmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: replaced associations block'
    } elseif ($vm -match 'ReferenceAssets') {
        Write-Log 'VM: associations block already replaced, skipping.' 'WARN'
    } else {
        Write-Log 'VM: associations block marker not found - manual check needed.' 'WARN'
    }

    # Replace RebuildFilteredAssets with RebuildAssetColumns
    $oldRebuild = @'
    private void RebuildFilteredAssets()
    {
        FilteredAssets.Clear();
        foreach (var r in AssetRows)
            if (_selectedAssetFilter == "all" || r.Asset.AssetType == _selectedAssetFilter)
                FilteredAssets.Add(r);
    }
'@
    $newRebuild = @'
    private void RebuildAssetColumns()
    {
        ReferenceAssets.Clear();
        PhotoAssets.Clear();
        foreach (var r in AssetRows)
        {
            var t = r.Asset.AssetType?.ToLowerInvariant();
            if (t == "photo") PhotoAssets.Add(r);
            else if (t == "reference" || string.IsNullOrEmpty(t)) ReferenceAssets.Add(r);
            // render/document/profile: not displayed in MVP
        }
    }
'@
    $oldRN = $oldRebuild -replace "`r`n", "`n"
    $vmNorm = $vm -replace "`r`n", "`n"
    if ($vmNorm.Contains($oldRN)) {
        $vmNorm = $vmNorm.Replace($oldRN, ($newRebuild -replace "`r`n", "`n"))
        $vm = $vmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: replaced RebuildFilteredAssets with RebuildAssetColumns'
    }

    # Replace ImportAssetsAsync signature
    $oldImport = '    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths)'
    $newImport = '    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths, string assetType)'
    if ($vm.Contains($oldImport)) {
        $vm = $vm.Replace($oldImport, $newImport)
        # Inside body: ImportAsync(Model.Id, p, SelectedAssetType) -> ImportAsync(Model.Id, p, assetType)
        $vm = $vm.Replace('AppServices.AssetService.ImportAsync(Model.Id, p, SelectedAssetType)', 'AppServices.AssetService.ImportAsync(Model.Id, p, assetType)')
        Write-Log 'VM: ImportAssetsAsync signature updated'
    }

    # Replace RebuildFilteredAssets calls with RebuildAssetColumns calls
    $vm = $vm.Replace('RebuildFilteredAssets();', 'RebuildAssetColumns();')

    [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))

    # ============ Write XAML + code-behind ============
    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # ============ lang/en.json ============
    $enPath = Join-Path $ProjectRoot 'lang\en.json'
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Card.Assoc.PSObject.Properties.Name -contains 'DropReference')) {
            $en.Card.Assoc | Add-Member -NotePropertyName 'DropReference' -NotePropertyValue 'Drop reference here' -Force
        }
        if (-not ($en.Card.Assoc.PSObject.Properties.Name -contains 'DropPhoto')) {
            $en.Card.Assoc | Add-Member -NotePropertyName 'DropPhoto' -NotePropertyValue 'Drop photo here' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\en.json"
    }

    # ============ lang/ru.json (char-array) ============
    $ruPath = Join-Path $ProjectRoot 'lang\ru.json'
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $ruDropRef = -join ((0x041F,0x0435,0x0440,0x0435,0x0442,0x0430,0x0449,0x0438,0x0442,0x0435,0x0020,0x0440,0x0435,0x0444,0x0435,0x0440,0x0435,0x043D,0x0441,0x0020,0x0441,0x044E,0x0434,0x0430) | ForEach-Object { [char]$_ })
        $ruDropPhoto = -join ((0x041F,0x0435,0x0440,0x0435,0x0442,0x0430,0x0449,0x0438,0x0442,0x0435,0x0020,0x0444,0x043E,0x0442,0x043E,0x0020,0x0441,0x044E,0x0434,0x0430) | ForEach-Object { [char]$_ })
        if (-not ($ru.Card.Assoc.PSObject.Properties.Name -contains 'DropReference')) {
            $ru.Card.Assoc | Add-Member -NotePropertyName 'DropReference' -NotePropertyValue $ruDropRef -Force
        }
        if (-not ($ru.Card.Assoc.PSObject.Properties.Name -contains 'DropPhoto')) {
            $ru.Card.Assoc | Add-Member -NotePropertyName 'DropPhoto' -NotePropertyValue $ruDropPhoto -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\ru.json"
    }

    # ============ CHANGELOG ============
    $marker = '<!-- patch 0.4.3f applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3f] - 2026-11-12`r`n`r`n### Changed`r`n- Associations tab: 2 columns (Reference / Photo) with per-column drop zones and Add buttons.`r`n- Removed type/filter ComboBoxes (type from drop zone / button).`r`n- ImportAssetsAsync(paths, assetType).`r`n- render/document/profile assets stored but not displayed (MVP).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3e\.2\].*)$', "$entry`$1"
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