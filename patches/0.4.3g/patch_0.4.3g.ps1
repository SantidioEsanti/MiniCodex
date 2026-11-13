#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3g - Associations tab: reorder, stacked sections, 256px thumbs, hint-as-placeholder.
.DESCRIPTION
    ModelCardView.axaml full rewrite (Assoc first tab, stacked Reference/Photo, 256px, empty-state hint).
    ModelCardPageViewModel: _selectedTabIndex = 0, HasReferenceAssets/HasPhotoAssets, raises in RebuildAssetColumns.
    LibraryViewModel: "Add tag" opens Tags tab (index 2, was 3).
    AssetService: thumbnail filename {id}_256.png, size 256.
    Old {id}.png thumbs cleaned from dev bin/ (best effort).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3g'
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

# ============ ModelCardView.axaml (full rewrite) ============
$xaml = @'
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
                    <TabItem Header="{Binding TabAssociationsHeader}">
                        <Grid RowDefinitions="Auto,*">
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                                <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                                <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                            </StackPanel>

                            <Grid Grid.Row="1" RowDefinitions="*,*" Margin="6">
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
                                                                        CornerRadius="6" ClipToBounds="True">
                                                                    <Grid>
                                                                        <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>
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
                                                                        CornerRadius="6" ClipToBounds="True">
                                                                    <Grid>
                                                                        <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>
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
</UserControl>
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $xamlPath    = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    $vmPath      = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $libPath     = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $assetSvcPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\AssetService.cs'

    Backup-File $xamlPath
    Backup-File $vmPath
    Backup-File $libPath
    Backup-File $assetSvcPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # 1. XAML full rewrite
    Write-Text -Path $xamlPath -Content $xaml
    Write-Log 'updated: ModelCardView.axaml (Assoc first tab, stacked sections, 256px, hint placeholder)'

    # 2. VM: _selectedTabIndex = 0 + HasReferenceAssets/HasPhotoAssets + raises
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)

    if ($vm -match '_selectedTabIndex = 1;') {
        $vm = $vm.Replace('private int _selectedTabIndex = 1; // Default: Associations (0.4.3d - Info moved to left panel)',
                          'private int _selectedTabIndex = 0; // Default: Associations (0.4.3g - Assoc is first tab)')
        $vm = $vm.Replace('private int _selectedTabIndex = 1;',
                          'private int _selectedTabIndex = 0;')
        Write-Log 'VM: _selectedTabIndex = 0'
    }

    if ($vm -notmatch 'HasReferenceAssets\s*=>') {
        $oldDecl = '    public ObservableCollection<AssetRowViewModel> ReferenceAssets { get; } = new();' + "`r`n" +
                   '    public ObservableCollection<AssetRowViewModel> PhotoAssets { get; } = new();'
        $newDecl = $oldDecl + "`r`n" + "`r`n" +
                   '    public bool HasReferenceAssets => ReferenceAssets.Count > 0;' + "`r`n" +
                   '    public bool HasPhotoAssets => PhotoAssets.Count > 0;'
        if ($vm.Contains($oldDecl)) {
            $vm = $vm.Replace($oldDecl, $newDecl)
            Write-Log 'VM: added HasReferenceAssets/HasPhotoAssets'
        }
    }

    # Add Raise in RebuildAssetColumns
    $oldRebuildEnd = '            // render/document/profile: not displayed in MVP' + "`r`n" +
                     '        }' + "`r`n" +
                     '    }'
    $newRebuildEnd = '            // render/document/profile: not displayed in MVP' + "`r`n" +
                     '        }' + "`r`n" +
                     '        Raise(nameof(HasReferenceAssets));' + "`r`n" +
                     '        Raise(nameof(HasPhotoAssets));' + "`r`n" +
                     '    }'
    if ($vm.Contains($oldRebuildEnd) -and ($vm -notmatch 'Raise\(nameof\(HasReferenceAssets\)\)')) {
        $vm = $vm.Replace($oldRebuildEnd, $newRebuildEnd)
        Write-Log 'VM: RebuildAssetColumns raises HasReferenceAssets/HasPhotoAssets'
    }

    [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))

    # 3. LibraryViewModel: fix "Add tag" tab index 3 -> 2
    $lib = [IO.File]::ReadAllText($libPath, [Text.Encoding]::UTF8)
    if ($lib.Contains('(m, 3)')) {
        $lib = $lib.Replace('OnAddTagForModel(Model m) => OpenCardWithTabRequested?.Invoke(this, (m, 3));',
                            'OnAddTagForModel(Model m) => OpenCardWithTabRequested?.Invoke(this, (m, 2));')
        [IO.File]::WriteAllText($libPath, $lib, [Text.UTF8Encoding]::new($false))
        Write-Log 'LibraryViewModel: Add-tag tab index 3 -> 2 (Tags)'
    }

    # 4. AssetService: thumbnail 128 -> 256 with _256 suffix
    $assetSvc = [IO.File]::ReadAllText($assetSvcPath, [Text.Encoding]::UTF8)
    if ($assetSvc -notmatch '_256\.png') {
        $assetSvc = $assetSvc.Replace(
            'var thumbPath = Path.Combine(_thumbsRoot, asset.Id + ".png");',
            'var thumbPath = Path.Combine(_thumbsRoot, asset.Id + "_256.png");')
        $assetSvc = $assetSvc.Replace(
            'var bytes = await Task.Run(() => _thumbs.Generate(asset.AbsolutePath, type, 128), ct);',
            'var bytes = await Task.Run(() => _thumbs.Generate(asset.AbsolutePath, type, 256), ct);')
        [IO.File]::WriteAllText($assetSvcPath, $assetSvc, [Text.UTF8Encoding]::new($false))
        Write-Log 'AssetService: thumbnail 128 -> 256 with _256 suffix'
    }

    # 5. Cleanup old 128px thumbs (best effort, dev paths)
    $thumbDirs = @(
        (Join-Path $ProjectRoot 'src\MiniCodex.App\bin\Debug\net8.0\data\cache\asset-thumbs'),
        (Join-Path $ProjectRoot 'dist\data\cache\asset-thumbs'),
        (Join-Path $ProjectRoot 'data\cache\asset-thumbs')
    )
    foreach ($d in $thumbDirs) {
        if (Test-Path $d) {
            try {
                $removed = 0
                Get-ChildItem -Path $d -Filter '*.png' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '_256\.png$' } |
                    ForEach-Object { Remove-Item -Force -ErrorAction SilentlyContinue; $removed++ }
                if ($removed -gt 0) { Write-Log "cleaned $removed old thumbs in $d" }
            } catch { }
        }
    }

    # README
    $readme = @'
