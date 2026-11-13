#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.1.0 — инициализация репозитория и скелет решения MiniCodex.
.DESCRIPTION
    Регламент: бэкап -> изменения -> лог -> CHANGELOG. Идемпотентен.
    Создаёт sln + 4 csproj, наполняет src/MiniCodex.App скелетом,
    обновляет CHANGELOG.
.NOTES
    Запуск:
    powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.0\patch_0.1.0.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.1.0'
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
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# --- Карта: относительный путь -> содержимое --------------------------------

$Files = @{}

$Files['patches\0.1.0\README.md'] = @'
# Патч 0.1.0 — Инициализация репозитория и скелет решения

**Итерация:** 0.1 (Фундамент)
**Статус:** реализован
**Задачи:** см. `docs/ROADMAP.md`, раздел 2.1.

## Что делает

- Создаёт `src/MiniCodex.sln` и четыре `.csproj` (Core, Data, Render, Tests).
- Обновляет `src/MiniCodex.App/MiniCodex.App.csproj`: Avalonia 11, копирование `lang/*.json` в выход.
- Наполняет `src/MiniCodex.App` скелетом: `Program.cs`, `App.axaml`, `MainWindow.axaml`, ViewModel, сервисы (`AppPaths`, `LocalizationService`, `ThemeService`).
- При старте приложения создаются portable-каталоги `data/`, `data/cache/previews/`, `data/assets/`.
- Обновляет `CHANGELOG.md`.

## Затрагиваемые файлы

- `src/MiniCodex.sln` — новый.
- `src/MiniCodex.Core/MiniCodex.Core.csproj` — новый.
- `src/MiniCodex.Data/MiniCodex.Data.csproj` — новый.
- `src/MiniCodex.Render/MiniCodex.Render.csproj` — новый.
- `src/MiniCodex.Tests/MiniCodex.Tests.csproj` — новый.
- `src/MiniCodex.App/MiniCodex.App.csproj` — заменён.
- `src/MiniCodex.App/Program.cs`, `App.axaml`, `App.axaml.cs` — новые.
- `src/MiniCodex.App/Views/MainWindow.axaml`, `MainWindow.axaml.cs` — новые.
- `src/MiniCodex.App/ViewModels/MainWindowViewModel.cs` — новый.
- `src/MiniCodex.App/Services/AppPaths.cs`, `LocalizationService.cs`, `ThemeService.cs` — новые.
- `CHANGELOG.md` — обновлён.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.0\patch_0.1.0.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- Приложение запускается, переключает тему (light/dark/auto) и язык (RU/EN).
- При первом запуске создаются `data/library.db` (пустой файл), `data/cache/previews/`, `data/assets/`.

## Откат

