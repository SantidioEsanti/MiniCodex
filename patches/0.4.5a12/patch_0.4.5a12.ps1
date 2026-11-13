#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a12 - Smooth hover rotation (120deg), first-scan warning, theme icon button.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a12'
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

# ============ PreviewGeneratorOptions.cs (120deg) ============
$optionsCs = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 384;
    public int Height { get; set; } = 384;
    public float PitchDegrees { get; set; } = 15f;

    // 4 stops over 120deg (180 -> 300). Smoother hover rotation than the old 270deg span.
    public float[] YawDegrees { get; set; } = { 180f, 220f, 260f, 300f };

    public int Supersample { get; set; } = 2;
}
'@

# ============ LibraryView.axaml (full rewrite with warning overlay) ============
$libraryXamlCs = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             x:Class="MiniCodex.App.Views.LibraryView"
             x:DataType="vm:LibraryViewModel">
    <Panel>
        <Grid ColumnDefinitions="200,*">
            <Border Grid.Column="0"
                    BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                    BorderThickness="0,0,1,0" Padding="4">
                <Grid RowDefinitions="Auto,*">
                    <TextBlock Grid.Row="0" Text="{Binding TagsHeader}" FontWeight="Bold" Margin="6,4,6,8"/>
                    <ListBox Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag}">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid ColumnDefinitions="*,Auto">
                                    <TextBlock Text="{Binding Name}" TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Grid.Column="1" Text="{Binding UsageCount}"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               FontSize="11" Margin="6,0,0,0"/>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </Grid>
            </Border>

            <Grid Grid.Column="1" RowDefinitions="Auto,*">
                <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">
                    <TextBox x:Name="SearchBox" Text="{Binding SearchQuery}"
                             Watermark="{Binding SearchPlaceholder}" Width="300" VerticalAlignment="Center"/>
                    <Button Content="{Binding ScanButtonText}" Click="OnScanClick"/>
                    <TextBlock Text="{Binding StatusText}" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                    <ProgressBar IsIndeterminate="True" IsVisible="{Binding IsBusy}"
                                 Width="120" VerticalAlignment="Center"/>
                </StackPanel>

                <ScrollViewer Grid.Row="1">
                    <ItemsControl ItemsSource="{Binding Cards}" Margin="4">
                        <ItemsControl.ItemsPanel>
                            <ItemsPanelTemplate>
                                <WrapPanel Orientation="Horizontal"/>
                            </ItemsPanelTemplate>
                        </ItemsControl.ItemsPanel>
                        <ItemsControl.ItemTemplate>
                            <DataTemplate DataType="vm:ModelCardViewModel">
                                <views:ModelCardTile/>
                            </DataTemplate>
                        </ItemsControl.ItemTemplate>
                    </ItemsControl>
                </ScrollViewer>

                <TextBlock Grid.Row="1" Text="{Binding EmptyStateText}"
                           HorizontalAlignment="Center" VerticalAlignment="Center"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                           IsVisible="{Binding IsEmpty}"/>
            </Grid>
        </Grid>

        <Border IsVisible="{Binding ShowScanWarning}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="520"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding ScanWarningTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBlock Text="{Binding ScanWarningMessage}" TextWrapping="Wrap" MaxWidth="470"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding ScanWarningCancelText}" Command="{Binding CancelScanCommand}" Padding="14,8"/>
                        <Button Content="{Binding ScanWarningContinueText}" Command="{Binding ConfirmScanCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>
    </Panel>
</UserControl>
'@

