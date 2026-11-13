#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3z3 - Fix missing Card.Scale.* lang keys, About screen, version bump.
.DESCRIPTION
    1. lang/en.json + lang/ru.json: Card.Scale.InvalidManual, Card.Scale.AppliedFormat.
    2. AboutView + AboutViewModel + wiring (ShowAboutCommand, DataTemplate).
    3. MiniCodex.App.csproj: Version 0.1.0 / AssemblyVersion 0.1.0.0 / InformationalVersion 0.1.0-alpha.
    ASCII-only.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3z3'
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

# ============ AboutViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\AboutViewModel.cs'] = @'
using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Windows.Input;

namespace MiniCodex.App.ViewModels;

public class AboutViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string AppName => App.Loc?.Get("App.Name") ?? "MiniCodex";
    public string Tagline => App.Loc?.Get("About.Tagline", "Portable 3D model library");
    public string VersionString
    {
        get
        {
            try
            {
                var asm = Assembly.GetEntryAssembly();
                return asm?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                       ?? "0.1.0-alpha";
            }
            catch { return "0.1.0-alpha"; }
        }
    }

    public string AboutHeader => App.Loc?.Get("About.Title", "About");
    public string AuthorLabel => App.Loc?.Get("About.Author", "Author");
    public string AuthorValue => "Santidio Esanti";
    public string LicenseLabel => App.Loc?.Get("About.License", "Licensed under MIT");
    public string GitHubLabel => App.Loc?.Get("About.GitHub", "GitHub repository");
    public string BoostyLabel => App.Loc?.Get("About.SupportAuthor", "Support the author");
    public string CopyrightLabel => App.Loc?.Get("About.Copyright", "Copyright (c) 2026 Santidio Esanti");

    public ICommand OpenGitHubCommand { get; }
    public ICommand OpenBoostyCommand { get; }

    public AboutViewModel()
    {
        OpenGitHubCommand = new RelayCommand(() => OpenUrl("https://github.com/SantidioEsanti"));
        OpenBoostyCommand = new RelayCommand(() => OpenUrl("https://boosty.to/santidioesanti"));
    }

    public void RefreshLocalized()
    {
        Raise(nameof(AppName));
        Raise(nameof(Tagline));
        Raise(nameof(AboutHeader));
        Raise(nameof(AuthorLabel));
        Raise(nameof(LicenseLabel));
        Raise(nameof(GitHubLabel));
        Raise(nameof(BoostyLabel));
        Raise(nameof(CopyrightLabel));
    }

    private static void OpenUrl(string url)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true,
            });
        }
        catch { }
    }
}
'@

