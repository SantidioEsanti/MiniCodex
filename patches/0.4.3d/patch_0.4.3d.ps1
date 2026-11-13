#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3d - Card view layout: viewer + Info panel below, tabs right (no Info), Associations default, rounded borders.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3d'
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
            <Grid Grid.Column="0" RowDefinitions="320,*" Margin="0,0,8,0">
                <Border Grid.Row="0" Classes="elevated">
                    <views:ThreeDViewer
                        MeshFilePath="{Binding MeshFilePath}"
                        MinLambert="{Binding MinLambertValue}"
                        Wireframe="{Binding WireframeMode}"
                        Yaw="{Binding ViewerYaw, Mode=TwoWay}"
                        Pitch="{Binding ViewerPitch, Mode=TwoWay}"/>
                </Border>

                <Border Grid.Row="1" Classes="elevated" Margin="0,8,0,0">
                    <ScrollViewer Padding="12">
                        <StackPanel Spacing="6">
                            <TextBlock Text="{Binding LabelTitle}"/>
                            <TextBox Text="{Binding Title}"/>
                            <TextBlock Text="{Binding LabelAuthor}"/>
                            <TextBox Text="{Binding Author}"/>
                            <TextBlock Text="{Binding LabelSourceUrl}"/>
                            <TextBox Text="{Binding SourceUrl}"/>
                            <TextBlock Text="{Binding LabelStatus}"/>
                            <TextBox Text="{Binding Status}"/>
                            <TextBlock Text="{Binding LabelDifficulty}"/>
                            <TextBox Text="{Binding Difficulty}"/>
                        </StackPanel>
                    </ScrollViewer>
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
                        <Grid RowDefinitions="Auto,Auto,*">
                            <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                                <ComboBox ItemsSource="{Binding AssetTypeChoices}" SelectedItem="{Binding SelectedAssetType}" Width="110"/>
                                <Button Content="{Binding AddFileButtonText}" Click="OnAddFileClick"/>
                                <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                                <ComboBox ItemsSource="{Binding AssetFilterChoices}" SelectedItem="{Binding SelectedAssetFilter}" Width="110" Margin="12,0,0,0"/>
                                <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                            </StackPanel>
                            <Border Grid.Row="1" Margin="6" Padding="8" MinHeight="60"
                                    CornerRadius="6" Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                    DragDrop.AllowDrop="True">
                                <TextBlock Text="{Binding DropHintText}" HorizontalAlignment="Center" VerticalAlignment="Center"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                            </Border>
                            <ScrollViewer Grid.Row="2">
                                <ItemsControl ItemsSource="{Binding FilteredAssets}" Margin="6">
                                    <ItemsControl.ItemsPanel>
                                        <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                    </ItemsControl.ItemsPanel>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border Width="150" Margin="4" Padding="6"
                                                    BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                                    BorderThickness="1" CornerRadius="4">
                                                <Grid RowDefinitions="100,*,Auto">
                                                    <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}" CornerRadius="2">
                                                        <Image Source="{Binding Thumbnail}" Stretch="Uniform" Margin="2"/>
                                                    </Border>
                                                    <TextBlock Grid.Row="1" Text="{Binding DisplayName}" FontSize="11"
                                                               TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
                                                    <Grid Grid.Row="2" ColumnDefinitions="*,Auto" Margin="0,4,0,0">
                                                        <TextBlock Text="{Binding AssetTypeText}" FontSize="10"
                                                                   Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                                                   VerticalAlignment="Center"/>
                                                        <Button Grid.Column="1" Content="&#x00D7;" Command="{Binding RemoveCommand}"
                                                                Padding="6,0" MinWidth="24"/>
                                                    </Grid>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </ScrollViewer>
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

# ============ README ============
$Files['patches\0.4.3d\README.md'] = @'
# Patch 0.4.3d - Card view layout restructure

**Iteration:** 0.4

## What it does

- ModelCardView.axaml (full rewrite):
  - Left column (480px): ThreeDViewer (fixed 320px height) + Info panel below (Title, Author, SourceURL, Status, Difficulty - editable fields).
  - Right column: TabControl (Files, Associations, Tags, Scale, Notes) - Info tab removed.
  - Default tab: Associations (index 1).
  - All major panels wrapped in Border.elevated (rounded + soft shadow).
  - Drop zone in Associations: removed hard border, only background.
- ModelCardPageViewModel.cs (one line):
  - _selectedTabIndex = 1 (Associations default after Info moved to left panel).
- App.axaml (one style added):
  - Border.elevated: CardBackgroundBrush + CornerRadius 8 + BoxShadow + ClipToBounds.

## Deferred

- 0.4.3e: Status as clickable buttons, Difficulty as 5 stars.
- 0.4.3f: Associations two-column (Reference / Photo with separate drop zones).

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Open card: left column has square 3D viewer (320px) with Info panel below.
- Right column: tabs without Info.
- Default tab: Associations.
- All panels (viewer, info, tabs) have rounded corners and soft shadow.
- Library tiles still have rounded corners with shadow (0.4.3c).
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # --- ViewModel: _selectedTabIndex = 1 ---
    $vmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    if ($vm -notmatch '_selectedTabIndex = 1;') {
        $vm = $vm.Replace(
            'private int _selectedTabIndex;',
            'private int _selectedTabIndex = 1; // Default: Associations (0.4.3d - Info moved to left panel)'
        )
        [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs (_selectedTabIndex = 1)'
    } else {
        Write-Log 'ModelCardPageViewModel.cs: _selectedTabIndex already = 1, skipping.' 'WARN'
    }

    # --- App.axaml: insert Border.elevated style ---
    $appPath = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml'
    $app = [IO.File]::ReadAllText($appPath, [Text.Encoding]::UTF8)
    if ($app -notmatch 'Border\.elevated') {
        $marker = '        <Style Selector="Border.card">'
        $insert = @'
        <Style Selector="Border.elevated">
            <Setter Property="Background" Value="{DynamicResource CardBackgroundBrush}"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="BoxShadow" Value="0 2 8 0 #18000000"/>
            <Setter Property="ClipToBounds" Value="True"/>
        </Style>

'@
        if ($app.Contains($marker)) {
            $app = $app.Replace($marker, $insert + $marker)
            [IO.File]::WriteAllText($appPath, $app, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: src\MiniCodex.App\App.axaml (Border.elevated)'
        } else {
            Write-Log 'App.axaml: marker Border.card not found - MANUAL EDIT NEEDED.' 'WARN'
        }
    } else {
        Write-Log 'App.axaml: Border.elevated already present, skipping.' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.3d applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3d] - 2026-11-12`r`n`r`n### Changed`r`n- Card view: 3D viewer (320px) + Info panel below; tabs right without Info.`r`n- Default tab: Associations.`r`n- Rounded borders (Border.elevated) on viewer, info panel, tab control.`r`n- Associations drop zone: removed hard border.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3c\].*)$', "$entry`$1"
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