# ============ MainWindow.axaml (theme button) ============
$mainWindowXamlCs = @'
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="MiniCodex.App.Views.MainWindow"
        Title="{Binding Title}" Icon="/Assets/icon.ico"
        Width="1100" Height="750">
    <Window.KeyBindings>
        <KeyBinding Gesture="Ctrl+F" Command="{Binding RequestFocusSearchCommand}"/>
    </Window.KeyBindings>
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding LibraryButtonText}" Command="{Binding ShowLibraryCommand}"/>
            <Button Content="{Binding SettingsButtonText}" Command="{Binding ShowSettingsCommand}"/>
            <Button Content="{Binding AboutButtonText}" Command="{Binding ShowAboutCommand}"/>
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120" Margin="16,0,0,0"/>
            <Button Command="{Binding CycleThemeCommand}"
                    ToolTip.Tip="{Binding ThemeTooltip}"
                    Padding="10,6" MinWidth="40" VerticalAlignment="Center">
                <TextBlock Text="{Binding ThemeIconGlyph}"
                           FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                           FontSize="16"
                           VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Button>
        </StackPanel>
        <ContentControl Grid.Row="1" Content="{Binding CurrentPage}"/>
    </Grid>
</Window>
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $optionsPath    = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'
    $previewGenPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    $libVmPath      = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $mainVmPath     = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'
    $libXamlPath    = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
    $mainXamlPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\MainWindow.axaml'
    $enPath         = Join-Path $ProjectRoot 'lang\en.json'
    $ruPath         = Join-Path $ProjectRoot 'lang\ru.json'

    Backup-File $optionsPath
    Backup-File $previewGenPath
    Backup-File $libVmPath
    Backup-File $mainVmPath
    Backup-File $libXamlPath
    Backup-File $mainXamlPath
    Backup-File $enPath
    Backup-File $ruPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # 1. Options: 120deg
    Write-Text -Path $optionsPath -Content $optionsCs
    Write-Log 'updated: PreviewGeneratorOptions.cs (YawDegrees 180/220/260/300)'

    # 2. RendererVersion bump (angles changed -> regen needed)
    $pg = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    $pg = $pg -replace 'RendererVersion\s*=\s*"0\.4\.5a\d+(\.\d+)?"', 'RendererVersion = "0.4.5a12"'
    [IO.File]::WriteAllText($previewGenPath, $pg, [Text.UTF8Encoding]::new($false))
    Write-Log 'updated: PreviewGenerator.cs (RendererVersion = 0.4.5a12)'

    # 3. XAML: LibraryView (with overlay)
    Write-Text -Path $libXamlPath -Content $libraryXamlCs
    Write-Log 'updated: LibraryView.axaml (scan warning overlay)'

    # 4. XAML: MainWindow (theme button)
    Write-Text -Path $mainXamlPath -Content $mainWindowXamlCs
    Write-Log 'updated: MainWindow.axaml (theme button instead of ComboBox)'

    # 5. LibraryViewModel: scan warning + commands
    $libVm = [IO.File]::ReadAllText($libVmPath, [Text.Encoding]::UTF8)

    # 5a. Add ShowScanWarning + fields after _isBusy
    $oldBusy = @'
    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); Raise(nameof(IsEmpty)); }
    }
'@
    $newBusy = $oldBusy + @'

    private bool _showScanWarning;
    public bool ShowScanWarning
    {
        get => _showScanWarning;
        private set { _showScanWarning = value; Raise(); }
    }

    private List<string> _pendingScanFolders = new();

    public string ScanWarningTitle => App.Loc?.Get("Library.ScanWarning.Title") ?? "Long scan";
    public string ScanWarningMessage => App.Loc?.Get("Library.ScanWarning.Message") ?? "Large libraries with high-poly models may take 15-30 minutes. The app stays responsive and shows progress. Continue?";
    public string ScanWarningContinueText => App.Loc?.Get("Library.ScanWarning.Continue") ?? "Continue";
    public string ScanWarningCancelText => App.Loc?.Get("Library.ScanWarning.Cancel") ?? "Cancel";
