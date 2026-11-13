#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.4.0 — Интеграции со слайсерами/редакторами + автодетект.
.DESCRIPTION
    IntegrationCatalog, IIntegrationProbe (WindowsRegistryProbe в App),
    IIntegrationService + IntegrationService, Settings screen, Launch-кнопки в карточке.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.0'
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
    Write-Log "Backup: $rel -> $dst"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

$Files = @{}

# ============ Core/Models/IntegrationApp.cs ============
$Files['src\MiniCodex.Core\Models\IntegrationApp.cs'] = @'
namespace MiniCodex.Core.Models;

public enum IntegrationAppKind { Slicer, Editor }

public class IntegrationApp
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public IntegrationAppKind Kind { get; set; }
    public string? Path { get; set; }
    public bool IsDetected { get; set; }
    public bool IsUserOverride { get; set; }
    public bool IsAvailable => !string.IsNullOrEmpty(Path) && System.IO.File.Exists(Path);
}
'@

# ============ Core/Services/IIntegrationProbe.cs ============
$Files['src\MiniCodex.Core\Services\IIntegrationProbe.cs'] = @'
namespace MiniCodex.Core.Services;

public interface IIntegrationProbe
{
    /// <summary>
    /// Возвращает словарь appId → абсолютный путь к exe.
    /// Отсутствующие приложения просто не попадают в словарь.
    /// </summary>
    Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default);
}
'@

# ============ Core/Services/IIntegrationService.cs ============
$Files['src\MiniCodex.Core\Services\IIntegrationService.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IIntegrationService
{
    Task<IReadOnlyList<IntegrationApp>> GetAppsAsync(CancellationToken ct = default);
    Task SetPathAsync(string appId, string? path, CancellationToken ct = default);
    Task<bool> LaunchAsync(string appId, string modelFilePath, CancellationToken ct = default);
}
'@

# ============ Core/Services/IntegrationCatalog.cs ============
$Files['src\MiniCodex.Core\Services\IntegrationCatalog.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public record IntegrationAppDefinition(
    string Id,
    string DisplayName,
    IntegrationAppKind Kind,
    string[] CommonPaths,
    string ExeName,
    string[] RegistryNameHints);

public static class IntegrationCatalog
{
    public static IReadOnlyList<IntegrationAppDefinition> All { get; } = new[]
    {
        // ---------- Slicers ----------
        new IntegrationAppDefinition(
            "bambustudio", "Bambu Studio", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Bambu Studio\bambu-studio.exe",
                @"C:\Program Files (x86)\Bambu Studio\bambu-studio.exe",
                @"%LOCALAPPDATA%\Programs\Bambu Studio\bambu-studio.exe",
            },
            "bambu-studio.exe",
            new[] { "Bambu Studio" }),

        new IntegrationAppDefinition(
            "prusaslicer", "PrusaSlicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Prusa3D\PrusaSlicer\prusa-slicer.exe",
                @"C:\Program Files\Prusa3D\PrusaSlicer\prusa-slicer-console.exe",
            },
            "prusa-slicer.exe",
            new[] { "PrusaSlicer" }),

        new IntegrationAppDefinition(
            "orcaslicer", "OrcaSlicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\OrcaSlicer\orca-slicer.exe",
                @"%LOCALAPPDATA%\Programs\OrcaSlicer\orca-slicer.exe",
            },
            "orca-slicer.exe",
            new[] { "OrcaSlicer" }),

        new IntegrationAppDefinition(
            "cura", "UltiMaker Cura", IntegrationAppKind.Slicer,
            new[] { @"C:\Program Files\UltiMaker Cura\UltiMaker-Cura.exe" },
            "UltiMaker-Cura.exe",
            new[] { "UltiMaker Cura", "Ultimaker Cura" }),

        new IntegrationAppDefinition(
            "lychee", "Lychee Slicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Lychee Slicer\Lychee Slicer.exe",
                @"%LOCALAPPDATA%\Programs\Lychee Slicer\Lychee Slicer.exe",
            },
            "Lychee Slicer.exe",
            new[] { "Lychee Slicer" }),

        new IntegrationAppDefinition(
            "chitubox", "CHITUBOX", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\CBD-Tech\Chitubox\CHITUBOX.exe",
                @"%LOCALAPPDATA%\Programs\Chitubox\CHITUBOX.exe",
            },
            "CHITUBOX.exe",
            new[] { "CHITUBOX" }),

        // ---------- Editors ----------
        new IntegrationAppDefinition(
            "blender", "Blender", IntegrationAppKind.Editor,
            new[]
            {
                @"C:\Program Files\Blender Foundation\Blender\blender.exe",
            },
            "blender.exe",
            new[] { "Blender" }),

        new IntegrationAppDefinition(
            "zbrush", "ZBrush", IntegrationAppKind.Editor,
            new[]
            {
                @"C:\Program Files\Maxon ZBrush\ZBrush.exe",
                @"C:\Program Files\Pixologic\ZBrush\ZBrush.exe",
            },
            "ZBrush.exe",
            new[] { "ZBrush" }),

        new IntegrationAppDefinition(
            "3dcoat", "3D-Coat", IntegrationAppKind.Editor,
            new[] { @"C:\Program Files\3D-Coat\3D-Coat.exe" },
            "3D-Coat.exe",
            new[] { "3D-Coat" }),

        new IntegrationAppDefinition(
            "meshmixer", "Meshmixer", IntegrationAppKind.Editor,
            new[] { @"C:\Program Files\Autodesk\Meshmixer\meshmixer.exe" },
            "meshmixer.exe",
            new[] { "Meshmixer" }),
    };

    public static IntegrationAppDefinition? Find(string id) => All.FirstOrDefault(a => a.Id == id);

    public static string SettingKey(string appId) => $"Integration.{appId}.Path";
}
'@

# ============ Core/Services/IntegrationService.cs ============
$Files['src\MiniCodex.Core\Services\IntegrationService.cs'] = @'
using System.Diagnostics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class IntegrationService : IIntegrationService
{
    private readonly IIntegrationProbe _probe;
    private readonly ISettingRepository _settings;

    public IntegrationService(IIntegrationProbe probe, ISettingRepository settings)
    {
        _probe = probe;
        _settings = settings;
    }

    public async Task<IReadOnlyList<IntegrationApp>> GetAppsAsync(CancellationToken ct = default)
    {
        var detected = await _probe.ProbeAsync(ct);
        var allSettings = await _settings.GetAllAsync(ct);

        var result = new List<IntegrationApp>();
        foreach (var def in IntegrationCatalog.All)
        {
            var userKey = IntegrationCatalog.SettingKey(def.Id);
            var userPath = allSettings.TryGetValue(userKey, out var raw) ? raw : null;

            if (!string.IsNullOrWhiteSpace(userPath))
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = userPath,
                    IsDetected = false,
                    IsUserOverride = true,
                });
            }
            else if (detected.TryGetValue(def.Id, out var detectedPath))
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = detectedPath,
                    IsDetected = true,
                    IsUserOverride = false,
                });
            }
            else
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = null,
                    IsDetected = false,
                    IsUserOverride = false,
                });
            }
        }
        return result;
    }

    public async Task SetPathAsync(string appId, string? path, CancellationToken ct = default)
    {
        var key = IntegrationCatalog.SettingKey(appId);
        if (string.IsNullOrWhiteSpace(path))
        {
            await _settings.SetAsync(key, string.Empty, ct);
        }
        else
        {
            await _settings.SetAsync(key, path.Trim(), ct);
        }
    }

    public async Task<bool> LaunchAsync(string appId, string modelFilePath, CancellationToken ct = default)
    {
        var apps = await GetAppsAsync(ct);
        var app = apps.FirstOrDefault(a => a.Id == appId);
        if (app == null || string.IsNullOrEmpty(app.Path) || !File.Exists(app.Path)) return false;
        if (string.IsNullOrEmpty(modelFilePath) || !File.Exists(modelFilePath)) return false;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = app.Path,
                Arguments = $"\"{modelFilePath}\"",
                UseShellExecute = false,
            };
            Process.Start(psi);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
