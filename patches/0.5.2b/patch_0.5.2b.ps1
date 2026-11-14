# patch_0.5.2b.ps1 - Smart Collections + Tag color ViewModels
# One logical step. No XAML. No lang keys. 55 tests must stay green.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.2b'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot ("backups\{0}_{1}" -f $Version, $Timestamp)
$PatchDir    = Join-Path $ProjectRoot ("patches\{0}" -f $Version)
$LogPath     = Join-Path $PatchDir 'patch.log'
$utf8NoBom   = [Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $PatchDir  | Out-Null

function Write-Log([string]$msg) {
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Replace-Exact([string]$path, $pairs) {
    $c = [IO.File]::ReadAllText($path, $utf8NoBom)
    $hadCrLf = $c.Contains("`r`n")
    if ($hadCrLf) { $c = $c.Replace("`r`n", "`n") }
    foreach ($p in $pairs) {
        $old = $p.Old.Replace("`r`n", "`n")
        $new = $p.New.Replace("`r`n", "`n")
        $cnt = [regex]::Matches($c, [regex]::Escape($old)).Count
        if ($cnt -eq 0) { throw ("Anchor not found: {0}" -f $p.Label) }
        if ($cnt -gt 1) { throw ("Anchor ambiguous ({0} occurrences): {1}" -f $cnt, $p.Label) }
        $c = $c.Replace($old, $new)
        Write-Log ("  replaced: {0}" -f $p.Label)
    }
    if ($hadCrLf) { $c = $c.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $c, $utf8NoBom)
}

Write-Log ("Patch {0} started" -f $Version)
Write-Log ("Backup dir: {0}" -f $BackupDir)

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs',
    'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
    'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src = Join-Path $ProjectRoot $rel
    if (Test-Path -LiteralPath $src) {
        $dst    = Join-Path $BackupDir $rel
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Log ("Backed up: {0}" -f $rel)
    } else {
        throw ("Required file missing: {0}" -f $src)
    }
}

# ---------- 2. Create CollectionRow.cs ----------
$rowPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\CollectionRow.cs'
if (-not (Test-Path -LiteralPath $rowPath)) {
    $rowContent = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class CollectionRow
{
    public string Id { get; init; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public SmartCollectionFilter Filter { get; set; } = SmartCollectionFilter.Empty;
    public bool IsSmart { get; set; } = true;

    public static CollectionRow From(Collection c) => new()
    {
        Id = c.Id,
        Name = c.Name,
        Filter = CollectionService.DeserializeFilter(c.FilterQuery),
        IsSmart = c.IsSmart,
    };
}
'@
    [IO.File]::WriteAllText($rowPath, $rowContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $rowPath)
} else {
    Write-Log ("Already exists, skip: {0}" -f $rowPath)
}

# ---------- 3. Rewrite TagNodeViewModel.cs (full) ----------
$tagNodePath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs'
$tagNodeContent = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media;

namespace MiniCodex.App.ViewModels;

public class TagNodeViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? ParentId { get; set; }

    private int _usageCount;
    public int UsageCount
    {
        get => _usageCount;
        set { _usageCount = value; Raise(); }
    }

    private string? _color;
    public string? Color
    {
        get => _color;
        set
        {
            if (_color == value) return;
            _color = value;
            Raise();
            Raise(nameof(HasColor));
            Raise(nameof(ColorBrush));
        }
    }

    public bool HasColor => !string.IsNullOrWhiteSpace(_color);

    public IBrush? ColorBrush
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_color)) return null;
            if (Avalonia.Media.Color.TryParse(_color, out var c))
                return new SolidColorBrush(c);
            return null;
        }
    }

    public Action<TagNodeViewModel, string?>? OnColorChange { get; set; }

    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }

    public static IReadOnlyList<string> Palette { get; } = new[]
    {
        "#E67E22",
        "#E74C3C",
        "#F39C12",
        "#2ECC71",
        "#3498DB",
        "#9B59B6",
        "#95A5A6",
        "#34495E",
    };

    public ObservableCollection<TagNodeViewModel> Children { get; } = new();

    private bool _isExpanded = true;
    public bool IsExpanded
    {
        get => _isExpanded;
        set { _isExpanded = value; Raise(); }
    }

    public TagNodeViewModel()
    {
        SetColorCommand = new RelayCommand(
            p =>
            {
                if (p is string s && !string.IsNullOrWhiteSpace(s))
                    OnColorChange?.Invoke(this, s);
            },
            _ => !string.IsNullOrEmpty(Id));
        ClearColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnColorChange?.Invoke(this, null); },
            () => !string.IsNullOrEmpty(Id));
    }

    public override bool Equals(object? obj) => obj is TagNodeViewModel other && Id == other.Id;
    public override int GetHashCode() => Id.GetHashCode();
}
'@
[IO.File]::WriteAllText($tagNodePath, $tagNodeContent, $utf8NoBom)
Write-Log ("Rewritten: {0}" -f $tagNodePath)

