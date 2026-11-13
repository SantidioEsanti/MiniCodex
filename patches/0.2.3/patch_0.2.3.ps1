#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.3 — Экран «Библиотека»: сетка карточек с превью.
.DESCRIPTION
    Добавляет UI библиотеки, сканирование по кнопке, фоновую генерацию превью
    на карточках. Без Hover и виртуализации (0.2.3a).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.3'
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
    public static ScannerService? Scanner { get; private set; }
    public static PreviewGenerator? PreviewGenerator { get; private set; }

    public static void Init(AppPaths paths)
    {
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);
    }
}
'@

# ============ App/ViewModels/ModelCardViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelCardViewModel.cs'] = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class ModelCardViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public Model Model { get; }
    public string Title => Model.Title;
    public string StatusText => Model.Status ?? "-";
    public string PolygonsText => "-"; // заполним после загрузки файлов
    public string FileSizeText => "-";

    private Bitmap? _preview;
    public Bitmap? PreviewImage
    {
        get => _preview;
        private set { _preview = value; Raise(); }
    }

    public ModelCardViewModel(Model model) => Model = model;

    public async Task LoadDetailsAsync(
        IModelFileRepository files,
        PreviewGenerator previews,
        CancellationToken ct = default)
    {
        try
        {
            var allFiles = await files.GetByModelAsync(Model.Id, ct);
            if (allFiles.Count > 0)
            {
                var totalSize = allFiles.Sum(f => f.FileSizeBytes ?? 0);
                var totalPoly = allFiles.Sum(f => (long)(f.PolygonCount ?? 0));
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    Raise(nameof(FileSizeText));
                    Raise(nameof(PolygonsText));
                });
            }

            if (Model.PrimaryModelFileId == null) return;
            var primary = allFiles.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId);
            if (primary == null) return;

            var results = await previews.EnsurePreviewsAsync(
                Model.Id, primary.Path, Model.UpdatedAt, ct);
            var firstPath = results.FirstOrDefault(p => p != null);
            if (firstPath == null) return;

            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                try
                {
                    using var stream = File.OpenRead(firstPath);
                    PreviewImage = new Bitmap(stream);
                }
                catch { /* ignore — превью просто не покажется */ }
            });
        }
        catch { /* fire-and-forget, не роняем UI */ }
    }
}
'@

# ============ App/ViewModels/LibraryViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\LibraryViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class LibraryViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository? _models;
    private readonly IModelFileRepository? _files;
    private readonly ScannerService? _scanner;
    private readonly PreviewGenerator? _previews;

    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); Raise(nameof(IsEmpty)); }
    }

    private string _statusText = string.Empty;
    public string StatusText
    {
        get => _statusText;
        private set { _statusText = value; Raise(); }
    }

    public bool IsEmpty => !IsBusy && Cards.Count == 0;

    public LibraryViewModel(
        IModelRepository? models,
        IModelFileRepository? files,
        ScannerService? scanner,
        PreviewGenerator? previews)
    {
        _models = models;
        _files = files;
        _scanner = scanner;
        _previews = previews;
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        if (_models == null || _files == null || _previews == null)
        {
            StatusText = "Сервисы не инициализированы.";
            return;
        }
        IsBusy = true;
        try
        {
            StatusText = "Загрузка библиотеки…";
            var all = await _models.GetAllAsync(ct);
            Cards.Clear();
            foreach (var m in all)
            {
                var card = new ModelCardViewModel(m);
                Cards.Add(card);
                _ = Task.Run(() => card.LoadDetailsAsync(_files, _previews, ct), ct);
            }
            StatusText = Cards.Count == 0 ? string.Empty : $"Моделей: {Cards.Count}";
            Raise(nameof(IsEmpty));
        }
        finally { IsBusy = false; }
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        if (_scanner == null || _models == null || _files == null || _previews == null)
            return;
        IsBusy = true;
        StatusText = "Сканирование…";
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                StatusText = $"Сканирование: {p.ProcessedFiles}/{p.TotalFiles} (+{p.Added}, ~{p.Updated}, ={p.Skipped})";
            });
            await _scanner.ScanAsync(folders, progress, ct);
        }
        finally
        {
            await LoadAsync(ct);
        }
    }
}
'@