'@

# ============ App/MiniCodex.App.csproj (Registry package) ============
$appCsprojContent = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AvaloniaUseCompiledBindingsByDefault>false</AvaloniaUseCompiledBindingsByDefault>
    <ApplicationIcon>Assets\icon.ico</ApplicationIcon>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Avalonia" Version="11.2.3" />
    <PackageReference Include="Avalonia.Desktop" Version="11.2.3" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="11.2.3" />
    <PackageReference Include="Microsoft.Win32.Registry" Version="5.0.0" />
  </ItemGroup>
  <ItemGroup>
    <AvaloniaResource Include="Assets\icon.ico" />
  </ItemGroup>
  <ItemGroup>
    <Content Include="..\..\lang\**\*.json">
      <Link>lang\%(RecursiveDir)%(Filename)%(Extension)</Link>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MiniCodex.Core\MiniCodex.Core.csproj" />
    <ProjectReference Include="..\MiniCodex.Data\MiniCodex.Data.csproj" />
    <ProjectReference Include="..\MiniCodex.Render\MiniCodex.Render.csproj" />
  </ItemGroup>
</Project>
'@

# ============ App/Services/WindowsRegistryProbe.cs ============
$Files['src\MiniCodex.App\Services\WindowsRegistryProbe.cs'] = @'
using Microsoft.Win32;
using MiniCodex.Core.Services;

namespace MiniCodex.App.Services;

public class WindowsRegistryProbe : IIntegrationProbe
{
    private static readonly string[] UninstallRoots =
    {
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    };

    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
    {
        var found = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var def in IntegrationCatalog.All)
        {
            if (ct.IsCancellationRequested) break;

            var path = TryCommonPaths(def) ?? TryRegistry(def);
            if (path != null) found[def.Id] = path;
        }
        return Task.FromResult<IReadOnlyDictionary<string, string>>(found);
    }

    private static string? TryCommonPaths(IntegrationAppDefinition def)
    {
        foreach (var raw in def.CommonPaths)
        {
            var expanded = Environment.ExpandEnvironmentVariables(raw);
            if (File.Exists(expanded)) return expanded;
        }
        return null;
    }

    private static string? TryRegistry(IntegrationAppDefinition def)
    {
        foreach (var hive in new[] { Registry.LocalMachine, Registry.CurrentUser })
        {
            foreach (var rootPath in UninstallRoots)
            {
                try
                {
                    using var root = hive.OpenSubKey(rootPath);
                    if (root == null) continue;
                    foreach (var subKeyName in root.GetSubKeyNames())
                    {
                        using var subKey = root.OpenSubKey(subKeyName);
                        if (subKey == null) continue;
                        var displayName = subKey.GetValue("DisplayName") as string;
                        if (string.IsNullOrEmpty(displayName)) continue;
                        if (!def.RegistryNameHints.Any(h => displayName.Contains(h, StringComparison.OrdinalIgnoreCase)))
                            continue;

                        var installLoc = subKey.GetValue("InstallLocation") as string;
                        if (!string.IsNullOrEmpty(installLoc))
                        {
                            var candidate = Path.Combine(installLoc, def.ExeName);
                            if (File.Exists(candidate)) return candidate;
                        }

                        // Fallback: DisplayIcon
                        var icon = subKey.GetValue("DisplayIcon") as string;
                        if (!string.IsNullOrEmpty(icon))
                        {
                            var cleaned = icon.Split(',')[0].Trim().Trim('"');
                            if (cleaned.EndsWith(def.ExeName, StringComparison.OrdinalIgnoreCase) && File.Exists(cleaned))
                                return cleaned;
                        }
                    }
                }
                catch { /* access denied — пропускаем */ }
            }
        }
        return null;
    }
}
'@

# ============ App/AppServices.cs ============
$Files['src\MiniCodex.App\AppServices.cs'] = @'
using MiniCodex.App.Services;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App;

public static class AppServices
{
    public static SqliteConnectionFactory? Factory { get; private set; }
    public static IModelRepository? Models { get; private set; }
    public static IModelFileRepository? ModelFiles { get; private set; }
    public static IAssetRepository? Assets { get; private set; }
    public static ISettingRepository? Settings { get; private set; }
    public static IModelTagRepository? ModelTags { get; private set; }
    public static ScannerService? Scanner { get; private set; }
    public static PreviewGenerator? PreviewGenerator { get; private set; }
    public static IAssetService? AssetService { get; private set; }
    public static ITagService? TagService { get; private set; }
    public static IIntegrationService? IntegrationService { get; private set; }
    public static AppPaths? Paths { get; private set; }

    public static void Init(AppPaths paths)
    {
        Paths = paths;
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);
        Settings = new SettingRepository(Factory);
        ModelTags = new ModelTagRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);

        var thumbs = new SkiaThumbnailGenerator();
        var thumbsRoot = Path.Combine(paths.DataDir, "cache", "asset-thumbs");
        AssetService = new AssetService(Assets, ModelFiles, thumbs, paths.AssetsDir, thumbsRoot);

        TagService = new TagService(new TagRepository(Factory), ModelTags);

        var probe = new WindowsRegistryProbe();
        IntegrationService = new IntegrationService(probe, Settings);
    }
}
'@

# ============ App/ViewModels/IntegrationAppRowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\IntegrationAppRowViewModel.cs'] = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class IntegrationAppRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public IntegrationApp App { get; }

    public string DisplayName => App.DisplayName;
    public string CurrentPath => App.Path ?? string.Empty;

    public string StatusText
    {
        get
        {
            if (App.IsUserOverride) return App.Loc?.Get("Settings.Integrations.StatusManual") ?? "Manual";
            if (App.IsDetected) return App.Loc?.Get("Settings.Integrations.StatusAuto") ?? "Auto";
            return App.Loc?.Get("Settings.Integrations.StatusMissing") ?? "Not found";
        }
    }

    public string BrowseText => App.Loc?.Get("Settings.Integrations.Browse") ?? "Browse…";
    public string ClearText => App.Loc?.Get("Settings.Integrations.Clear") ?? "Clear";

    public ICommand BrowseCommand { get; }
    public ICommand ClearCommand { get; }

    public IntegrationAppRowViewModel(
        IntegrationApp app,
        Func<IntegrationAppRowViewModel, Task> onBrowse,
        Func<IntegrationAppRowViewModel, Task> onClear)
    {
        App = app;
        BrowseCommand = new RelayCommand(async () => await onBrowse(this));
        ClearCommand = new RelayCommand(async () => await onClear(this));
    }

    public void RefreshLocalized()
    {
        Raise(nameof(StatusText));
        Raise(nameof(BrowseText));
        Raise(nameof(ClearText));
    }
}
'@