# ---------- 4. Update LibraryViewModel.cs (targeted) ----------
$libPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$libPairs = @(
    @{
        Label = 'add fields'
        Old = @'
    private readonly ITagService? _tagService;
    private readonly IIntegrationService? _integration;
'@
        New = @'
    private readonly ITagService? _tagService;
    private readonly IIntegrationService? _integration;
    private readonly ICollectionService? _collectionService;
    private readonly RelayCommand _deleteCollectionCommand;
'@
    },
    @{
        Label = 'add Collections collection'
        Old = @'
    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
    public ObservableCollection<TagNodeViewModel> Tags { get; } = new();
'@
        New = @'
    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
    public ObservableCollection<TagNodeViewModel> Tags { get; } = new();
    public ObservableCollection<CollectionRow> Collections { get; } = new();
'@
    },
    @{
        Label = 'add SelectedCollection property'
        Old = @'
    private TagNodeViewModel? _selectedTag;
    public TagNodeViewModel? SelectedTag
    {
        get => _selectedTag;
        set
        {
            if (Equals(_selectedTag, value)) return;
            _selectedTag = value;
            Raise();
            if (!_suppressTagReload)
                _ = ReloadModelsAsync(CancellationToken.None);
        }
    }
'@
        New = @'
    private TagNodeViewModel? _selectedTag;
    public TagNodeViewModel? SelectedTag
    {
        get => _selectedTag;
        set
        {
            if (Equals(_selectedTag, value)) return;
            _selectedTag = value;
            Raise();
            if (!_suppressTagReload)
                _ = ReloadModelsAsync(CancellationToken.None);
        }
    }

    private CollectionRow? _selectedCollection;
    public CollectionRow? SelectedCollection
    {
        get => _selectedCollection;
        set
        {
            if (Equals(_selectedCollection, value)) return;
            _selectedCollection = value;
            Raise();
            _deleteCollectionCommand?.RaiseCanExecuteChanged();
            if (value != null)
                _ = ApplyCollectionAsync(value);
        }
    }
'@
    },
    @{
        Label = 'add command declarations'
        Old = @'
    public ICommand ToggleDuplicatesCommand { get; }
    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ConfirmScanCommand { get; }
    public ICommand CancelScanCommand { get; }
'@
        New = @'
    public ICommand ToggleDuplicatesCommand { get; }
    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ConfirmScanCommand { get; }
    public ICommand CancelScanCommand { get; }
    public ICommand SaveCurrentFilterAsCollectionCommand { get; }
    public ICommand DeleteCollectionCommand => _deleteCollectionCommand;
'@
    },
    @{
        Label = 'ctor signature'
        Old = @'
        ITagService? tagService,
        IIntegrationService? integration)
'@
        New = @'
        ITagService? tagService,
        IIntegrationService? integration,
        ICollectionService? collectionService = null)