# ============ App/Views/LibraryView.axaml ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.LibraryView">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="8" Spacing="8">
            <Button Content="Сканировать папку" Click="OnScanClick"/>
            <TextBlock Text="{Binding StatusText}" VerticalAlignment="Center" Foreground="#666"/>
            <ProgressBar IsIndeterminate="True" IsVisible="{Binding IsBusy}" Width="120" VerticalAlignment="Center"/>
        </StackPanel>

        <ScrollViewer Grid.Row="1">
            <ItemsControl ItemsSource="{Binding Cards}" Margin="4">
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel Orientation="Horizontal"/>
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Border Width="220" Height="260" Margin="6" BorderBrush="#DDD" BorderThickness="1"
                                CornerRadius="6" Padding="6" Background="#FFF">
                            <Grid RowDefinitions="180,*,Auto">
                                <Border Background="#F5F5F5" CornerRadius="4">
                                    <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
                                </Border>
                                <TextBlock Grid.Row="1" Text="{Binding Title}"
                                           FontWeight="Bold" TextTrimming="CharacterEllipsis"
                                           Margin="0,6,0,0"/>
                                <TextBlock Grid.Row="2" FontSize="11" Foreground="#666"
                                           Text="{Binding StatusText}"/>
                            </Grid>
                        </Border>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>

        <TextBlock Grid.Row="1"
                   Text="Пока нет моделей. Нажмите «Сканировать папку»."
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="#888" IsVisible="{Binding IsEmpty}"/>
    </Grid>
</UserControl>
'@

# ============ App/Views/LibraryView.axaml.cs ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml.cs'] = @'
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class LibraryView : UserControl
{
    public LibraryView()
    {
        InitializeComponent();
    }

    protected override async void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        if (DataContext is LibraryViewModel vm)
            await vm.LoadAsync();
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel?.StorageProvider is null) return;

        var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Выберите папку-источник",
            AllowMultiple = true,
        });
        if (folders.Count == 0) return;

        var paths = folders
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        if (DataContext is LibraryViewModel vm)
            await vm.ScanAsync(paths);
    }
}
'@

# ============ App/ViewModels/MainWindowViewModel.cs (обновление) ============
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

    public LibraryViewModel Library { get; }

    public MainWindowViewModel()
    {
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator);
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

# ============ App/Views/MainWindow.axaml (обновление) ============
$Files['src\MiniCodex.App\Views\MainWindow.axaml'] = @'
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:views="clr-namespace:MiniCodex.App.Views"
        x:Class="MiniCodex.App.Views.MainWindow"
        Title="{Binding Title}" Icon="/Assets/icon.ico"
        Width="1000" Height="700">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120"/>
            <ComboBox ItemsSource="{Binding Themes}" SelectedItem="{Binding CurrentTheme}" Width="120"/>
        </StackPanel>
        <views:LibraryView Grid.Row="1" DataContext="{Binding Library}"/>
    </Grid>
</Window>
'@

# ============ App/App.axaml.cs (правка через regex) ============
# (не в $Files, потому что нужно точечно вставить AppServices.Init)

# ============ README патча ============
$Files['patches\0.2.3\README.md'] = @'
# Патч 0.2.3 — Экран «Библиотека»: сетка карточек с превью

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- `AppServices` — composition root (SQLite factory, репозитории, Scanner, PreviewGenerator).
- `LibraryViewModel` — загрузка моделей, команда сканирования папок, коллекция карточек.
- `ModelCardViewModel` — модель + превью + метаданные, превью генерируется в фоне (`Task.Run`), UI не блокируется.
- `LibraryView.axaml` — сетка карточек (`WrapPanel` + `ScrollViewer`), кнопка «Сканировать папку», пустое состояние.
- `LibraryView.axaml.cs` — Avalonia `IStorageProvider.OpenFolderPickerAsync` для выбора папок.
- `MainWindow.axaml` — заменяет приветствие на `LibraryView`, ComboBox языка/темы остаются сверху.
- `MainWindowViewModel` — свойство `Library`, DI-инициализация.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3\patch_0.2.3.ps1"

## DoD

- Приложение запускается, показывает пустое состояние.
- Кнопка «Сканировать папку» → FolderPicker → карточки с превью.
- UI не блокируется во время сканирования.
- Hover-панель и виртуализация — **в 0.2.3a / 0.2.3b** (не входят в этот патч).
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.App\App.axaml.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\Views\MainWindow.axaml',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # --- Правка App.axaml.cs: AppServices.Init(Paths) после DatabaseInitializer ---
    $appCs = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml.cs'
    $content = [IO.File]::ReadAllText($appCs, [Text.Encoding]::UTF8)
    if ($content -notmatch 'AppServices\.Init') {
        $content = $content -replace
            '(DatabaseInitializer\.InitializeAsync\(Paths\.LibraryDb\)\.GetAwaiter\(\)\.GetResult\(\);)',
            "`$1`r`n            AppServices.Init(Paths);"
        Write-Text -Path $appCs -Content $content
        Write-Log 'updated: src\MiniCodex.App\App.axaml.cs (AppServices.Init)'
    } else {
        Write-Log 'App.axaml.cs: AppServices уже подключён, пропускаю.' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.3 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.2.3] - 2026-11-10`n`n### Added`n- Экран «Библиотека»: сетка карточек с превью.`n- Кнопка «Сканировать папку» (FolderPicker).`n- Фоновая генерация превью на карточках.`n- AppServices (composition root).`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.2a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.3.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}