# ============ App/ViewModels/SettingsViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\SettingsViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ObservableCollection<IntegrationAppRowViewModel> SlicerRows { get; } = new();
    public ObservableCollection<IntegrationAppRowViewModel> EditorRows { get; } = new();

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); }
    }

    public string HeaderText => App.Loc?.Get("Settings.Title") ?? "Settings";
    public string IntegrationsHeader => App.Loc?.Get("Settings.Integrations.SectionHeader") ?? "Integrations";
    public string HintText => App.Loc?.Get("Settings.Integrations.Hint") ?? "Auto-detect or set paths manually";
    public string DetectButtonText => App.Loc?.Get("Settings.Integrations.Detect") ?? "Re-detect";
    public string SlicersHeader => App.Loc?.Get("Settings.Integrations.KindSlicer") ?? "Slicers";
    public string EditorsHeader => App.Loc?.Get("Settings.Integrations.KindEditor") ?? "Editors";
    public string ColumnNameText => App.Loc?.Get("Settings.Integrations.ColumnName") ?? "Application";
    public string ColumnPathText => App.Loc?.Get("Settings.Integrations.ColumnPath") ?? "Path";
    public string ColumnStatusText => App.Loc?.Get("Settings.Integrations.ColumnStatus") ?? "Status";

    public ICommand DetectCommand { get; }

    public SettingsViewModel()
    {
        DetectCommand = new RelayCommand(async () => await ReloadAsync());
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        await ReloadAsync(ct);
    }

    private async Task ReloadAsync(CancellationToken ct = default)
    {
        if (AppServices.IntegrationService == null) return;
        IsBusy = true;
        try
        {
            var apps = await AppServices.IntegrationService.GetAppsAsync(ct);
            SlicerRows.Clear();
            EditorRows.Clear();
            foreach (var app in apps)
            {
                var row = new IntegrationAppRowViewModel(app, OnBrowseAsync, OnClearAsync);
                if (app.Kind == IntegrationAppKind.Slicer) SlicerRows.Add(row);
                else EditorRows.Add(row);
            }
        }
        finally { IsBusy = false; }
    }

    private async Task OnBrowseAsync(IntegrationAppRowViewModel row)
    {
        // Диалог выбора файла — вызывается из View через событие;
        // ViewModel делегирует View через событие BrowseRequested.
        var handler = BrowseRequested;
        if (handler == null) return;
        var path = await handler(row);
        if (string.IsNullOrEmpty(path) || AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.SetPathAsync(row.App.Id, path);
        await ReloadAsync();
    }

    private async Task OnClearAsync(IntegrationAppRowViewModel row)
    {
        if (AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.SetPathAsync(row.App.Id, null);
        await ReloadAsync();
    }

    public delegate Task<string?> BrowseHandler(IntegrationAppRowViewModel row);
    public event BrowseHandler? BrowseRequested;

    public void RefreshLocalized()
    {
        Raise(nameof(HeaderText));
        Raise(nameof(IntegrationsHeader));
        Raise(nameof(HintText));
        Raise(nameof(DetectButtonText));
        Raise(nameof(SlicersHeader));
        Raise(nameof(EditorsHeader));
        Raise(nameof(ColumnNameText));
        Raise(nameof(ColumnPathText));
        Raise(nameof(ColumnStatusText));
        foreach (var r in SlicerRows) r.RefreshLocalized();
        foreach (var r in EditorRows) r.RefreshLocalized();
    }
}
'@

# ============ App/Views/SettingsView.axaml ============
$Files['src\MiniCodex.App\Views\SettingsView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.SettingsView"
             x:DataType="vm:SettingsViewModel">
    <ScrollViewer>
        <StackPanel Margin="12">
            <TextBlock Text="{Binding HeaderText}" FontSize="20" FontWeight="Bold" Margin="0,0,0,12"/>

            <TextBlock Text="{Binding IntegrationsHeader}" FontWeight="Bold" Margin="0,8,0,4"/>
            <StackPanel Orientation="Horizontal" Spacing="8" Margin="0,0,0,8">
                <TextBlock Text="{Binding HintText}" VerticalAlignment="Center"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                <Button Content="{Binding DetectButtonText}" Command="{Binding DetectCommand}"/>
            </StackPanel>

            <TextBlock Text="{Binding SlicersHeader}" FontWeight="SemiBold" Margin="0,8,0,4"/>
            <Grid ColumnDefinitions="200,*,100,90,70" Margin="4,0,4,2">
                <TextBlock Grid.Column="0" Text="{Binding ColumnNameText}" FontSize="11" Foreground="#888"/>
                <TextBlock Grid.Column="1" Text="{Binding ColumnPathText}" FontSize="11" Foreground="#888"/>
                <TextBlock Grid.Column="2" Text="{Binding ColumnStatusText}" FontSize="11" Foreground="#888"/>
            </Grid>
            <ItemsControl ItemsSource="{Binding SlicerRows}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Grid ColumnDefinitions="200,*,100,90,70" Margin="4,2">
                            <TextBlock Grid.Column="0" Text="{Binding DisplayName}" VerticalAlignment="Center"/>
                            <TextBox Grid.Column="1" Text="{Binding CurrentPath}" IsReadOnly="True" Watermark="—" Margin="4,0"/>
                            <TextBlock Grid.Column="2" Text="{Binding StatusText}" VerticalAlignment="Center" FontSize="11"/>
                            <Button Grid.Column="3" Content="{Binding BrowseText}" Command="{Binding BrowseCommand}" Padding="6,0" Margin="2,0"/>
                            <Button Grid.Column="4" Content="{Binding ClearText}" Command="{Binding ClearCommand}" Padding="6,0" Margin="2,0"/>
                        </Grid>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>

            <TextBlock Text="{Binding EditorsHeader}" FontWeight="SemiBold" Margin="0,16,0,4"/>
            <ItemsControl ItemsSource="{Binding EditorRows}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Grid ColumnDefinitions="200,*,100,90,70" Margin="4,2">
                            <TextBlock Grid.Column="0" Text="{Binding DisplayName}" VerticalAlignment="Center"/>
                            <TextBox Grid.Column="1" Text="{Binding CurrentPath}" IsReadOnly="True" Watermark="—" Margin="4,0"/>
                            <TextBlock Grid.Column="2" Text="{Binding StatusText}" VerticalAlignment="Center" FontSize="11"/>
                            <Button Grid.Column="3" Content="{Binding BrowseText}" Command="{Binding BrowseCommand}" Padding="6,0" Margin="2,0"/>
                            <Button Grid.Column="4" Content="{Binding ClearText}" Command="{Binding ClearCommand}" Padding="6,0" Margin="2,0"/>
                        </Grid>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </StackPanel>
    </ScrollViewer>
</UserControl>
'@

# ============ App/Views/SettingsView.axaml.cs ============
$Files['src\MiniCodex.App\Views\SettingsView.axaml.cs'] = @'
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    protected override async void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is SettingsViewModel vm)
        {
            vm.BrowseRequested += OnBrowseRequested;
            await vm.LoadAsync();
        }
    }

    protected override void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is SettingsViewModel vm)
            vm.BrowseRequested -= OnBrowseRequested;
        base.OnDetachedFromVisualTree(e);
    }

    private async Task<string?> OnBrowseRequested(IntegrationAppRowViewModel row)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return null;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select executable",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Executable") { Patterns = new[] { "*.exe" } },
            }
        });
        if (files.Count == 0) return null;
        return files[0].TryGetLocalPath();
    }
}
'@