# Patch 0.4.3g - Associations: reorder, stacked, 256px

**Iteration:** 0.4

## What it does

1. Tab reorder: Associations first (default), then Files, Tags, Scale, Notes.
   _selectedTabIndex = 0.
   Fix bug from 0.4.3d: "Add tag" context menu opened Scale instead of Tags (index 3 -> 2).

2. Associations: Reference (top) and Photo (bottom) as separate elevated sections,
   stacked vertically, each with header + add button + drop zone.

3. Drop hint as placeholder:
   - Drop hint visible only when collection is empty (!HasReferenceAssets / !HasPhotoAssets).
   - Whole drop-zone area is drop target (Border with DragDrop.DragOver/Drop).

4. Thumbnails 256x256:
   - AssetService: thumbnail filename {assetId}_256.png, size 256 (was 128).
   - UI shows image at 256x256, no text label below; remove (x) overlay top-right (semi-transparent).
   - Old 128px thumbs ({assetId}.png) cleaned from dev bin/data/cache/asset-thumbs/.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Open card -> Associations tab first, two stacked sections.
- Empty section shows centered drop hint.
- Add file -> hint disappears, 256x256 image with x overlay top-right.
- Drag to any part of drop area works.
- Old assets regenerate at 256px on next view.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3g\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3g applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3g] - 2026-11-12`r`n`r`n### Changed`r`n- Associations tab is first and default (0).`r`n- Reference and Photo stacked vertically as separate elevated sections.`r`n- Drop hint is empty-state placeholder; whole area is drop zone.`r`n- Thumbnails 256x256, no text labels below, remove button overlay.`r`n- Fixed: Add-tag context menu opens Tags (was Scale).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3f\.1\].*)$', "$entry`$1"
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