'@
    },
    @{
        Label = 'ctor assignment'
        Old = @'
        _integration = integration;
'@
        New = @'
        _integration = integration;
        _collectionService = collectionService;
'@
    },
    @{
        Label = 'ctor command init'
        Old = @'
        CancelScanCommand = new RelayCommand(CancelScan);
'@
        New = @'
        CancelScanCommand = new RelayCommand(CancelScan);
        SaveCurrentFilterAsCollectionCommand = new RelayCommand(() => _ = SaveCurrentFilterAsync(null));
        _deleteCollectionCommand = new RelayCommand(
            () => { if (SelectedCollection != null) _ = DeleteCollectionAsync(SelectedCollection); },
            () => SelectedCollection != null);
'@
    },
    @{
        Label = 'LoadAsync calls LoadCollectionsAsync'
        Old = @'
            _selectedTag = null; // Reset filter to "All Models" on load
            await LoadTagsAsync(ct);
            await ReloadModelsCoreAsync(ct);
'@
        New = @'
            _selectedTag = null; // Reset filter to "All Models" on load
            await LoadTagsAsync(ct);
            await LoadCollectionsAsync(ct);
            await ReloadModelsCoreAsync(ct);
'@
    },
    @{
        Label = 'LoadTagsAsync propagates Color + callback'
        Old = @'
                dict[t.Id] = new TagNodeViewModel { Id = t.Id, Name = t.Name, ParentId = t.ParentId, UsageCount = t.UsageCount };
'@
        New = @'
                dict[t.Id] = new TagNodeViewModel
                {
                    Id = t.Id,
                    Name = t.Name,
                    ParentId = t.ParentId,
                    UsageCount = t.UsageCount,
                    Color = t.Color,
                    OnColorChange = (node, c) => _ = ChangeTagColorAsync(node, c),
                };
'@
    },
    @{
        Label = 'RefreshLocalized new raises'
        Old = @'
        Raise(nameof(ScanWarningCancelText));
'@
        New = @'
        Raise(nameof(ScanWarningCancelText));
        Raise(nameof(CollectionsHeader));
        Raise(nameof(SaveFilterButtonText));
        Raise(nameof(DeleteCollectionTooltip));
'@
    },
    @{
        Label = 'insert new methods before ScanAsync'
        Old = @'
    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
'@
        New = @'
    public string CollectionsHeader => App.Loc?.Get("Library.CollectionsHeader") ?? "Collections";
    public string SaveFilterButtonText => App.Loc?.Get("Library.SaveFilterButton") ?? "Save filter";
    public string DeleteCollectionTooltip => App.Loc?.Get("Library.DeleteCollection") ?? "Delete collection";

    private async Task LoadCollectionsAsync(CancellationToken ct = default)
    {
        if (_collectionService == null) return;
        try
        {
            var all = await _collectionService.GetSmartAsync(ct);
            Collections.Clear();
            foreach (var c in all) Collections.Add(CollectionRow.From(c));
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadCollections failed", ex); }
    }

    public async Task SaveCurrentFilterAsync(string? name)
    {
        if (_collectionService == null) return;
        var tag = _selectedTag;
        var filter = new SmartCollectionFilter(
            string.IsNullOrWhiteSpace(_searchQuery) ? null : _searchQuery.Trim(),
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Id,
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Name);
        if (filter.IsEmpty)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.SaveFilterEmpty") ?? "Nothing to save: filter is empty.");
            return;
        }
        if (string.IsNullOrWhiteSpace(name))
            name = "Filter " + DateTime.Now.ToString("HH:mm:ss");
        try
        {
            await _collectionService.SaveSmartAsync(name.Trim(), filter);
            await LoadCollectionsAsync();
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] SaveCurrentFilterAsync failed", ex); }
    }

    public async Task DeleteCollectionAsync(CollectionRow row)
    {
        if (_collectionService == null || row == null) return;
        try
        {
            await _collectionService.DeleteAsync(row.Id);
            Collections.Remove(row);
            if (Equals(_selectedCollection, row)) _selectedCollection = null;
            Raise(nameof(SelectedCollection));
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] DeleteCollectionAsync failed", ex); }
    }

    public async Task ChangeTagColorAsync(TagNodeViewModel tag, string? color)
    {
        if (_tagService == null || tag == null || string.IsNullOrEmpty(tag.Id)) return;
        try
        {
            await _tagService.SetColorAsync(tag.Id, color);
            tag.Color = color;
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ChangeTagColorAsync failed", ex); }
    }

    private async Task ApplyCollectionAsync(CollectionRow row)
    {
        _suppressTagReload = true;
        try
        {
            _searchQuery = row.Filter.Search ?? string.Empty;
            Raise(nameof(SearchQuery));

            if (!string.IsNullOrEmpty(row.Filter.TagId))
                _selectedTag = FindTagById(row.Filter.TagId);
            else
                _selectedTag = Tags.FirstOrDefault();
            Raise(nameof(SelectedTag));
        }
        finally { _suppressTagReload = false; }

        await ReloadModelsAsync(CancellationToken.None);
    }

    private TagNodeViewModel? FindTagById(string id)
    {
        foreach (var root in Tags)
        {
            var f = FindTagByIdRec(root, id);
            if (f != null) return f;
        }
        return null;
    }

    private static TagNodeViewModel? FindTagByIdRec(TagNodeViewModel node, string id)
    {
        if (string.Equals(node.Id, id, StringComparison.Ordinal)) return node;
        foreach (var child in node.Children)
        {
            var f = FindTagByIdRec(child, id);
            if (f != null) return f;
        }
        return null;
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
'@
    }
)
Replace-Exact $libPath $libPairs
Write-Log ("Updated: {0}" -f $libPath)

# ---------- 5. Update MainWindowViewModel.cs ----------
$mwPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'
$mwPairs = @(
    @{
        Label = 'LibraryViewModel ctor 7th arg'
        Old = @'
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService,
            AppServices.IntegrationService);
'@
        New = @'
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService,
            AppServices.IntegrationService,
            AppServices.CollectionService);
'@
    }
)
Replace-Exact $mwPath $mwPairs
Write-Log ("Updated: {0}" -f $mwPath)