# ============ App/ViewModels/ModelCardPageViewModel.cs (дополнение launch) ============
$Files['src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public enum ThreeDViewState { Loading, Loaded, FileNotChosen, ParseFailed, Error }
public enum SaveState { None, Saved, Error }

public class ModelCardPageViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;
    private readonly Action _onBack;

    public Model Model { get; }

    private string _title = string.Empty;
    public string Title { get => _title; set { _title = value; Raise(); } }
    private string _author = string.Empty;
    public string Author { get => _author; set { _author = value; Raise(); } }
    private string _sourceUrl = string.Empty;
    public string SourceUrl { get => _sourceUrl; set { _sourceUrl = value; Raise(); } }
    private string _status = string.Empty;
    public string Status { get => _status; set { _status = value; Raise(); } }
    private string _difficulty = string.Empty;
    public string Difficulty { get => _difficulty; set { _difficulty = value; Raise(); } }
    private string _notes = string.Empty;
    public string Notes { get => _notes; set { _notes = value; Raise(); } }

    public ObservableCollection<ModelFileRowViewModel> FileRows { get; } = new();

    private string? _meshFilePath;
    public string? MeshFilePath { get => _meshFilePath; set { _meshFilePath = value; Raise(); Raise(nameof(CanLaunch)); } }

    private int _selectedTabIndex;
    public int SelectedTabIndex { get => _selectedTabIndex; set { _selectedTabIndex = value; Raise(); } }

    private float _minLambert = 0.4f;
    public float MinLambertValue
    {
        get => _minLambert;
        set
        {
            if (Math.Abs(_minLambert - value) < 0.001f) return;
            _minLambert = value;
            Raise();
            _ = SaveSettingAsync("Render.MinLambert", value.ToString("F2", CultureInfo.InvariantCulture));
        }
    }

    private bool _wireframeMode;
    public bool WireframeMode
    {
        get => _wireframeMode;
        set { if (_wireframeMode != value) { _wireframeMode = value; Raise(); } }
    }

    private ThreeDViewState _threeDViewState = ThreeDViewState.FileNotChosen;
    public ThreeDViewState ThreeDViewState
    {
        get => _threeDViewState;
        set { _threeDViewState = value; Raise(); Raise(nameof(ThreeDStatusText)); Raise(nameof(ThreeDStatusVisible)); }
    }

    private string? _threeDErrorMessage;
    public string? ThreeDErrorMessage
    {
        get => _threeDErrorMessage;
        set { _threeDErrorMessage = value; Raise(); Raise(nameof(ThreeDStatusText)); }
    }

    public string ThreeDStatusText => ThreeDViewState switch
    {
        ThreeDViewState.Loading => Loc("Card.ThreeD.Loading", "Loading 3D…"),
        ThreeDViewState.FileNotChosen => Loc("Card.ThreeD.FileNotChosen", "No model file selected"),
        ThreeDViewState.ParseFailed => Loc("Card.ThreeD.ParseFailed", "Failed to parse model"),
        ThreeDViewState.Error => Loc("Card.ThreeD.ErrorPrefix", "Error: ") + (ThreeDErrorMessage ?? ""),
        _ => string.Empty,
    };
    public bool ThreeDStatusVisible => ThreeDViewState != ThreeDViewState.Loaded;

    private SaveState _saveState = SaveState.None;
    public SaveState SaveState
    {
        get => _saveState;
        private set { _saveState = value; Raise(); Raise(nameof(SaveStatusText)); }
    }

    private string? _saveErrorMessage;
    public string? SaveErrorMessage
    {
        get => _saveErrorMessage;
        private set { _saveErrorMessage = value; Raise(); Raise(nameof(SaveStatusText)); }
    }

    public string SaveStatusText => SaveState switch
    {
        SaveState.Saved => Loc("Card.Status.Saved", "Saved"),
        SaveState.Error => Loc("Card.Status.ErrorPrefix", "Error: ") + (SaveErrorMessage ?? ""),
        _ => string.Empty,
    };

    public string BackButtonText => Loc("Card.Actions.Back", "← Back");
    public string SaveButtonText => Loc("Card.Actions.Save", "Save");
    public string TabInfoHeader => Loc("Card.Tabs.Info", "Info");
    public string TabFilesHeader => Loc("Card.Tabs.Files", "Files");
    public string TabAssociationsHeader => Loc("Card.Tabs.Associations", "Associations");
    public string TabTagsHeader => Loc("Card.Tabs.Tags", "Tags");
    public string TabNotesHeader => Loc("Card.Tabs.Notes", "Notes");
    public string LabelTitle => Loc("Card.Fields.Title", "Title");
    public string LabelAuthor => Loc("Card.Fields.Author", "Author");
    public string LabelSourceUrl => Loc("Card.Fields.SourceUrl", "Source URL");
    public string LabelStatus => Loc("Card.Fields.Status", "Status");
    public string LabelDifficulty => Loc("Card.Fields.Difficulty", "Difficulty");
    public string LabelMinLambert => Loc("Card.View.MinLambert", "Shadow softness");
    public string LabelWireframe => Loc("Card.View.Wireframe", "Wireframe");

    public string AddFileButtonText => Loc("Card.Assoc.AddFile", "Add file");
    public string AutoLinkButtonText => Loc("Card.Assoc.AutoLink", "Auto-link");
    public string DropHintText => Loc("Card.Assoc.DropHint", "Drop files here to attach");
    public string RemoveAssetText => Loc("Card.Assoc.Remove", "Remove");
    public string AssetStatusText { get; private set; } = string.Empty;

    public string TagPlaceholderText => Loc("Card.Tags.Placeholder", "Enter tag…");
    public string AddTagButtonText => Loc("Card.Tags.Add", "Add");
    public string EmptyTagsText => Loc("Card.Tags.Empty", "No tags yet");

    public string SlicerLabel => Loc("Card.Launch.SlicerLabel", "Slicer:");
    public string EditorLabel => Loc("Card.Launch.EditorLabel", "Editor:");
    public string OpenInSlicerText => Loc("Card.Launch.OpenInSlicer", "Open in slicer");
    public string OpenInEditorText => Loc("Card.Launch.OpenInEditor", "Open in editor");
    public string NoSlicerText => Loc("Card.Launch.NoSlicer", "No slicers configured (Settings)");
    public string NoEditorText => Loc("Card.Launch.NoEditor", "No editors configured (Settings)");

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

    public ObservableCollection<TagRowViewModel> TagRows { get; } = new();
    private string _newTagName = string.Empty;
    public string NewTagName { get => _newTagName; set { _newTagName = value; Raise(); } }

    // ---------- Integration launch ----------
    public ObservableCollection<IntegrationApp> AvailableSlicers { get; } = new();
    public ObservableCollection<IntegrationApp> AvailableEditors { get; } = new();

    private IntegrationApp? _selectedSlicer;
    public IntegrationApp? SelectedSlicer { get => _selectedSlicer; set { _selectedSlicer = value; Raise(); Raise(nameof(CanLaunchSlicer)); } }

    private IntegrationApp? _selectedEditor;
    public IntegrationApp? SelectedEditor { get => _selectedEditor; set { _selectedEditor = value; Raise(); Raise(nameof(CanLaunchEditor)); } }

    public bool HasSlicers => AvailableSlicers.Count > 0;
    public bool HasEditors => AvailableEditors.Count > 0;
    public bool HasAnyIntegration => HasSlicers || HasEditors;
    public bool CanLaunchSlicer => SelectedSlicer != null && !string.IsNullOrEmpty(MeshFilePath);
    public bool CanLaunchEditor => SelectedEditor != null && !string.IsNullOrEmpty(MeshFilePath);
    public bool CanLaunch => !string.IsNullOrEmpty(MeshFilePath);

    public ICommand SaveCommand { get; }
    public ICommand GoBackCommand { get; }
    public ICommand SetPrimaryCommand { get; }
    public ICommand AutoLinkCommand { get; }
    public ICommand AddTagCommand { get; }
    public ICommand LaunchInSlicerCommand { get; }
    public ICommand LaunchInEditorCommand { get; }

    public ModelCardPageViewModel(
        Model model,
        IModelRepository models,
        IModelFileRepository files,
        Action onBack)
    {
        Model = model;
        _models = models;
        _files = files;
        _onBack = onBack;

        _title = model.Title;
        _author = model.Author ?? string.Empty;
        _sourceUrl = model.SourceUrl ?? string.Empty;
        _status = model.Status ?? string.Empty;
        _difficulty = model.Difficulty?.ToString() ?? string.Empty;
        _notes = model.Notes ?? string.Empty;

        SaveCommand = new RelayCommand(async () => await SaveAsync());
        GoBackCommand = new RelayCommand(() => _onBack());
        SetPrimaryCommand = new RelayCommand(async p => await SetPrimaryAsync(p as ModelFileRowViewModel));
        AutoLinkCommand = new RelayCommand(async () => await AutoLinkAsync());
        AddTagCommand = new RelayCommand(async () => await AddTagAsync());
        LaunchInSlicerCommand = new RelayCommand(async () => await LaunchAsync(SelectedSlicer));
        LaunchInEditorCommand = new RelayCommand(async () => await LaunchAsync(SelectedEditor));
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        var files = await _files.GetByModelAsync(Model.Id, ct);
        FileRows.Clear();
        foreach (var f in files)
            FileRows.Add(new ModelFileRowViewModel(f, f.Id == Model.PrimaryModelFileId));

        var primary = files.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId) ?? files.FirstOrDefault();
        MeshFilePath = primary?.Path;

        if (AppServices.Settings != null)
        {
            var raw = await AppServices.Settings.GetAsync("Render.MinLambert", ct);
            if (raw != null && float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var f))
            {
                _minLambert = Math.Clamp(f, 0f, 1f);
                Raise(nameof(MinLambertValue));
            }
        }

        await ReloadAssetsAsync(ct);
        await ReloadTagsAsync(ct);
        await ReloadIntegrationsAsync(ct);
    }

    private async Task ReloadIntegrationsAsync(CancellationToken ct)
    {
        if (AppServices.IntegrationService == null) return;
        try
        {
            var apps = await AppServices.IntegrationService.GetAppsAsync(ct);
            AvailableSlicers.Clear();
            AvailableEditors.Clear();
            foreach (var a in apps)
            {
                if (!a.IsAvailable) continue;
                if (a.Kind == IntegrationAppKind.Slicer) AvailableSlicers.Add(a);
                else AvailableEditors.Add(a);
            }
            SelectedSlicer = AvailableSlicers.FirstOrDefault();
            SelectedEditor = AvailableEditors.FirstOrDefault();
            Raise(nameof(HasSlicers));
            Raise(nameof(HasEditors));
            Raise(nameof(HasAnyIntegration));
            Raise(nameof(CanLaunchSlicer));
            Raise(nameof(CanLaunchEditor));
        }
        catch { }
    }

    private async Task LaunchAsync(IntegrationApp? app)
    {
        if (app == null || string.IsNullOrEmpty(MeshFilePath)) return;
        if (AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.LaunchAsync(app.Id, MeshFilePath);
    }

    private async Task ReloadAssetsAsync(CancellationToken ct)
    {
        if (AppServices.Assets == null || AppServices.AssetService == null) return;
        var assets = await AppServices.Assets.GetByModelAsync(Model.Id, ct);
        AssetRows.Clear();
        foreach (var a in assets)
        {
            var row = new AssetRowViewModel(a, OnRemoveAssetAsync);
            AssetRows.Add(row);
            _ = LoadThumbnailAsync(row, ct);
        }
        RebuildFilteredAssets();
    }

    private async Task LoadThumbnailAsync(AssetRowViewModel row, CancellationToken ct)
    {
        if (AppServices.AssetService == null) return;
        try
        {
            var path = await AppServices.AssetService.EnsureThumbnailAsync(row.Asset, ct);
            if (path == null) return;
            await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
            {
                try { using var stream = File.OpenRead(path); row.SetThumbnail(new Bitmap(stream)); }
                catch { }
            });
        }
        catch { }
    }

    private void RebuildFilteredAssets()
    {
        FilteredAssets.Clear();
        foreach (var r in AssetRows)
            if (_selectedAssetFilter == "all" || r.Asset.AssetType == _selectedAssetFilter)
                FilteredAssets.Add(r);
    }

    private void SetAssetStatus(string text) { AssetStatusText = text; Raise(nameof(AssetStatusText)); }

    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths)
    {
        if (AppServices.AssetService == null) return;
        var count = 0;
        foreach (var p in sourcePaths)
        {
            try { await AppServices.AssetService.ImportAsync(Model.Id, p, SelectedAssetType); count++; }
            catch { }
        }
        SetAssetStatus(string.Format(Loc("Card.Assoc.Imported", "Imported: {0}"), count));
        await ReloadAssetsAsync(CancellationToken.None);
    }

    private async Task AutoLinkAsync()
    {
        if (AppServices.AssetService == null) return;
        SetAssetStatus(Loc("Card.Assoc.AutoLinkRunning", "Searching…"));
        try
        {
            var found = await AppServices.AssetService.AutoLinkAsync(Model.Id);
            SetAssetStatus(string.Format(Loc("Card.Assoc.AutoLinkResult", "Linked: {0}"), found.Count));
            await ReloadAssetsAsync(CancellationToken.None);
        }
        catch (Exception ex) { SetAssetStatus("Error: " + ex.Message); }
    }

    private async Task OnRemoveAssetAsync(AssetRowViewModel row)
    {
        if (AppServices.AssetService == null) return;
        await AppServices.AssetService.RemoveFromCardAsync(row.Asset.Id);
        AssetRows.Remove(row);
        RebuildFilteredAssets();
    }

    private async Task ReloadTagsAsync(CancellationToken ct)
    {
        if (AppServices.TagService == null) return;
        try
        {
            TagRows.Clear();
            var tags = await AppServices.TagService.GetTagsForModelAsync(Model.Id, ct);
            foreach (var t in tags) TagRows.Add(new TagRowViewModel(t, OnRemoveTagAsync));
        }
        catch { }
    }

    private async Task AddTagAsync()
    {
        if (AppServices.TagService == null) return;
        if (string.IsNullOrWhiteSpace(NewTagName)) return;
        try
        {
            await AppServices.TagService.AddToModelAsync(Model.Id, NewTagName.Trim());
            NewTagName = string.Empty;
            await ReloadTagsAsync(CancellationToken.None);
        }
        catch { }
    }

    private async Task OnRemoveTagAsync(TagRowViewModel row)
    {
        if (AppServices.TagService == null) return;
        try { await AppServices.TagService.RemoveFromModelAsync(Model.Id, row.Tag.Id); TagRows.Remove(row); }
        catch { }
    }

    public void RefreshLocalized()
    {
        Raise(nameof(BackButtonText));
        Raise(nameof(SaveButtonText));
        Raise(nameof(TabInfoHeader));
        Raise(nameof(TabFilesHeader));
        Raise(nameof(TabAssociationsHeader));
        Raise(nameof(TabTagsHeader));
        Raise(nameof(TabNotesHeader));
        Raise(nameof(LabelTitle));
        Raise(nameof(LabelAuthor));
        Raise(nameof(LabelSourceUrl));
        Raise(nameof(LabelStatus));
        Raise(nameof(LabelDifficulty));
        Raise(nameof(LabelMinLambert));
        Raise(nameof(LabelWireframe));
        Raise(nameof(AddFileButtonText));
        Raise(nameof(AutoLinkButtonText));
        Raise(nameof(DropHintText));
        Raise(nameof(RemoveAssetText));
        Raise(nameof(TagPlaceholderText));
        Raise(nameof(AddTagButtonText));
        Raise(nameof(EmptyTagsText));
        Raise(nameof(SlicerLabel));
        Raise(nameof(EditorLabel));
        Raise(nameof(OpenInSlicerText));
        Raise(nameof(OpenInEditorText));
        Raise(nameof(NoSlicerText));
        Raise(nameof(NoEditorText));
        Raise(nameof(ThreeDStatusText));
        Raise(nameof(SaveStatusText));
    }

    private async Task SaveAsync()
    {
        try
        {
            Model.Title = string.IsNullOrWhiteSpace(Title) ? "Untitled" : Title;
            Model.Author = NullIfEmpty(Author);
            Model.SourceUrl = NullIfEmpty(SourceUrl);
            Model.Status = NullIfEmpty(Status);
            Model.Difficulty = int.TryParse(Difficulty, out var d) ? Math.Clamp(d, 1, 5) : null;
            Model.Notes = NullIfEmpty(Notes);
            await _models.UpsertAsync(Model);
            SaveErrorMessage = null;
            SaveState = SaveState.Saved;
        }
        catch (Exception ex) { SaveErrorMessage = ex.Message; SaveState = SaveState.Error; }
    }

    private async Task SetPrimaryAsync(ModelFileRowViewModel? row)
    {
        if (row == null) return;
        foreach (var r in FileRows) r.IsPrimary = ReferenceEquals(r, row);
        Model.PrimaryModelFileId = row.File.Id;
        await _models.UpsertAsync(Model);
        MeshFilePath = row.File.Path;
    }

    private static async Task SaveSettingAsync(string key, string value)
    {
        if (AppServices.Settings == null) return;
        try { await AppServices.Settings.SetAsync(key, value); } catch { }
    }

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;
    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;
}
'@