'@
    if ($libVm.Contains($oldBusy)) {
        $libVm = $libVm.Replace($oldBusy, $newBusy)
        Write-Log 'VM: added ShowScanWarning + pending folders + warning strings'
    }

    # 5b. Add commands declaration after RequestFocusSearchCommand
    $oldCmd = '    public ICommand RequestFocusSearchCommand { get; }'
    $newCmd = $oldCmd + "`r`n" + '    public ICommand ConfirmScanCommand { get; }' + "`r`n" + '    public ICommand CancelScanCommand { get; }'
    if ($libVm.Contains($oldCmd) -and ($libVm -notmatch 'ConfirmScanCommand\s*\{\s*get')) {
        $libVm = $libVm.Replace($oldCmd, $newCmd)
        Write-Log 'VM: added ConfirmScanCommand / CancelScanCommand declarations'
    }

    # 5c. Init commands in ctor
    $oldInit = '        RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));'
    $newInit = $oldInit + "`r`n" +
               '        ConfirmScanCommand = new RelayCommand(async () => await ConfirmScanAsync());' + "`r`n" +
               '        CancelScanCommand = new RelayCommand(CancelScan);'
    if ($libVm.Contains($oldInit) -and ($libVm -notmatch 'ConfirmScanCommand = new RelayCommand')) {
        $libVm = $libVm.Replace($oldInit, $newInit)
        Write-Log 'VM: initialized ConfirmScanCommand / CancelScanCommand'
    }

    # 5d. Replace ScanAsync body with warning check + DoScanAsync
    $oldScanStart = @'
    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        var folderList = folders.ToList();
        Log.Info("[LibraryViewModel] ScanAsync begin folders=" + folderList.Count +
                 " scanner=" + (_scanner != null) + " models=" + (_models != null) + " files=" + (_files != null));

        if (_scanner == null || _models == null || _files == null || _previews == null)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        if (folderList.Count == 0) return;

        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner.ScanAsync(folderList, progress, ct);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ScanAsync exception", ex); }
        finally
        {
            try { await LoadTagsAsync(ct); } catch { }
            try { await ReloadModelsCoreAsync(ct); } catch { }
            IsBusy = false;
        }
    }
'@
    $newScanStart = @'
    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        var folderList = folders.ToList();
        Log.Info("[LibraryViewModel] ScanAsync begin folders=" + folderList.Count +
                 " scanner=" + (_scanner != null) + " models=" + (_models != null) + " files=" + (_files != null));

        if (_scanner == null || _models == null || _files == null || _previews == null)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        if (folderList.Count == 0) return;

        // First-scan warning (once, persisted in Setting)
        if (AppServices.Settings != null)
        {
            try
            {
                var warningShown = await AppServices.Settings.GetAsync("Scan.WarningShown", ct);
                if (warningShown != "true")
                {
                    _pendingScanFolders = folderList;
                    ShowScanWarning = true;
                    Log.Info("[LibraryViewModel] First scan -> showing warning dialog");
                    return;
                }
            }
            catch (Exception ex) { Log.Exception("[LibraryViewModel] read Scan.WarningShown failed", ex); }
        }

        await DoScanAsync(folderList, ct);
    }

    private async Task ConfirmScanAsync()
    {
        ShowScanWarning = false;
        if (AppServices.Settings != null)
        {
            try { await AppServices.Settings.SetAsync("Scan.WarningShown", "true"); } catch { }
        }
        var folders = _pendingScanFolders;
        _pendingScanFolders = new List<string>();
        if (folders.Count > 0)
        {
            Log.Info("[LibraryViewModel] Warning confirmed -> starting scan");
            await DoScanAsync(folders, CancellationToken.None);
        }
    }

    private void CancelScan()
    {
        ShowScanWarning = false;
        _pendingScanFolders = new List<string>();
        Log.Info("[LibraryViewModel] Warning cancelled -> scan not started");
    }

    private async Task DoScanAsync(List<string> folderList, CancellationToken ct)
    {
        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner!.ScanAsync(folderList, progress, ct);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] DoScanAsync exception", ex); }
        finally
        {
            try { await LoadTagsAsync(ct); } catch { }
            try { await ReloadModelsCoreAsync(ct); } catch { }
            IsBusy = false;
        }
    }
