#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.3b — фикс: разворот моделей, тема карточек, локализация UI библиотеки.
.DESCRIPTION
    YawDegrees {180,270,0,90} + RendererVersion bump.
    DynamicResource в LibraryView.axaml.
    Ключи Library.* в lang/*.json + RefreshLocalized.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.3b'
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

# ============ PreviewGeneratorOptions.cs — разворот на 180 ============
$Files['src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'] = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 256;
    public int Height { get; set; } = 256;
    public float PitchDegrees { get; set; } = 15f;
    // 180 — начальный ракурс лицом к камере (3D-печать смотрит в −Y после Z→Y конверсии).
    public float[] YawDegrees { get; set; } = { 180f, 270f, 0f, 90f };
}
'@

# ============ PreviewGenerator.cs — bump RendererVersion ============
$Files['src\MiniCodex.Core\Services\PreviewGenerator.cs'] = @'
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
    // Увеличивайте при изменении алгоритма рендера — инвалидирует кэш.
    private const string RendererVersion = "0.2.3b";

    private readonly IPreviewRenderer _renderer;
    private readonly IMeshGeometryLoader _loader;
    private readonly string _cacheDir;
    private readonly PreviewGeneratorOptions _options;

    public PreviewGenerator(
        IPreviewRenderer renderer,
        IMeshGeometryLoader loader,
        string cacheDir,
        PreviewGeneratorOptions? options = null)
    {
        _renderer = renderer;
        _loader = loader;
        _cacheDir = cacheDir;
        _options = options ?? new PreviewGeneratorOptions();
    }

    public async Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        CancellationToken ct = default)
    {
        return await Task.Run(() => GenerateAll(modelId, meshPath, sourceUpdatedAt, ct), ct);
    }

    private IReadOnlyList<string?> GenerateAll(string modelId, string meshPath, DateTime sourceUpdatedAt, CancellationToken ct)
    {
        var results = new string?[_options.YawDegrees.Length];
        var modelDir = Path.Combine(_cacheDir, modelId);
        Directory.CreateDirectory(modelDir);

        var metaPath = Path.Combine(modelDir, "metadata.json");
        CacheMetadata? meta = null;
        if (File.Exists(metaPath))
        {
            try { meta = JsonSerializer.Deserialize<CacheMetadata>(File.ReadAllText(metaPath)); } catch { }
        }

        var needsRegen =
            meta == null ||
            meta.RendererVersion != RendererVersion ||
            meta.SourceUpdatedAt < sourceUpdatedAt;

        for (int i = 0; i < _options.YawDegrees.Length; i++)
        {
            if (ct.IsCancellationRequested) return results;
            var pngPath = Path.Combine(modelDir, $"{(int)_options.YawDegrees[i]}.png");
            if (needsRegen || !File.Exists(pngPath))
                pngPath = RenderOne(modelId, meshPath, _options.YawDegrees[i], pngPath, ct);
            results[i] = File.Exists(pngPath) ? pngPath : null;
        }

        if (needsRegen)
        {
            var newMeta = new CacheMetadata
            {
                ModelId = modelId,
                SourcePath = meshPath,
                SourceUpdatedAt = sourceUpdatedAt,
                GeneratedAt = DateTime.UtcNow,
                RendererVersion = RendererVersion,
            };
            File.WriteAllText(metaPath, JsonSerializer.Serialize(newMeta, new JsonSerializerOptions { WriteIndented = true }));
        }
        return results;
    }

    private string RenderOne(string modelId, string meshPath, float yaw, string outPath, CancellationToken ct)
    {
        var geometry = _loader.LoadGeometry(meshPath);
        if (geometry == null || geometry.TriangleCount == 0) return outPath;
        if (ct.IsCancellationRequested) return outPath;

        var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, _options.PitchDegrees);
        File.WriteAllBytes(outPath, png);
        return outPath;
    }

    private class CacheMetadata
    {
        [JsonPropertyName("modelId")] public string ModelId { get; set; } = string.Empty;
        [JsonPropertyName("sourcePath")] public string SourcePath { get; set; } = string.Empty;
        [JsonPropertyName("sourceUpdatedAt")] public DateTime SourceUpdatedAt { get; set; }
        [JsonPropertyName("generatedAt")] public DateTime GeneratedAt { get; set; }
        [JsonPropertyName("rendererVersion")] public string? RendererVersion { get; set; }
    }
}
'@

# ============ LibraryView.axaml — DynamicResource + Bindings ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.LibraryView">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="8" Spacing="8">
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
                    <DataTemplate>
                        <Border Width="220" Height="260" Margin="6"
                                BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                BorderThickness="1" CornerRadius="6" Padding="6">
                            <Grid RowDefinitions="180,*,Auto">
                                <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                        CornerRadius="4">
                                    <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
                                </Border>
                                <TextBlock Grid.Row="1" Text="{Binding Title}"
                                           FontWeight="Bold" TextTrimming="CharacterEllipsis"
                                           Margin="0,6,0,0"/>
                                <TextBlock Grid.Row="2" FontSize="11"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                           Text="{Binding StatusText}"/>
                            </Grid>
                        </Border>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>

        <TextBlock Grid.Row="1" Text="{Binding EmptyStateText}"
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                   IsVisible="{Binding IsEmpty}"/>
    </Grid>
</UserControl>
'@

# ============ LibraryViewModel.cs — локализация ============
$Files['src\MiniCodex.App\ViewModels\LibraryViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
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

    public bool IsEmpty => !IsBusy && Cards.Count == 0;

    public string ScanButtonText => App.Loc?.Get("Library.ScanButton") ?? "Scan folder";
    public string EmptyStateText => App.Loc?.Get("Library.Empty") ?? "No models yet.";

    private enum StatusState { None, Loading, ModelCount, Scanning }
    private StatusState _statusState = StatusState.None;
    private int _statusCount;
    private string _statusDetail = string.Empty;

    public string StatusText => _statusState switch
    {
        StatusState.Loading => App.Loc?.Get("Library.Loading") ?? "Loading…",
        StatusState.ModelCount => string.Format(App.Loc?.Get("Library.ModelsCount") ?? "Models: {0}", _statusCount),
        StatusState.Scanning => _statusDetail,
        _ => string.Empty,
    };

    private void SetStatus(StatusState state, int count = 0, string detail = "")
    {
        _statusState = state;
        _statusCount = count;
        _statusDetail = detail;
        Raise(nameof(StatusText));
    }

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

    public void RefreshLocalized()
    {
        Raise(nameof(ScanButtonText));
        Raise(nameof(EmptyStateText));
        // Если сейчас показывается количество моделей — пересчитаем строку с новым языком.
        if (_statusState == StatusState.ModelCount)
            SetStatus(StatusState.ModelCount, _statusCount);
        else
            Raise(nameof(StatusText));
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        if (_models == null || _files == null || _previews == null)
        {
            _statusDetail = App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.";
            _statusState = StatusState.Scanning;
            Raise(nameof(StatusText));
            return;
        }
        IsBusy = true;
        try
        {
            SetStatus(StatusState.Loading);
            var all = await _models.GetAllAsync(ct);
            Cards.Clear();
            foreach (var m in all)
            {
                var card = new ModelCardViewModel(m);
                Cards.Add(card);
                _ = Task.Run(() => card.LoadDetailsAsync(_files, _previews, ct), ct);
            }
            SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
            Raise(nameof(IsEmpty));
        }
        finally { IsBusy = false; }
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        if (_scanner == null || _models == null || _files == null || _previews == null)
            return;
        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning…");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                var detail = string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped);
                SetStatus(StatusState.Scanning, 0, detail);
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

# ============ MainWindowViewModel.cs — вызов RefreshLocalized ============
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
            Library.RefreshLocalized();
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

# ============ lang/en.json — добавлены Library.* ключи ============
$Files['lang\en.json'] = @'
{
  "App": {
    "Name": "MiniCodex",
    "Version": "0.0.0",
    "Tagline": "Portable 3D model library"
  },
  "Menu": {
    "Library": "Library",
    "Settings": "Settings",
    "About": "About"
  },
  "Common": {
    "Ok": "OK",
    "Cancel": "Cancel",
    "Save": "Save",
    "Delete": "Delete",
    "Close": "Close",
    "Browse": "Browse…",
    "Loading": "Loading…",
    "Error": "Error",
    "Warning": "Warning"
  },
  "Settings": {
    "Title": "Settings",
    "Section": {
      "Sources": "Source folders",
      "AssetsRoot": "Associations root",
      "Integrations": "Slicers & editors",
      "Appearance": "Appearance",
      "Database": "Database"
    },
    "Theme": {
      "Label": "Theme",
      "Light": "Light",
      "Dark": "Dark",
      "Auto": "Auto"
    },
    "Language": {
      "Label": "Language",
      "Ru": "Русский",
      "En": "English"
    },
    "LowDiskSpace": "Less than 500 MB free on the data drive."
  },
  "Library": {
    "Title": "Library",
    "SearchPlaceholder": "Search by name, tag, author, source…",
    "Empty": "No models yet. Click “Scan folder”.",
    "ScanButton": "Scan folder",
    "ScanFolderTitle": "Select source folder",
    "Loading": "Loading library…",
    "ModelsCount": "Models: {0}",
    "Scanning": "Scanning…",
    "ScanningProgress": "Scanning: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Services not initialized.",
    "Hover": {
      "TotalSize": "Total size",
      "Polygons": "Polygons",
      "Files": "Files",
      "Status": "Status"
    },
    "Status": {
      "Planned": "Planned",
      "Printed": "Printed",
      "Painted": "Painted"
    },
    "QuickActions": {
      "ToSlicer": "To slicer",
      "ToEditor": "To editor",
      "ShowInFolder": "Show in folder"
    },
    "ContextMenu": {
      "CopyPath": "Copy path",
      "RemoveFromLibrary": "Remove from library",
      "AddTag": "Add tag",
      "OpenCard": "Open card"
    }
  },
  "Card": {
    "Tabs": {
      "Info": "Info",
      "Files": "Files",
      "Associations": "Associations",
      "Tags": "Tags",
      "Notes": "Notes",
      "Scale": "Scale"
    },
    "Actions": {
      "Orient": "Orient",
      "RegeneratePreviews": "Regenerate previews",
      "OpenInSlicer": "Open in slicer",
      "OpenInEditor": "Open in editor",
      "ShowInFolder": "Show in folder"
    },
    "Fields": {
      "Title": "Title",
      "Author": "Author",
      "SourceUrl": "Source URL",
      "Status": "Status",
      "Difficulty": "Paint difficulty",
      "Notes": "Notes",
      "RealHeightMm": "Prototype real height (mm)",
      "ModelHeightMm": "Model height (mm)",
      "Scale": "Target scale",
      "PrototypeType": "Prototype type"
    },
    "FileRole": {
      "Main": "Main",
      "Part": "Part",
      "Presupported": "Pre-supported",
      "Hollowed": "Hollowed",
      "Variant": "Variant",
      "Accessory": "Accessory"
    },
    "AssetType": {
      "Reference": "Reference",
      "Render": "Render",
      "Photo": "Photo",
      "Document": "Document",
      "Profile": "Print profile"
    },
    "RemoveFromCard": "Remove from card"
  },
  "About": {
    "Title": "About",
    "License": "Licensed under MIT.",
    "Support": "Support the author"
  },
  "Error": {
    "ParseFailed": "Failed to parse mesh file",
    "FolderUnavailable": "Source folder is unavailable"
  }
}
'@

# ============ lang/ru.json — добавлены Library.* ключи ============
$Files['lang\ru.json'] = @'
{
  "App": {
    "Name": "MiniCodex",
    "Version": "0.0.0",
    "Tagline": "Portable-библиотека 3D-моделей"
  },
  "Menu": {
    "Library": "Библиотека",
    "Settings": "Настройки",
    "About": "О программе"
  },
  "Common": {
    "Ok": "ОК",
    "Cancel": "Отмена",
    "Save": "Сохранить",
    "Delete": "Удалить",
    "Close": "Закрыть",
    "Browse": "Обзор…",
    "Loading": "Загрузка…",
    "Error": "Ошибка",
    "Warning": "Предупреждение"
  },
  "Settings": {
    "Title": "Настройки",
    "Section": {
      "Sources": "Папки-источники",
      "AssetsRoot": "Корень ассоциаций",
      "Integrations": "Слайсеры и редакторы",
      "Appearance": "Внешний вид",
      "Database": "База данных"
    },
    "Theme": {
      "Label": "Тема",
      "Light": "Светлая",
      "Dark": "Тёмная",
      "Auto": "Авто"
    },
    "Language": {
      "Label": "Язык",
      "Ru": "Русский",
      "En": "English"
    },
    "LowDiskSpace": "Свободно менее 500 МБ на диске с данными."
  },
  "Library": {
    "Title": "Библиотека",
    "SearchPlaceholder": "Поиск по имени, тегу, автору, источнику…",
    "Empty": "Пока нет моделей. Нажмите «Сканировать папку».",
    "ScanButton": "Сканировать папку",
    "ScanFolderTitle": "Выберите папку-источник",
    "Loading": "Загрузка библиотеки…",
    "ModelsCount": "Моделей: {0}",
    "Scanning": "Сканирование…",
    "ScanningProgress": "Сканирование: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Сервисы не инициализированы.",
    "Hover": {
      "TotalSize": "Общий размер",
      "Polygons": "Полигоны",
      "Files": "Файлы",
      "Status": "Статус"
    },
    "Status": {
      "Planned": "В планах",
      "Printed": "Напечатано",
      "Painted": "Покрашено"
    },
    "QuickActions": {
      "ToSlicer": "В слайсер",
      "ToEditor": "В редактор",
      "ShowInFolder": "В папке"
    },
    "ContextMenu": {
      "CopyPath": "Копировать путь",
      "RemoveFromLibrary": "Удалить из библиотеки",
      "AddTag": "Добавить тег",
      "OpenCard": "Открыть карточку"
    }
  },
  "Card": {
    "Tabs": {
      "Info": "Инфо",
      "Files": "Файлы",
      "Associations": "Ассоциации",
      "Tags": "Теги",
      "Notes": "Заметки",
      "Scale": "Масштаб"
    },
    "Actions": {
      "Orient": "Ориентировать",
      "RegeneratePreviews": "Перегенерировать превью",
      "OpenInSlicer": "Открыть в слайсере",
      "OpenInEditor": "Открыть в редакторе",
      "ShowInFolder": "Показать в папке"
    },
    "Fields": {
      "Title": "Название",
      "Author": "Автор",
      "SourceUrl": "Источник (URL)",
      "Status": "Статус",
      "Difficulty": "Сложность покраса",
      "Notes": "Заметки",
      "RealHeightMm": "Реальная высота прототипа (мм)",
      "ModelHeightMm": "Высота модели (мм)",
      "Scale": "Целевой масштаб",
      "PrototypeType": "Тип прототипа"
    },
    "FileRole": {
      "Main": "Основной",
      "Part": "Часть",
      "Presupported": "Pre-supported",
      "Hollowed": "Полый",
      "Variant": "Вариант",
      "Accessory": "Аксессуар"
    },
    "AssetType": {
      "Reference": "Референс",
      "Render": "Рендер",
      "Photo": "Фото готовой работы",
      "Document": "Документ",
      "Profile": "Профиль печати"
    },
    "RemoveFromCard": "Убрать из карточки"
  },
  "About": {
    "Title": "О программе",
    "License": "Лицензия MIT.",
    "Support": "Поддержать автора"
  },
  "Error": {
    "ParseFailed": "Не удалось разобрать файл модели",
    "FolderUnavailable": "Папка-источник недоступна"
  }
}
'@

# ============ README патча ============
$Files['patches\0.2.3b\README.md'] = @'
# Патч 0.2.3b — разворот моделей, тема карточек, локализация UI библиотеки

**Итерация:** 0.2 · **Статус:** реализован

## Причины

1. **Модели показывались сзади.** После Z-up→Y-up 3D-печатная модель (перед в −Y)
   проецировалась «затылком». Решение — сдвинуть набор ракурсов на 180°.
2. **Рамка карточек не менялась при смене темы.** В `LibraryView.axaml` были
   захардкожены `Background`, `BorderBrush`, `Foreground`. Заменено на
   `{DynamicResource SystemControl*Brush}` из Fluent-темы Avalonia.
3. **Язык не менял текст.** Строки «Сканировать папку», «Загрузка библиотеки…»,
   «Моделей: N», «Сканирование…» были захардкожены по-русски. Добавлены ключи
   `Library.ScanButton`, `Library.Loading`, `Library.ModelsCount`,
   `Library.Scanning`, `Library.ScanningProgress`, `Library.ServicesNotInitialized`,
   `Library.ScanFolderTitle` в `lang/en.json` и `lang/ru.json`.

## Что делает

- `PreviewGeneratorOptions.YawDegrees = {180, 270, 0, 90}` — карточка показывает лицо.
- `PreviewGenerator.RendererVersion = "0.2.3b"` — кэш превью инвалидируется, все
  PNG перегенерируются при первом показе.
- `LibraryView.axaml` — DynamicResource для фона, рамки и текста; биндинги на
  `ScanButtonText` и `EmptyStateText`.
- `LibraryViewModel` — computed-свойства из `App.Loc`, `RefreshLocalized()`,
  переделанный `StatusText` через `StatusState`.
- `MainWindowViewModel.CurrentLanguage.set` — вызывает `Library.RefreshLocalized()`
  после `App.Loc.SetLanguage`.
- `lang/en.json`, `lang/ru.json` — расширены ключами `Library.*`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3b\patch_0.2.3b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста, 0 сбоев.
- При первом показе карточек превью перерисовываются: модель лицом к камере.
- Переключение темы `auto`→`dark`→`light` меняет фон и рамку карточек.
- Переключение языка `ru`→`en` меняет кнопку «Сканировать папку» / «Scan folder»,
  статус «Моделей: 172» / «Models: 172», пустое состояние.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs',
        'src\MiniCodex.Core\Services\PreviewGenerator.cs',
        'src\MiniCodex.App\Views\LibraryView.axaml',
        'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'lang\en.json',
        'lang\ru.json',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # Копируем lang/*.json в выход приложения (Content настроен в csproj — при сборке подхватится)
    Write-Log 'lang/*.json обновлены — при следующей сборке копируются в bin\Debug\net8.0\lang\.'

    # CHANGELOG
    $marker = '<!-- patch 0.2.3b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.3b: модели развёрнуты лицом (YawDegrees 180°).`n- 0.2.3b: рамка и фон карточек меняются при смене темы (DynamicResource).`n- 0.2.3b: UI библиотеки локализован (RU/EN).`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.3a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.3b.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}