# ============ App/ViewModels/MainWindowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class MainWindowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ObservableCollection<string> Languages { get; } = new() { "en", "ru" };
    public ObservableCollection<string> Themes { get; } = new() { "light", "dark", "auto" };

    private string _lang = App.Loc?.Current ?? "en";
    public string CurrentLanguage
    {
        get => _lang;
        set
        {
            if (!Set(ref _lang, value)) return;
            App.Loc.SetLanguage(value);
            Raise(nameof(Title));
            Raise(nameof(LibraryButtonText));
            Raise(nameof(SettingsButtonText));
            Library.RefreshLocalized();
            (CurrentPage as ModelCardPageViewModel)?.RefreshLocalized();
            (CurrentPage as SettingsViewModel)?.RefreshLocalized();
        }
    }

    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set { if (Set(ref _theme, value)) App.Theme.Apply(value); }
    }

    public string Title => App.Loc.Get("App.Name");
    public string LibraryButtonText => App.Loc.Get("Menu.Library");
    public string SettingsButtonText => App.Loc.Get("Menu.Settings");

    public LibraryViewModel Library { get; }

    private object? _currentPage;
    public object? CurrentPage
    {
        get => _currentPage;
        private set { _currentPage = value; Raise(); }
    }

    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ShowLibraryCommand { get; }
    public ICommand ShowSettingsCommand { get; }

    public MainWindowViewModel()
    {
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService);
        Library.OpenCardRequested += OnOpenCard;
        CurrentPage = Library;

        RequestFocusSearchCommand = new RelayCommand(() =>
        {
            if (CurrentPage is LibraryViewModel lib) lib.RequestFocusSearch();
        });
        ShowLibraryCommand = new RelayCommand(() => CurrentPage = Library);
        ShowSettingsCommand = new RelayCommand(() =>
        {
            var vm = new SettingsViewModel();
            CurrentPage = vm;
            _ = vm.LoadAsync();
        });
    }

    private void OnOpenCard(object? sender, Model model)
    {
        if (AppServices.Models == null || AppServices.ModelFiles == null) return;
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
            onBack: () => CurrentPage = Library);
        CurrentPage = page;
        _ = page.LoadAsync();
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}
'@