'@
    $libVmNorm = $libVm -replace "`r`n", "`n"
    $oldScanNorm = $oldScanStart -replace "`r`n", "`n"
    if ($libVmNorm.Contains($oldScanNorm)) {
        $libVmNorm = $libVmNorm.Replace($oldScanNorm, ($newScanStart -replace "`r`n", "`n"))
        $libVm = $libVmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: ScanAsync -> warning dialog + DoScanAsync'
    } else {
        Write-Log 'VM: ScanAsync block not matched - check manually' 'WARN'
    }

    # 5e. Add RefreshLocalized entries for warning strings
    $oldRefresh = '        Raise(nameof(TagsHeader));'
    $newRefresh = $oldRefresh + "`r`n" +
                  '        Raise(nameof(ScanWarningTitle));' + "`r`n" +
                  '        Raise(nameof(ScanWarningMessage));' + "`r`n" +
                  '        Raise(nameof(ScanWarningContinueText));' + "`r`n" +
                  '        Raise(nameof(ScanWarningCancelText));'
    if ($libVm.Contains($oldRefresh) -and ($libVm -notmatch 'Raise\(nameof\(ScanWarningTitle\)\)')) {
        $libVm = $libVm.Replace($oldRefresh, $newRefresh)
        Write-Log 'VM: RefreshLocalized includes scan-warning strings'
    }

    [IO.File]::WriteAllText($libVmPath, $libVm, [Text.UTF8Encoding]::new($false))

    # 6. MainWindowViewModel: theme button
    $mainVm = [IO.File]::ReadAllText($mainVmPath, [Text.Encoding]::UTF8)

    # 6a. Remove Themes collection
    $mainVm = $mainVm.Replace('    public ObservableCollection<string> Themes { get; } = new() { "light", "dark", "auto" };' + "`r`n", '')

    # 6b. Modify CurrentTheme setter + add icon/tooltip/command
    $oldTheme = @'
    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set { if (Set(ref _theme, value)) App.Theme.Apply(value); }
    }
'@
    $newTheme = @'
    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set
        {
            if (!Set(ref _theme, value)) return;
            App.Theme.Apply(value);
            Raise(nameof(ThemeIconGlyph));
            Raise(nameof(ThemeTooltip));
        }
    }

    public string ThemeIconGlyph => _theme switch
    {
        "light" => "\uE706",
        "dark" => "\uE708",
        _ => "\uE7F4",
    };

    public string ThemeTooltip => _theme switch
    {
        "light" => App.Loc?.Get("Settings.Theme.Light") ?? "Light",
        "dark" => App.Loc?.Get("Settings.Theme.Dark") ?? "Dark",
        _ => App.Loc?.Get("Settings.Theme.Auto") ?? "Auto",
    };

    public ICommand CycleThemeCommand { get; }