Скопировать файлы из `backups\0.1.0_{timestamp}\` обратно в `D:\AI\MiniCodex\`.
'@

$Files['src\MiniCodex.sln'] = @'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MiniCodex.App", "MiniCodex.App\MiniCodex.App.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MiniCodex.Core", "MiniCodex.Core\MiniCodex.Core.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MiniCodex.Data", "MiniCodex.Data\MiniCodex.Data.csproj", "{33333333-3333-3333-3333-333333333333}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MiniCodex.Render", "MiniCodex.Render\MiniCodex.Render.csproj", "{44444444-4444-4444-4444-444444444444}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "MiniCodex.Tests", "MiniCodex.Tests\MiniCodex.Tests.csproj", "{55555555-5555-5555-5555-555555555555}"
EndProject
Global
    GlobalSection(SolutionConfigurationPlatforms) = preSolution
        Debug|Any CPU = Debug|Any CPU
        Release|Any CPU = Release|Any CPU
    EndGlobalSection
    GlobalSection(ProjectConfigurationPlatforms) = postSolution
        {11111111-1111-1111-1111-111111111111}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
        {11111111-1111-1111-1111-111111111111}.Debug|Any CPU.Build.0 = Debug|Any CPU
        {11111111-1111-1111-1111-111111111111}.Release|Any CPU.ActiveCfg = Release|Any CPU
        {11111111-1111-1111-1111-111111111111}.Release|Any CPU.Build.0 = Release|Any CPU
        {22222222-2222-2222-2222-222222222222}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
        {22222222-2222-2222-2222-222222222222}.Debug|Any CPU.Build.0 = Debug|Any CPU
        {22222222-2222-2222-2222-222222222222}.Release|Any CPU.ActiveCfg = Release|Any CPU
        {22222222-2222-2222-2222-222222222222}.Release|Any CPU.Build.0 = Release|Any CPU
        {33333333-3333-3333-3333-333333333333}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
        {33333333-3333-3333-3333-333333333333}.Debug|Any CPU.Build.0 = Debug|Any CPU
        {33333333-3333-3333-3333-333333333333}.Release|Any CPU.ActiveCfg = Release|Any CPU
        {33333333-3333-3333-3333-333333333333}.Release|Any CPU.Build.0 = Release|Any CPU
        {44444444-4444-4444-4444-444444444444}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
        {44444444-4444-4444-4444-444444444444}.Debug|Any CPU.Build.0 = Debug|Any CPU
        {44444444-4444-4444-4444-444444444444}.Release|Any CPU.ActiveCfg = Release|Any CPU
        {44444444-4444-4444-4444-444444444444}.Release|Any CPU.Build.0 = Release|Any CPU
        {55555555-5555-5555-5555-555555555555}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
        {55555555-5555-5555-5555-555555555555}.Debug|Any CPU.Build.0 = Debug|Any CPU
        {55555555-5555-5555-5555-555555555555}.Release|Any CPU.ActiveCfg = Release|Any CPU
        {55555555-5555-5555-5555-555555555555}.Release|Any CPU.Build.0 = Release|Any CPU
    EndGlobalSection
EndGlobal
'@

$Files['src\MiniCodex.Core\MiniCodex.Core.csproj'] = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
'@

$Files['src\MiniCodex.Data\MiniCodex.Data.csproj'] = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Data.Sqlite" Version="8.0.10" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MiniCodex.Core\MiniCodex.Core.csproj" />
  </ItemGroup>
</Project>
'@

$Files['src\MiniCodex.Render\MiniCodex.Render.csproj'] = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\MiniCodex.Core\MiniCodex.Core.csproj" />
  </ItemGroup>
</Project>
'@

$Files['src\MiniCodex.Tests\MiniCodex.Tests.csproj'] = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MiniCodex.Core\MiniCodex.Core.csproj" />
    <ProjectReference Include="..\MiniCodex.Data\MiniCodex.Data.csproj" />
    <ProjectReference Include="..\MiniCodex.Render\MiniCodex.Render.csproj" />
  </ItemGroup>
</Project>
'@

$Files['src\MiniCodex.App\MiniCodex.App.csproj'] = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AvaloniaUseCompiledBindingsByDefault>false</AvaloniaUseCompiledBindingsByDefault>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Avalonia" Version="11.2.3" />
    <PackageReference Include="Avalonia.Desktop" Version="11.2.3" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="11.2.3" />
  </ItemGroup>
  <ItemGroup>
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
            .LogToTrace();
}
'@

$Files['src\MiniCodex.App\App.axaml'] = @'
<Application xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.App"
             RequestedThemeVariant="Default">
    <Application.Styles>
        <FluentTheme />
    </Application.Styles>
</Application>
'@

$Files['src\MiniCodex.App\App.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using MiniCodex.App.Services;
using MiniCodex.App.Views;

namespace MiniCodex.App;

public partial class App : Application
{
    public static AppPaths Paths { get; private set; } = null!;
    public static LocalizationService Loc { get; private set; } = null!;
    public static ThemeService Theme { get; private set; } = null!;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Paths = new AppPaths();
            Paths.EnsureCreated();

            Loc = new LocalizationService(Paths, "en");
            Loc.LoadInitial();

            Theme = new ThemeService(this);

            desktop.MainWindow = new MainWindow();
        }
        base.OnFrameworkInitializationCompleted();
    }
}
'@

$Files['src\MiniCodex.App\Views\MainWindow.axaml'] = @'
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="MiniCodex.App.Views.MainWindow"
        Title="{Binding Title}"
        Width="900" Height="600">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120"/>
            <ComboBox ItemsSource="{Binding Themes}" SelectedItem="{Binding CurrentTheme}" Width="120"/>
        </StackPanel>
        <TextBlock Grid.Row="1" Margin="8" Text="{Binding Greeting}" FontSize="18"/>
    </Grid>
</Window>
'@

$Files['src\MiniCodex.App\Views\MainWindow.axaml.cs'] = @'
using Avalonia.Controls;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }
}
'@

$Files['src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

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
            Raise(nameof(Greeting));
        }
    }

    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set
        {
            if (!Set(ref _theme, value)) return;
            App.Theme.Apply(value);
        }
    }

    public string Title => App.Loc.Get("App.Name");
    public string Greeting => App.Loc.Get("App.Tagline");

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}
'@

$Files['src\MiniCodex.App\Services\AppPaths.cs'] = @'
using System;
using System.IO;

namespace MiniCodex.App.Services;

public class AppPaths
{
    public string Root { get; }
    public string DataDir => Path.Combine(Root, "data");
    public string LibraryDb => Path.Combine(DataDir, "library.db");
    public string CacheDir => Path.Combine(DataDir, "cache", "previews");
    public string AssetsDir => Path.Combine(DataDir, "assets");
    public string LangDir { get; }

    public AppPaths()
    {
        Root = AppContext.BaseDirectory;

        var candidate = Path.Combine(Root, "lang");
        if (!Directory.Exists(candidate))
        {
            var repoLang = Path.Combine(Root, "..", "..", "..", "..", "..", "lang");
            repoLang = Path.GetFullPath(repoLang);
            if (Directory.Exists(repoLang)) candidate = repoLang;
        }
        LangDir = candidate;
    }

    public void EnsureCreated()
    {
        Directory.CreateDirectory(DataDir);
        Directory.CreateDirectory(CacheDir);
        Directory.CreateDirectory(AssetsDir);
        if (!File.Exists(LibraryDb)) File.WriteAllBytes(LibraryDb, Array.Empty<byte>());
    }
}
'@

$Files['src\MiniCodex.App\Services\LocalizationService.cs'] = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace MiniCodex.App.Services;

public class LocalizationService
{
    private readonly AppPaths _paths;
    private Dictionary<string, string> _dict = new(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, string> _fallback = new(StringComparer.OrdinalIgnoreCase);

    public string Current { get; private set; } = "en";

    public LocalizationService(AppPaths paths, string current)
    {
        _paths = paths;
        Current = current;
    }

    public void LoadInitial()
    {
        var sys = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        var lang = File.Exists(Path.Combine(_paths.LangDir, sys + ".json")) ? sys : "en";
        SetLanguage(lang);
    }

    public void SetLanguage(string lang)
    {
        Current = lang;
        _fallback = Load("en");
        _dict = lang == "en" ? _fallback : Load(lang);
    }

    public string Get(string key)
    {
        if (_dict.TryGetValue(key, out var v)) return v;
        if (_fallback.TryGetValue(key, out var f)) return f;
        return key;
    }

    private Dictionary<string, string> Load(string lang)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(_paths.LangDir, lang + ".json");
        if (!File.Exists(path)) return result;
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        Flatten(doc.RootElement, "", result);
        return result;
    }

    private static void Flatten(JsonElement el, string prefix, Dictionary<string, string> target)
    {
        foreach (var prop in el.EnumerateObject())
        {
            var key = string.IsNullOrEmpty(prefix) ? prop.Name : prefix + "." + prop.Name;
            if (prop.Value.ValueKind == JsonValueKind.Object)
                Flatten(prop.Value, key, target);
            else if (prop.Value.ValueKind == JsonValueKind.String)
                target[key] = prop.Value.GetString() ?? "";
        }
    }
}
'@

$Files['src\MiniCodex.App\Services\ThemeService.cs'] = @'
using Avalonia;
using Avalonia.Styling;

namespace MiniCodex.App.Services;

public class ThemeService
{
    private readonly Application _app;

    public ThemeService(Application app) => _app = app;

    public void Apply(string theme)
    {
        _app.RequestedThemeVariant = theme?.ToLowerInvariant() switch
        {
            "light" => ThemeVariant.Light,
            "dark" => ThemeVariant.Dark,
            _ => ThemeVariant.Default,
        };
    }
}
'@

# --- Основной сценарий -------------------------------------------------------

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $backupTargets = @(
        'src\MiniCodex.App\MiniCodex.App.csproj',
        'CHANGELOG.md'
    )
    foreach ($rel in $backupTargets) {
        $full = Join-Path $ProjectRoot $rel
        if (Test-Path -LiteralPath $full) { Backup-File $full }
    }

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        $action = if ($existed) { 'updated' } else { 'created' }
        Write-Log ('{0}: {1}' -f $action, $rel)
    }

    $marker = '<!-- patch 0.1.0 applied -->'
    $changelogPath = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path -LiteralPath $changelogPath) {
        $cl = Get-Content -Raw -LiteralPath $changelogPath
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Реализовано в 0.1.0 (патч 0.1.0)`n`n- Скелет решения .NET 8 + Avalonia (sln + 5 проектов).`n- Локализация RU/EN с автовыбором и fallback EN.`n- Темы light/dark/auto.`n- Portable-каталоги data/, data/cache/previews/, data/assets/ (создаются при старте).`n"
            $cl = [regex]::Replace($cl, '(?m)^(## \[0\.1\.0\].*)$', ('$1' + $entry))
            [System.IO.File]::WriteAllText($changelogPath, $cl, [System.Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись о реализации 0.1.0.'
        } else {
            Write-Log 'CHANGELOG.md: запись о 0.1.0 уже присутствует, пропускаю.'
        }
    }

    Write-Log "Патч $Version завершён."
    Write-Log 'Следующий шаг: dotnet build src/MiniCodex.sln'
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    Write-Log "Восстановление: скопируйте файлы из '$BackupDir' обратно в '$ProjectRoot'." 'ERROR'
    exit 1
}