# ============ App/Views/MainWindow.axaml ============
$Files['src\MiniCodex.App\Views\MainWindow.axaml'] = @'
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
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120" Margin="16,0,0,0"/>
            <ComboBox ItemsSource="{Binding Themes}" SelectedItem="{Binding CurrentTheme}" Width="120"/>
        </StackPanel>
        <ContentControl Grid.Row="1" Content="{Binding CurrentPage}"/>
    </Grid>
</Window>
'@

# ============ App/Views/ModelCardView.axaml (добавлен launch-ряд) ============
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
            <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
            <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="120" VerticalAlignment="Center"/>
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

        <Grid Grid.Row="2" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0"
                                MeshFilePath="{Binding MeshFilePath}"
                                MinLambert="{Binding MinLambertValue}"
                                Wireframe="{Binding WireframeMode}"
                                Margin="0,0,8,0"/>

            <TabControl Grid.Column="1" SelectedIndex="{Binding SelectedTabIndex}">
                <TabItem Header="{Binding TabInfoHeader}">
                    <ScrollViewer>
                        <StackPanel Margin="8" Spacing="6">
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
                                BorderThickness="1" BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
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
                                                    <Button Grid.Column="1" Content="×" Command="{Binding RemoveCommand}"
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
                                                <Button Content="×" Command="{Binding RemoveCommand}"
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

                <TabItem Header="{Binding TabNotesHeader}">
                    <TextBox Text="{Binding Notes}" AcceptsReturn="True"
                             TextWrapping="Wrap" VerticalContentAlignment="Top"
                             Margin="8" MinHeight="200"/>
                </TabItem>
            </TabControl>
        </Grid>
    </Grid>
</UserControl>
'@

# ============ App/App.axaml (DataTemplate для SettingsViewModel) ============
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
    <Application.Styles>
        <FluentTheme />
    </Application.Styles>
</Application>
'@