'@
    $mainVmNorm = $mainVm -replace "`r`n", "`n"
    $oldThemeNorm = $oldTheme -replace "`r`n", "`n"
    if ($mainVmNorm.Contains($oldThemeNorm)) {
        $mainVmNorm = $mainVmNorm.Replace($oldThemeNorm, ($newTheme -replace "`r`n", "`n"))
        $mainVm = $mainVmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'MainVM: theme icon + tooltip + CycleThemeCommand'
    }

    # 6c. Init CycleThemeCommand in ctor
    $oldMainInit = '        RequestFocusSearchCommand = new RelayCommand(() =>'
    $newMainInit = '        CycleThemeCommand = new RelayCommand(() =>' + "`r`n" +
                   '        {' + "`r`n" +
                   '            CurrentTheme = _theme switch' + "`r`n" +
                   '            {' + "`r`n" +
                   '                "auto" => "light",' + "`r`n" +
                   '                "light" => "dark",' + "`r`n" +
                   '                _ => "auto",' + "`r`n" +
                   '            };' + "`r`n" +
                   '        });' + "`r`n" +
                   '        RequestFocusSearchCommand = new RelayCommand(() =>'
    if ($mainVm.Contains($oldMainInit) -and ($mainVm -notmatch 'CycleThemeCommand = new RelayCommand')) {
        $mainVm = $mainVm.Replace($oldMainInit, $newMainInit)
        Write-Log 'MainVM: CycleThemeCommand init'
    }

    # 6d. RefreshLocalized: raise ThemeTooltip when language changes
    $oldLangRaise = '            Raise(nameof(AboutButtonText));'
    $newLangRaise = $oldLangRaise + "`r`n" + '            Raise(nameof(ThemeTooltip));'
    if ($mainVm.Contains($oldLangRaise) -and ($mainVm -notmatch 'Raise\(nameof\(ThemeTooltip\)\)')) {
        $mainVm = $mainVm.Replace($oldLangRaise, $newLangRaise)
        Write-Log 'MainVM: CurrentLanguage raises ThemeTooltip'
    }

    [IO.File]::WriteAllText($mainVmPath, $mainVm, [Text.UTF8Encoding]::new($false))

    # 7. lang/en.json
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Library.PSObject.Properties.Name -contains 'ScanWarning')) {
            $en.Library | Add-Member -NotePropertyName 'ScanWarning' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not ($en.Library.ScanWarning.PSObject.Properties.Name -contains 'Title')) {
            $en.Library.ScanWarning | Add-Member -NotePropertyName 'Title' -NotePropertyValue 'Long scan' -Force
        }
        if (-not ($en.Library.ScanWarning.PSObject.Properties.Name -contains 'Message')) {
            $en.Library.ScanWarning | Add-Member -NotePropertyName 'Message' -NotePropertyValue 'Large libraries with high-poly models may take 15-30 minutes or more. The app stays responsive and shows progress. Continue?' -Force
        }
        if (-not ($en.Library.ScanWarning.PSObject.Properties.Name -contains 'Continue')) {
            $en.Library.ScanWarning | Add-Member -NotePropertyName 'Continue' -NotePropertyValue 'Continue' -Force
        }
        if (-not ($en.Library.ScanWarning.PSObject.Properties.Name -contains 'Cancel')) {
            $en.Library.ScanWarning | Add-Member -NotePropertyName 'Cancel' -NotePropertyValue 'Cancel' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log 'lang/en.json: Library.ScanWarning.*'
    }

    # 8. lang/ru.json (char-codes for Cyrillic)
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

        $ruTitle = -join ((0x0414,0x043E,0x043B,0x0433,0x043E,0x0435,0x0020,0x0441,0x043A,0x0430,0x043D,0x0438,0x0440,0x043E,0x0432,0x0430,0x043D,0x0438,0x0435) | ForEach-Object { [char]$_ })
        $ruMessage = -join ((0x042D,0x0442,0x043E,0x0020,0x043C,0x043E,0x0436,0x0435,0x0442,0x0020,0x0437,0x0430,0x043D,0x044F,0x0442,0x044C,0x0020,0x043C,0x043D,0x043E,0x0433,0x043E,0x0020,0x0432,0x0440,0x0435,0x043C,0x0435,0x043D,0x0438,0x002E,0x0020,0x041F,0x0440,0x043E,0x0434,0x043E,0x043B,0x0436,0x0438,0x0442,0x044C,0x003F) | ForEach-Object { [char]$_ })
        $ruContinue = -join ((0x041F,0x0440,0x043E,0x0434,0x043E,0x043B,0x0436,0x0438,0x0442,0x044C) | ForEach-Object { [char]$_ })
        $ruCancel = -join ((0x041E,0x0442,0x043C,0x0435,0x043D,0x0430) | ForEach-Object { [char]$_ })

        if (-not ($ru.Library.PSObject.Properties.Name -contains 'ScanWarning')) {
            $ru.Library | Add-Member -NotePropertyName 'ScanWarning' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not ($ru.Library.ScanWarning.PSObject.Properties.Name -contains 'Title')) {
            $ru.Library.ScanWarning | Add-Member -NotePropertyName 'Title' -NotePropertyValue $ruTitle -Force
        }
        if (-not ($ru.Library.ScanWarning.PSObject.Properties.Name -contains 'Message')) {
            $ru.Library.ScanWarning | Add-Member -NotePropertyName 'Message' -NotePropertyValue $ruMessage -Force
        }
        if (-not ($ru.Library.ScanWarning.PSObject.Properties.Name -contains 'Continue')) {
            $ru.Library.ScanWarning | Add-Member -NotePropertyName 'Continue' -NotePropertyValue $ruContinue -Force
        }
        if (-not ($ru.Library.ScanWarning.PSObject.Properties.Name -contains 'Cancel')) {
            $ru.Library.ScanWarning | Add-Member -NotePropertyName 'Cancel' -NotePropertyValue $ruCancel -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log 'lang/ru.json: Library.ScanWarning.*'
    }

    # README
    $readme = @'