# ============ AboutView.axaml ============
$Files['src\MiniCodex.App\Views\AboutView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.AboutView"
             x:DataType="vm:AboutViewModel">
    <ScrollViewer>
        <StackPanel Margin="32" Spacing="16" MaxWidth="600" HorizontalAlignment="Left">
            <TextBlock Text="{Binding AppName}" FontSize="28" FontWeight="Bold"/>
            <TextBlock Text="{Binding Tagline}" FontSize="14"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <TextBlock Text="{Binding VersionString}" FontSize="12"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>

            <Separator Margin="0,8"/>

            <Grid ColumnDefinitions="Auto,*" RowDefinitions="Auto,Auto" >
                <TextBlock Grid.Row="0" Grid.Column="0" Text="{Binding AuthorLabel}"
                           FontWeight="SemiBold" Margin="0,0,12,8" VerticalAlignment="Center"/>
                <TextBlock Grid.Row="0" Grid.Column="1" Text="{Binding AuthorValue}" VerticalAlignment="Center" Margin="0,0,0,8"/>
                <TextBlock Grid.Row="1" Grid.Column="0" Text="{Binding LicenseLabel}"
                           FontWeight="SemiBold" Margin="0,0,12,0" VerticalAlignment="Center"/>
                <TextBlock Grid.Row="1" Grid.Column="1" Text="MIT" VerticalAlignment="Center"/>
            </Grid>

            <Separator Margin="0,8"/>

            <StackPanel Orientation="Horizontal" Spacing="8">
                <Button Content="{Binding GitHubLabel}" Command="{Binding OpenGitHubCommand}" Padding="14,8"/>
                <Button Content="{Binding BoostyLabel}" Command="{Binding OpenBoostyCommand}" Padding="14,8"
                        Background="#E67E22" Foreground="White"/>
            </StackPanel>

            <TextBlock Text="{Binding CopyrightLabel}" FontSize="11" Margin="0,16,0,0"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
        </StackPanel>
    </ScrollViewer>
</UserControl>
'@

# ============ AboutView.axaml.cs ============
$Files['src\MiniCodex.App\Views\AboutView.axaml.cs'] = @'
using Avalonia.Controls;

namespace MiniCodex.App.Views;

public partial class AboutView : UserControl
{
    public AboutView() => InitializeComponent();
}
'@

# ============ README ============
$Files['patches\0.4.3z3\README.md'] = @'
# Patch 0.4.3z3 - Fix missing lang keys, About screen, version bump

**Iteration:** 0.4

## What it does

1. Fix bug: Card.Scale.InvalidManual and Card.Scale.AppliedFormat were used in code but missing from lang/*.json
   (seen as raw key on Scale tab). Added to both en.json and ru.json.

2. About screen:
   - New AboutViewModel + AboutView.axaml(.cs).
   - App name, tagline, version (from AssemblyInformationalVersion), Author, MIT License.
   - Buttons: GitHub (https://github.com/SantidioEsanti), Support the author (https://boosty.to/santidioesanti).
   - Copyright 2026 Santidio Esanti.

3. Version bump:
   - MiniCodex.App.csproj: Version=0.1.0, AssemblyVersion=0.1.0.0, FileVersion=0.1.0.0, InformationalVersion=0.1.0-alpha.

4. Wiring:
   - MainWindowViewModel: ShowAboutCommand, AboutButtonText.
   - MainWindow.axaml: About button next to Library / Settings.
   - App.axaml: DataTemplate for AboutViewModel.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scale tab: no more raw keys (Invalid scale format / Applied: 1:35).
- About button works, shows version 0.1.0-alpha, GitHub / Boosty buttons open browser.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $mwVmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'
    $mwXamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\MainWindow.axaml'
    $appXamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml'
    $csprojPath = Join-Path $ProjectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
    $enPath = Join-Path $ProjectRoot 'lang\en.json'
    $ruPath = Join-Path $ProjectRoot 'lang\ru.json'

    Backup-File $mwVmPath
    Backup-File $mwXamlPath
    Backup-File $appXamlPath
    Backup-File $csprojPath
    Backup-File $enPath
    Backup-File $ruPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # ============ lang/en.json ============
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Card.Scale)) {
            $en.Card | Add-Member -NotePropertyName 'Scale' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not ($en.Card.Scale.PSObject.Properties.Name -contains 'InvalidManual')) {
            $en.Card.Scale | Add-Member -NotePropertyName 'InvalidManual' -NotePropertyValue 'Invalid scale format' -Force
        }
        if (-not ($en.Card.Scale.PSObject.Properties.Name -contains 'AppliedFormat')) {
            $en.Card.Scale | Add-Member -NotePropertyName 'AppliedFormat' -NotePropertyValue 'Applied: 1:{0}' -Force
        }
        if (-not ($en.About.PSObject.Properties.Name -contains 'Tagline')) {
            $en.About | Add-Member -NotePropertyName 'Tagline' -NotePropertyValue 'Portable 3D model library' -Force
        }
        if (-not ($en.About.PSObject.Properties.Name -contains 'Author')) {
            $en.About | Add-Member -NotePropertyName 'Author' -NotePropertyValue 'Author' -Force
        }
        if (-not ($en.About.PSObject.Properties.Name -contains 'GitHub')) {
            $en.About | Add-Member -NotePropertyName 'GitHub' -NotePropertyValue 'GitHub repository' -Force
        }
        if (-not ($en.About.PSObject.Properties.Name -contains 'SupportAuthor')) {
            $en.About | Add-Member -NotePropertyName 'SupportAuthor' -NotePropertyValue 'Support the author' -Force
        }
        if (-not ($en.About.PSObject.Properties.Name -contains 'Copyright')) {
            $en.About | Add-Member -NotePropertyName 'Copyright' -NotePropertyValue 'Copyright (c) 2026 Santidio Esanti' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: lang\en.json'
    }

    # ============ lang/ru.json (char-codes for Cyrillic) ============
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

        $ruInvalidManual = -join ((0x041D,0x0435,0x0432,0x0435,0x0440,0x043D,0x044B,0x0439,0x0020,0x0444,0x043E,0x0440,0x043C,0x0430,0x0442,0x0020,0x043C,0x0430,0x0441,0x0448,0x0442,0x0430,0x0431,0x0430) | ForEach-Object { [char]$_ })
        $ruAppliedFormat = -join ((0x041F,0x0440,0x0438,0x043C,0x0435,0x043D,0x0435,0x043D,0x043E,0x003A,0x0020,0x0031,0x003A,0x007B,0x0030,0x007D) | ForEach-Object { [char]$_ })
        $ruTagline = -join ((0x041F,0x043E,0x0440,0x0442,0x0430,0x0442,0x0438,0x0432,0x043D,0x0430,0x044F,0x0020,0x0431,0x0438,0x0431,0x043B,0x0438,0x043E,0x0442,0x0435,0x043A,0x0430,0x0020,0x0033,0x0044,0x002D,0x043C,0x043E,0x0434,0x0435,0x043B,0x0435,0x0439) | ForEach-Object { [char]$_ })
        $ruAuthor = -join ((0x0410,0x0432,0x0442,0x043E,0x0440) | ForEach-Object { [char]$_ })
        $ruGitHub = -join ((0x0420,0x0435,0x043F,0x043E,0x0437,0x0438,0x0442,0x043E,0x0440,0x0438,0x0439,0x0020,0x0047,0x0069,0x0074,0x0048,0x0075,0x0062) | ForEach-Object { [char]$_ })
        $ruSupport = -join ((0x041F,0x043E,0x0434,0x0434,0x0435,0x0440,0x0436,0x0430,0x0442,0x044C,0x0020,0x0430,0x0432,0x0442,0x043E,0x0440,0x0430) | ForEach-Object { [char]$_ })
        $ruCopyright = -join ((0x041A,0x043E,0x043F,0x0438,0x0440,0x0430,0x0439,0x0442,0x0020,0x0028,0x0063,0x0029,0x0020,0x0032,0x0030,0x0032,0x0036,0x0020,0x0053,0x0061,0x006E,0x0074,0x0069,0x0064,0x0069,0x006F,0x0020,0x0045,0x0073,0x0061,0x006E,0x0074,0x0069) | ForEach-Object { [char]$_ })

        if (-not ($ru.Card.Scale)) {
            $ru.Card | Add-Member -NotePropertyName 'Scale' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not ($ru.Card.Scale.PSObject.Properties.Name -contains 'InvalidManual')) {
            $ru.Card.Scale | Add-Member -NotePropertyName 'InvalidManual' -NotePropertyValue $ruInvalidManual -Force
        }
        if (-not ($ru.Card.Scale.PSObject.Properties.Name -contains 'AppliedFormat')) {
            $ru.Card.Scale | Add-Member -NotePropertyName 'AppliedFormat' -NotePropertyValue $ruAppliedFormat -Force
        }
        if (-not ($ru.About.PSObject.Properties.Name -contains 'Tagline')) {
            $ru.About | Add-Member -NotePropertyName 'Tagline' -NotePropertyValue $ruTagline -Force
        }
        if (-not ($ru.About.PSObject.Properties.Name -contains 'Author')) {
            $ru.About | Add-Member -NotePropertyName 'Author' -NotePropertyValue $ruAuthor -Force
        }
        if (-not ($ru.About.PSObject.Properties.Name -contains 'GitHub')) {
            $ru.About | Add-Member -NotePropertyName 'GitHub' -NotePropertyValue $ruGitHub -Force
        }
        if (-not ($ru.About.PSObject.Properties.Name -contains 'SupportAuthor')) {
            $ru.About | Add-Member -NotePropertyName 'SupportAuthor' -NotePropertyValue $ruSupport -Force
        }
        if (-not ($ru.About.PSObject.Properties.Name -contains 'Copyright')) {
            $ru.About | Add-Member -NotePropertyName 'Copyright' -NotePropertyValue $ruCopyright -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: lang\ru.json'
    }

    # ============ csproj: version bump ============
    $csproj = [IO.File]::ReadAllText($csprojPath, [Text.Encoding]::UTF8)
    if ($csproj -notmatch '<Version>0\.1\.0</Version>') {
        $anchor = '    <ApplicationIcon>Assets\icon.ico</ApplicationIcon>'
        $versionBlock = $anchor + "`r`n" +
                        '    <Version>0.1.0</Version>' + "`r`n" +
                        '    <AssemblyVersion>0.1.0.0</AssemblyVersion>' + "`r`n" +
                        '    <FileVersion>0.1.0.0</FileVersion>' + "`r`n" +
                        '    <InformationalVersion>0.1.0-alpha</InformationalVersion>'
        if ($csproj.Contains($anchor)) {
            $csproj = $csproj.Replace($anchor, $versionBlock)
            [IO.File]::WriteAllText($csprojPath, $csproj, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: MiniCodex.App.csproj (Version 0.1.0 / InformationalVersion 0.1.0-alpha)'
        } else { Write-Log 'csproj: ApplicationIcon anchor not found' 'WARN' }
    }

    # ============ MainWindowViewModel: About wiring ============
    $mwVm = [IO.File]::ReadAllText($mwVmPath, [Text.Encoding]::UTF8)
    if ($mwVm -notmatch 'ShowAboutCommand') {
        # Add AboutButtonText computed property
        $mwVm = $mwVm.Replace(
            '    public string SettingsButtonText => App.Loc.Get("Menu.Settings");',
            '    public string SettingsButtonText => App.Loc.Get("Menu.Settings");' + "`r`n" +
            '    public string AboutButtonText => App.Loc.Get("Menu.About");'
        )
        # Add ShowAboutCommand declaration
        $mwVm = $mwVm.Replace(
            '    public ICommand ShowSettingsCommand { get; }',
            '    public ICommand ShowSettingsCommand { get; }' + "`r`n" +
            '    public ICommand ShowAboutCommand { get; }'
        )
        # Init ShowAboutCommand
        $mwVm = $mwVm.Replace(
            '        ShowSettingsCommand = new RelayCommand(() =>' + "`r`n" +
            '        {' + "`r`n" +
            '            var vm = new SettingsViewModel();' + "`r`n" +
            '            CurrentPage = vm;' + "`r`n" +
            '            _ = vm.LoadAsync();' + "`r`n" +
            '        });',
            '        ShowSettingsCommand = new RelayCommand(() =>' + "`r`n" +
            '        {' + "`r`n" +
            '            var vm = new SettingsViewModel();' + "`r`n" +
            '            CurrentPage = vm;' + "`r`n" +
            '            _ = vm.LoadAsync();' + "`r`n" +
            '        });' + "`r`n" +
            '        ShowAboutCommand = new RelayCommand(() =>' + "`r`n" +
            '        {' + "`r`n" +
            '            CurrentPage = new AboutViewModel();' + "`r`n" +
            '        });'
        )
        # RefreshLocalized for About
        $mwVm = $mwVm.Replace(
            '(CurrentPage as SettingsViewModel)?.RefreshLocalized();',
            '(CurrentPage as SettingsViewModel)?.RefreshLocalized();' + "`r`n" +
            '            (CurrentPage as AboutViewModel)?.RefreshLocalized();'
        )
        # Raise AboutButtonText on language change
        $mwVm = $mwVm.Replace(
            '            Raise(nameof(SettingsButtonText));',
            '            Raise(nameof(SettingsButtonText));' + "`r`n" +
            '            Raise(nameof(AboutButtonText));'
        )
        [IO.File]::WriteAllText($mwVmPath, $mwVm, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: MainWindowViewModel.cs (ShowAboutCommand, AboutButtonText)'
    }

    # ============ MainWindow.axaml: About button ============
    $mwXaml = [IO.File]::ReadAllText($mwXamlPath, [Text.Encoding]::UTF8)
    if ($mwXaml -notmatch 'ShowAboutCommand') {
        $mwXaml = $mwXaml.Replace(
            '<Button Content="{Binding SettingsButtonText}" Command="{Binding ShowSettingsCommand}"/>',
            '<Button Content="{Binding SettingsButtonText}" Command="{Binding ShowSettingsCommand}"/>' + "`r`n" +
            '            <Button Content="{Binding AboutButtonText}" Command="{Binding ShowAboutCommand}"/>'
        )
        [IO.File]::WriteAllText($mwXamlPath, $mwXaml, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: MainWindow.axaml (About button)'
    }

    # ============ App.axaml: DataTemplate for AboutViewModel ============
    $appXaml = [IO.File]::ReadAllText($appXamlPath, [Text.Encoding]::UTF8)
    if ($appXaml -notmatch 'AboutViewModel') {
        $dtMarker = '        <DataTemplate DataType="vm:SettingsViewModel">' + "`r`n" +
                    '            <views:SettingsView/>' + "`r`n" +
                    '        </DataTemplate>'
        $dtNew = $dtMarker + "`r`n" +
                 '        <DataTemplate DataType="vm:AboutViewModel">' + "`r`n" +
                 '            <views:AboutView/>' + "`r`n" +
                 '        </DataTemplate>'
        if ($appXaml.Contains($dtMarker)) {
            $appXaml = $appXaml.Replace($dtMarker, $dtNew)
            [IO.File]::WriteAllText($appXamlPath, $appXaml, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: App.axaml (DataTemplate for AboutViewModel)'
        } else {
            Write-Log 'App.axaml: SettingsViewModel DataTemplate marker not found' 'WARN'
        }
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.3z3 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3z3] - 2026-11-12`r`n`r`n### Added`r`n- About screen (GitHub + Boosty links, version from AssemblyInformationalVersion).`r`n- Card.Scale.InvalidManual / Card.Scale.AppliedFormat lang keys (fix for raw key shown in Scale tab).`r`n`r`n### Changed`r`n- Version bump: 0.1.0 (InformationalVersion 0.1.0-alpha).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3z2\].*)$', "$entry`$1"
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