# ============ Tests/Services/IntegrationServiceTests.cs ============
$Files['src\MiniCodex.Tests\Services\IntegrationServiceTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class FakeProbe : IIntegrationProbe
{
    private readonly Dictionary<string, string> _paths;
    public FakeProbe(Dictionary<string, string>? paths = null) => _paths = paths ?? new();
    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
        => Task.FromResult<IReadOnlyDictionary<string, string>>(_paths);
}

public class IntegrationServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly SqliteConnectionFactory _factory;

    public IntegrationServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
    }

    public void Dispose() { try { File.Delete(_dbPath); } catch { } }

    [Fact]
    public async Task GetApps_EmptyProbe_AllMissing()
    {
        var svc = new IntegrationService(new FakeProbe(), new SettingRepository(_factory));
        var apps = await svc.GetAppsAsync();
        Assert.Equal(IntegrationCatalog.All.Count, apps.Count);
        Assert.All(apps, a => Assert.Null(a.Path));
        Assert.All(apps, a => Assert.False(a.IsDetected));
    }

    [Fact]
    public async Task GetApps_WithProbe_DetectedAppsHavePath()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\fake\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"C:\fake\bambu.exe", bambu.Path);
        Assert.True(bambu.IsDetected);
        Assert.False(bambu.IsUserOverride);
    }

    [Fact]
    public async Task SetPath_Override_Wins()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\detected\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));

        await svc.SetPathAsync("bambustudio", @"D:\custom\bambu-custom.exe");
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"D:\custom\bambu-custom.exe", bambu.Path);
        Assert.True(bambu.IsUserOverride);
        Assert.False(bambu.IsDetected);
    }

    [Fact]
    public async Task ClearOverride_RevertsToDetected()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\detected\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));

        await svc.SetPathAsync("bambustudio", @"D:\custom\bambu-custom.exe");
        await svc.SetPathAsync("bambustudio", null);
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"C:\detected\bambu.exe", bambu.Path);
        Assert.True(bambu.IsDetected);
        Assert.False(bambu.IsUserOverride);
    }
}
'@

# ============ lang/en.json ============
$Files['lang\en.json'] = @'
{
  "App": { "Name": "MiniCodex", "Version": "0.0.0", "Tagline": "Portable 3D model library" },
  "Menu": { "Library": "Library", "Settings": "Settings", "About": "About" },
  "Common": { "Ok": "OK", "Cancel": "Cancel", "Save": "Save", "Delete": "Delete", "Close": "Close", "Browse": "Browse…", "Loading": "Loading…", "Error": "Error", "Warning": "Warning" },
  "Settings": {
    "Title": "Settings",
    "Section": { "Sources": "Source folders", "AssetsRoot": "Associations root", "Integrations": "Slicers & editors", "Appearance": "Appearance", "Database": "Database" },
    "Theme": { "Label": "Theme", "Light": "Light", "Dark": "Dark", "Auto": "Auto" },
    "Language": { "Label": "Language", "Ru": "Русский", "En": "English" },
    "LowDiskSpace": "Less than 500 MB free on the data drive.",
    "Integrations": {
      "SectionHeader": "Integrations",
      "Hint": "Auto-detect or set paths manually.",
      "Detect": "Re-detect",
      "KindSlicer": "Slicers",
      "KindEditor": "3D Editors",
      "ColumnName": "Application",
      "ColumnPath": "Path",
      "ColumnStatus": "Status",
      "StatusAuto": "Auto",
      "StatusManual": "Manual",
      "StatusMissing": "Not found",
      "Browse": "Browse…",
      "Clear": "Clear"
    }
  },
  "Library": {
    "Title": "Library",
    "SearchPlaceholder": "Search by name, tag, author…",
    "Empty": "No models yet. Click “Scan folder”.",
    "ScanButton": "Scan folder",
    "ScanFolderTitle": "Select source folder",
    "Loading": "Loading library…",
    "ModelsCount": "Models: {0}",
    "Scanning": "Scanning…",
    "ScanningProgress": "Scanning: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Services not initialized.",
    "TagsHeader": "Tags",
    "AllModels": "All models",
    "Hover": { "TotalSize": "Total size", "Polygons": "Polygons", "Files": "Files", "Status": "Status" },
    "Status": { "Planned": "Planned", "Printed": "Printed", "Painted": "Painted" },
    "QuickActions": { "ToSlicer": "To slicer", "ToEditor": "To editor", "ShowInFolder": "Show in folder" },
    "ContextMenu": { "CopyPath": "Copy path", "RemoveFromLibrary": "Remove from library", "AddTag": "Add tag", "OpenCard": "Open card" }
  },
  "Card": {
    "Tabs": { "Info": "Info", "Files": "Files", "Associations": "Associations", "Tags": "Tags", "Notes": "Notes", "Scale": "Scale" },
    "Actions": { "Back": "← Back", "Save": "Save", "Orient": "Orient", "RegeneratePreviews": "Regenerate previews", "OpenInSlicer": "Open in slicer", "OpenInEditor": "Open in editor", "ShowInFolder": "Show in folder" },
    "Fields": { "Title": "Title", "Author": "Author", "SourceUrl": "Source URL", "Status": "Status", "Difficulty": "Paint difficulty", "Notes": "Notes", "RealHeightMm": "Prototype real height (mm)", "ModelHeightMm": "Model height (mm)", "Scale": "Target scale", "PrototypeType": "Prototype type" },
    "FileRole": { "Main": "Main", "Part": "Part", "Presupported": "Pre-supported", "Hollowed": "Hollowed", "Variant": "Variant", "Accessory": "Accessory" },
    "AssetType": { "Reference": "Reference", "Render": "Render", "Photo": "Photo", "Document": "Document", "Profile": "Print profile" },
    "Status": { "Saved": "Saved", "ErrorPrefix": "Error: " },
    "Placeholder": { "AssociationsSoon": "Associations — coming in 0.3.1", "TagsSoon": "Tags — coming in 0.3.2" },
    "ThreeD": { "Loading": "Loading 3D…", "FileNotChosen": "No model file selected", "ParseFailed": "Failed to parse model", "ErrorPrefix": "Error: " },
    "View": { "MinLambert": "Shadow softness", "Wireframe": "Wireframe" },
    "Assoc": { "AddFile": "Add file", "AutoLink": "Auto-link", "AutoLinkRunning": "Searching…", "AutoLinkResult": "Linked: {0}", "Imported": "Imported: {0}", "DropHint": "Drop files here to attach", "Remove": "Remove" },
    "Tags": { "Placeholder": "Enter tag…", "Add": "Add", "Empty": "No tags yet" },
    "Launch": { "SlicerLabel": "Slicer:", "EditorLabel": "Editor:", "OpenInSlicer": "Open in slicer", "OpenInEditor": "Open in editor", "NoSlicer": "No slicers configured (Settings)", "NoEditor": "No editors configured (Settings)" },
    "RemoveFromCard": "Remove from card"
  },
  "About": { "Title": "About", "License": "Licensed under MIT.", "Support": "Support the author" },
  "Error": { "ParseFailed": "Failed to parse mesh file", "FolderUnavailable": "Source folder is unavailable" }
}
'@