# Patch 0.4.5a12 - Smooth rotation + scan warning + theme icon

**Iteration:** 0.4.5

## What it does

1. YawDegrees: { 180, 270, 0, 90 } -> { 180, 220, 260, 300 }.
   Hover rotation in library now spans 120deg instead of 270deg.
   Smoother transitions between the 4 preview angles, still shows different sides.

2. First-scan warning (overlay dialog):
   - Setting "Scan.WarningShown" tracks if user has seen warning.
   - First scan -> ShowScanWarning=true -> overlay with title/message/buttons.
   - Continue -> saves "Scan.WarningShown"="true", runs DoScanAsync.
   - Cancel -> dismisses, no scan.
   - Subsequent scans go directly to DoScanAsync.

3. Theme ComboBox replaced with icon button:
   - Single button in top toolbar.
   - Click cycles: auto -> light -> dark -> auto.
   - Icon (Segoe Fluent Icons): light=Sun E706, dark=Moon E708, auto=Contrast E7F4.
   - Tooltip: current theme name (from existing Settings.Theme.* keys).

4. RendererVersion 0.4.5a12 (angles changed -> regen needed).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- First run after patch: click Scan -> warning overlay appears. Cancel dismisses. Click Scan again -> warning again (until user clicks Continue at least once). After Continue once -> subsequent scans go directly.
- Hover rotation in library: smoother angle steps (40deg apart, not 90deg).
- Top toolbar: no theme ComboBox, icon button with sun/moon/contrast glyph. Click cycles.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a12\README.md'

    # Verify
    $vOpt = [IO.File]::ReadAllText($optionsPath, [Text.Encoding]::UTF8)
    if ($vOpt -match '180f, 220f, 260f, 300f') { Write-Log 'verify OK: 120deg angles' } else { Write-Log 'verify FAIL: angles wrong' 'WARN' }

    $vP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($vP -match '"0\.4\.5a12"') { Write-Log 'verify OK: RendererVersion 0.4.5a12' }

    $vLib = [IO.File]::ReadAllText($libVmPath, [Text.Encoding]::UTF8)
    if ($vLib -match 'ShowScanWarning') { Write-Log 'verify OK: ShowScanWarning in VM' }
    if ($vLib -match 'DoScanAsync') { Write-Log 'verify OK: DoScanAsync method present' }
    if ($vLib -match 'ConfirmScanCommand') { Write-Log 'verify OK: ConfirmScanCommand' }

    $vMain = [IO.File]::ReadAllText($mainVmPath, [Text.Encoding]::UTF8)
    if ($vMain -match 'ThemeIconGlyph') { Write-Log 'verify OK: ThemeIconGlyph' }
    if ($vMain -match 'CycleThemeCommand') { Write-Log 'verify OK: CycleThemeCommand' }

    $vLibX = [IO.File]::ReadAllText($libXamlPath, [Text.Encoding]::UTF8)
    if ($vLibX -match 'ShowScanWarning') { Write-Log 'verify OK: overlay in LibraryView XAML' }

    $vMainX = [IO.File]::ReadAllText($mainXamlPath, [Text.Encoding]::UTF8)
    if ($vMainX -match 'CycleThemeCommand') { Write-Log 'verify OK: theme button in MainWindow XAML' }
    if ($vMainX -notmatch 'ItemsSource="\{Binding Themes\}"') { Write-Log 'verify OK: old theme ComboBox removed' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a12 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a12] - 2026-11-13`r`n`r`n### Changed`r`n- Hover rotation 270deg -> 120deg: YawDegrees {180,220,260,300}. Smoother preview switch.`r`n- Theme ComboBox -> icon button (auto/light/dark cycle, sun/moon/contrast glyphs).`r`n`r`n### Added`r`n- First-scan warning overlay (Settings flag Scan.WarningShown).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a11\].*)$', "$entry`$1"
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