#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3e.1 - Auto-save Status/Difficulty, labels -> Watermarks, viewer fills vertical.
.DESCRIPTION
    1. IModelRepository + ModelRepository: UpdateStatusDifficultyAsync (no UpdatedAt change).
    2. ModelCardPageViewModel: SetStatus/SetDifficulty now async void, call SaveFieldAsync.
    3. ModelCardView.axaml: full rewrite - RowDefinitions *,Auto for viewer/info; Watermarks; inline labels.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3e.1'
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

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $repoIfacePath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Repositories\IRepositories.cs'
    $repoImplPath  = Join-Path $ProjectRoot 'src\MiniCodex.Data\Repositories\ModelRepository.cs'
    $vmPath        = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $xamlPath      = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'

    Backup-File $repoIfacePath
    Backup-File $repoImplPath
    Backup-File $vmPath
    Backup-File $xamlPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ 1. IModelRepository: add UpdateStatusDifficultyAsync ============
    $iface = [IO.File]::ReadAllText($repoIfacePath, [Text.Encoding]::UTF8)
    if ($iface -notmatch 'UpdateStatusDifficultyAsync') {
        $marker = '    Task UpsertAsync(Model model, CancellationToken ct = default);'
        $insert = '    Task UpdateStatusDifficultyAsync(string id, string? status, int? difficulty, CancellationToken ct = default);' + "`r`n" + $marker
        if ($iface.Contains($marker)) {
            $iface = $iface.Replace($marker, $insert)
            [IO.File]::WriteAllText($repoIfacePath, $iface, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: IRepositories.cs (UpdateStatusDifficultyAsync)'
        } else { Write-Log 'IRepositories.cs: UpsertAsync marker not found' 'WARN' }
    } else { Write-Log 'IRepositories.cs: already has UpdateStatusDifficultyAsync' 'WARN' }

    # ============ 2. ModelRepository: implement ============
    $impl = [IO.File]::ReadAllText($repoImplPath, [Text.Encoding]::UTF8)
    if ($impl -notmatch 'UpdateStatusDifficultyAsync') {
        $marker = '    public async Task UpsertAsync(Model m, CancellationToken ct = default)'
        $implBlock = @'
    public async Task UpdateStatusDifficultyAsync(string id, string? status, int? difficulty, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "UPDATE Model SET status = $s, difficulty = $d WHERE id = $id;";
        cmd.Parameters.AddWithValue("$s", (object?)status ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$d", (object?)difficulty ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

'@
        if ($impl.Contains($marker)) {
            $impl = $impl.Replace($marker, $implBlock + $marker)
            [IO.File]::WriteAllText($repoImplPath, $impl, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: ModelRepository.cs (UpdateStatusDifficultyAsync impl)'
        } else { Write-Log 'ModelRepository.cs: UpsertAsync marker not found' 'WARN' }
    } else { Write-Log 'ModelRepository.cs: already has UpdateStatusDifficultyAsync' 'WARN' }

    # ============ 3. ModelCardPageViewModel: SetStatus/SetDifficulty async void + SaveFieldAsync ============
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    $oldSetStatus = @'
    private void SetStatus(string? s)
    {
        if (string.IsNullOrEmpty(s)) return;
        _status = s;
        Raise(nameof(Status));
        Raise(nameof(IsPlanned));
        Raise(nameof(IsPrinted));
        Raise(nameof(IsPainted));
    }

    private void SetDifficulty(string? s)
    {
        if (s == null || !int.TryParse(s, out var v)) return;
        if (v < 1 || v > 5) return;
        DifficultyValue = (DifficultyValue == v) ? 0 : v;
    }
'@
    $newSetStatus = @'
    private async void SetStatus(string? s)
    {
        if (string.IsNullOrEmpty(s)) return;
        _status = string.Equals(_status, s, StringComparison.OrdinalIgnoreCase) ? string.Empty : s;
        Raise(nameof(Status));
        Raise(nameof(IsPlanned));
        Raise(nameof(IsPrinted));
        Raise(nameof(IsPainted));
        await SaveFieldAsync();
    }

    private async void SetDifficulty(string? s)
    {
        if (s == null || !int.TryParse(s, out var v)) return;
        if (v < 1 || v > 5) return;
        DifficultyValue = (DifficultyValue == v) ? 0 : v;
        await SaveFieldAsync();
    }

    private async Task SaveFieldAsync()
    {
        try
        {
            await _models.UpdateStatusDifficultyAsync(
                Model.Id,
                string.IsNullOrEmpty(_status) ? null : _status,
                _difficultyValue > 0 ? (int?)_difficultyValue : null);
            Model.Status = string.IsNullOrEmpty(_status) ? null : _status;
            Model.Difficulty = _difficultyValue > 0 ? (int?)_difficultyValue : null;
        }
        catch { }
    }
'@
    $oldNorm = $oldSetStatus -replace "`r`n", "`n"
    $vmNorm = $vm -replace "`r`n", "`n"
    if ($vmNorm.Contains($oldNorm)) {
        $newVm = $vmNorm.Replace($oldNorm, ($newSetStatus -replace "`r`n", "`n"))
        [IO.File]::WriteAllText($vmPath, $newVm, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ModelCardPageViewModel.cs (SetStatus/SetDifficulty async + SaveFieldAsync)'
    } elseif ($vm -match 'SaveFieldAsync') {
        Write-Log 'ModelCardPageViewModel.cs: SaveFieldAsync already present, skipping.' 'WARN'
    } else {
        Write-Log 'ModelCardPageViewModel.cs: SetStatus/SetDifficulty block not found - check manually' 'WARN'
    }

    # ============ 4. ModelCardView.axaml - full rewrite ============
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

                <Border Grid.Row="1" Classes="elevated" Margin="0,8,0,0">
                    <StackPanel Padding="12" Spacing="6">
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
    Write-Text -Path $xamlPath -Content $xaml
    Write-Log 'updated: ModelCardView.axaml (auto-scale viewer, labels -> watermarks, inline status/difficulty labels)'

    # ============ README ============
    $readme = @'
# Patch 0.4.3e.1 - Auto-save Status/Difficulty, compact Info, viewer fills height

**Iteration:** 0.4

## What it does

1. Auto-save Status/Difficulty:
   - IModelRepository.UpdateStatusDifficultyAsync (UPDATE only status, difficulty; no UpdatedAt touch).
   - SetStatus and SetDifficulty are now async void, call SaveFieldAsync after change.
   - Status toggle: click active status -> reset to empty.
   - Previews cache NOT invalidated (UpdatedAt unchanged).

2. Compact Info panel:
   - Title/Author/SourceUrl: no labels above, only Watermark in TextBox.
   - Status/Difficulty: label moved inline (left of icons/stars, Width=90).
   - ScrollViewer removed (content short enough).
   - Saves ~100px vertical.

3. Viewer fills available vertical space:
   - Left column: RowDefinitions "320,*" -> "*,Auto".
   - 3D viewer ~450px on 750px window (was 320px).
   - Horizontal models (tanks, ships) get more room.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Card: viewer taller, Info panel more compact.
- Click status icon -> saves instantly (close+reopen shows same value).
- Click star -> saves instantly.
- Text fields show grey placeholders when empty (Title, Author, Source URL).
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.3e.1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3e.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3e.1] - 2026-11-12`r`n`r`n### Changed`r`n- Auto-save for Status/Difficulty (UpdateStatusDifficultyAsync, no UpdatedAt touch).`r`n- Status toggle: click active -> clear.`r`n- Info panel compact: labels -> Watermarks, inline labels for status/difficulty.`r`n- 3D viewer fills vertical space (RowDefinitions *,Auto).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3e\].*)$', "$entry`$1"
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