# ---------- 6. CHANGELOG.md ----------
$chPath = Join-Path $ProjectRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $chPath) {
    $c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
    if ($c -notmatch 'patch 0\.5\.2b applied') {
        $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
        $entry = $nl +
            '## 0.5.2b - Smart Collections + Tag color (ViewModels)' + $nl + $nl +
            '- CollectionRow (MiniCodex.App.ViewModels) wraps Collection + deserialized SmartCollectionFilter.' + $nl +
            '- TagNodeViewModel: Color, ColorBrush, HasColor, Palette (8 swatches), SetColorCommand, ClearColorCommand, OnColorChange callback.' + $nl +
            '- LibraryViewModel: Collections collection, SelectedCollection, SaveCurrentFilterAsCollectionCommand, DeleteCollectionCommand, ApplyCollectionAsync, ChangeTagColorAsync, LoadCollectionsAsync.' + $nl +
            '- LibraryViewModel ctor gains 7th optional ICollectionService parameter.' + $nl +
            '- MainWindowViewModel passes AppServices.CollectionService.' + $nl + $nl +
            '<!-- patch 0.5.2b applied -->' + $nl
        [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
        Write-Log 'CHANGELOG.md updated.'
    } else {
        Write-Log 'CHANGELOG.md already has patch 0.5.2b marker, skip.'
    }
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next:'
Write-Log '  1) dotnet build D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  2) dotnet test  D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  Expect: 0 errors, 0 warnings, 55 tests.'
Write-Log 'Rollback (if needed):'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)