# ============ lang/ru.json ============
$Files['lang\ru.json'] = @'
{
  "App": { "Name": "MiniCodex", "Version": "0.0.0", "Tagline": "Portable-библиотека 3D-моделей" },
  "Menu": { "Library": "Библиотека", "Settings": "Настройки", "About": "О программе" },
  "Common": { "Ok": "ОК", "Cancel": "Отмена", "Save": "Сохранить", "Delete": "Удалить", "Close": "Закрыть", "Browse": "Обзор…", "Loading": "Загрузка…", "Error": "Ошибка", "Warning": "Предупреждение" },
  "Settings": {
    "Title": "Настройки",
    "Section": { "Sources": "Папки-источники", "AssetsRoot": "Корень ассоциаций", "Integrations": "Слайсеры и редакторы", "Appearance": "Внешний вид", "Database": "База данных" },
    "Theme": { "Label": "Тема", "Light": "Светлая", "Dark": "Тёмная", "Auto": "Авто" },
    "Language": { "Label": "Язык", "Ru": "Русский", "En": "English" },
    "LowDiskSpace": "Свободно менее 500 МБ на диске с данными.",
    "Integrations": {
      "SectionHeader": "Интеграции",
      "Hint": "Автодетект или ручные пути.",
      "Detect": "Обнаружить",
      "KindSlicer": "Слайсеры",
      "KindEditor": "3D-редакторы",
      "ColumnName": "Приложение",
      "ColumnPath": "Путь",
      "ColumnStatus": "Статус",
      "StatusAuto": "Авто",
      "StatusManual": "Вручную",
      "StatusMissing": "Не найден",
      "Browse": "Обзор…",
      "Clear": "Очистить"
    }
  },
  "Library": {
    "Title": "Библиотека",
    "SearchPlaceholder": "Поиск по имени, тегу, автору…",
    "Empty": "Пока нет моделей. Нажмите «Сканировать папку».",
    "ScanButton": "Сканировать папку",
    "ScanFolderTitle": "Выберите папку-источник",
    "Loading": "Загрузка библиотеки…",
    "ModelsCount": "Моделей: {0}",
    "Scanning": "Сканирование…",
    "ScanningProgress": "Сканирование: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Сервисы не инициализированы.",
    "TagsHeader": "Теги",
    "AllModels": "Все модели",
    "Hover": { "TotalSize": "Общий размер", "Polygons": "Полигоны", "Files": "Файлы", "Status": "Статус" },
    "Status": { "Planned": "В планах", "Printed": "Напечатано", "Painted": "Покрашено" },
    "QuickActions": { "ToSlicer": "В слайсер", "ToEditor": "В редактор", "ShowInFolder": "В папке" },
    "ContextMenu": { "CopyPath": "Копировать путь", "RemoveFromLibrary": "Удалить из библиотеки", "AddTag": "Добавить тег", "OpenCard": "Открыть карточку" }
  },
  "Card": {
    "Tabs": { "Info": "Инфо", "Files": "Файлы", "Associations": "Ассоциации", "Tags": "Теги", "Notes": "Заметки", "Scale": "Масштаб" },
    "Actions": { "Back": "← Назад", "Save": "Сохранить", "Orient": "Ориентировать", "RegeneratePreviews": "Перегенерировать превью", "OpenInSlicer": "Открыть в слайсере", "OpenInEditor": "Открыть в редакторе", "ShowInFolder": "Показать в папке" },
    "Fields": { "Title": "Название", "Author": "Автор", "SourceUrl": "Источник (URL)", "Status": "Статус", "Difficulty": "Сложность покраса", "Notes": "Заметки", "RealHeightMm": "Реальная высота прототипа (мм)", "ModelHeightMm": "Высота модели (мм)", "Scale": "Целевой масштаб", "PrototypeType": "Тип прототипа" },
    "FileRole": { "Main": "Основной", "Part": "Часть", "Presupported": "Pre-supported", "Hollowed": "Полый", "Variant": "Вариант", "Accessory": "Аксессуар" },
    "AssetType": { "Reference": "Референс", "Render": "Рендер", "Photo": "Фото готовой работы", "Document": "Документ", "Profile": "Профиль печати" },
    "Status": { "Saved": "Сохранено", "ErrorPrefix": "Ошибка: " },
    "Placeholder": { "AssociationsSoon": "Ассоциации — в патче 0.3.1", "TagsSoon": "Теги — в патче 0.3.2" },
    "ThreeD": { "Loading": "Загрузка 3D…", "FileNotChosen": "Файл модели не выбран", "ParseFailed": "Не удалось разобрать модель", "ErrorPrefix": "Ошибка: " },
    "View": { "MinLambert": "Мягкость теней", "Wireframe": "Каркас" },
    "Assoc": { "AddFile": "Добавить файл", "AutoLink": "Авто-привязка", "AutoLinkRunning": "Поиск…", "AutoLinkResult": "Привязано: {0}", "Imported": "Импортировано: {0}", "DropHint": "Перетащите файлы сюда", "Remove": "Убрать" },
    "Tags": { "Placeholder": "Введите тег…", "Add": "Добавить", "Empty": "Тегов пока нет" },
    "Launch": { "SlicerLabel": "Слайсер:", "EditorLabel": "Редактор:", "OpenInSlicer": "Открыть в слайсере", "OpenInEditor": "Открыть в редакторе", "NoSlicer": "Слайсеры не настроены (Настройки)", "NoEditor": "Редакторы не настроены (Настройки)" },
    "RemoveFromCard": "Убрать из карточки"
  },
  "About": { "Title": "О программе", "License": "Лицензия MIT.", "Support": "Поддержать автора" },
  "Error": { "ParseFailed": "Не удалось разобрать файл модели", "FolderUnavailable": "Папка-источник недоступна" }
}
'@

# ============ README ============
$Files['patches\0.4.0\README.md'] = @'
# Патч 0.4.0 — Интеграции со слайсерами/редакторами + автодетект

**Итерация:** 0.4 · **Статус:** реализован

## Что делает

- `IntegrationCatalog` (Core) — 10 приложений: 6 слайсеров + 4 редактора.
- `IIntegrationProbe` (Core) + `WindowsRegistryProbe` (App) — стандартные пути + Uninstall-ключи.
- `IIntegrationService` + `IntegrationService` (Core) — Get/Set/Launch, override в `Setting`.
- Экран «Настройки» (`SettingsViewModel` + `SettingsView`): списки слайсеров/редакторов, статусы (Auto/Manual/Not found), Browse/Clear, Re-detect.
- Навигация `Library | Settings` в верхней панели.
- Карточка модели: второй ряд с dropdown + кнопки Open in slicer/editor. Скрыт, если интеграций нет.
- Локализация: полная перезапись `lang/en.json` + `lang/ru.json` (200+ строк, с новыми ключами Settings.Integrations.* и Card.Launch.*).
- `Microsoft.Win32.Registry 5.0.0` в App.csproj.
- 4 новых теста (fake probe).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.4.0\patch_0.4.0.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 40/40 (36 + 4 новых).
- Settings: секция «Интеграции», список 10 приложений. Если Bambu установлен — статус Auto, путь заполнен. «Re-detect» перепроверяет.
- Browse: file picker → override, статус Manual.
- Clear: override снят → снова Auto (если установлен).
- Карточка: второй ряд с dropdown выбранного слайсера/редактора, кнопки запускают процесс с primary-файлом.
- Смена языка → все строки переключаются.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $appCsprojPath = Join-Path $ProjectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'

    $toBackup = @(
        'src\MiniCodex.App\AppServices.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\Views\MainWindow.axaml',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
        'src\MiniCodex.App\App.axaml',
        'lang\en.json',
        'lang\ru.json',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }
    Backup-File $appCsprojPath

    # Перезаписываем App.csproj с Microsoft.Win32.Registry
    Write-Text -Path $appCsprojPath -Content $appCsprojContent
    Write-Log 'updated: src\MiniCodex.App\MiniCodex.App.csproj (Microsoft.Win32.Registry)'

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.0 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.4.0] - 2026-11-10`n`n### Added`n- IntegrationCatalog (10 приложений: 6 слайсеров + 4 редактора).`n- IIntegrationProbe + WindowsRegistryProbe (стандартные пути + Uninstall).`n- IIntegrationService: Get/Set/Launch.`n- Экран «Настройки»: секция «Интеграции» с Browse/Clear/Re-detect.`n- Карточка: dropdown + кнопки запуска слайсера/редактора.`n- 4 юнит-теста интеграций.`n`n### Changed`n- lang/*.json — полная перезапись с новыми ключами.`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.2\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.4.0.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}