# patch_0.5.6c.ps1
# 0.5.6c - Tags / Collections polish
#   - Migration 0005: Collection.color
#   - Entities / ICollectionService / CollectionService / CollectionRepository: color plumbing
#   - CollectionRow: INotifyPropertyChanged, Color, ColorBrush, HasColor, Palette,
#                    SetColorCommand, ClearColorCommand, OnColorChange
#   - LibraryViewModel: _tagDirectUsage dict, breakdown in DeleteTagDialog, LoadCollections
#                       wires OnColorChange, ChangeCollectionColorAsync
#   - ModelCardPageViewModel: TagCandidates + RefreshTagCandidatesAsync (called in
#                             LoadAsync and AddTagAsync)
#   - LibraryView.axaml: collections item template (color dot + context menu)
#   - ModelCardView.axaml: AutoCompleteBox for NewTagName
#   - lang/en.json + lang/ru.json: DeleteTagDialog.Message -> 3-param format
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6c\patch_0.5.6c.ps1"

Write-Host "=== MiniCodex patch 0.5.6c STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6c'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot ('patches\' + $version)
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir ('patch_' + $version + '.log')

if (-not (Test-Path $projectRoot)) { throw ("Project root not found: " + $projectRoot) }
New-Item -ItemType Directory -Force -Path $patchDir  | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { throw ("ASSERT FAILED: " + $msg) }
}
function Replace-Exact([string]$content, [string]$old, [string]$new, [string]$tag) {
    $cnt = [regex]::Matches($content, [regex]::Escape($old)).Count
    Assert ($cnt -eq 1) ("anchor '" + $tag + "' matched " + $cnt + " times (expected 1)")
    Log ("  replace-exact OK: " + $tag)
    return $content.Replace($old, $new)
}

Log ("=== MiniCodex patch " + $version + " ===")

$migPath    = Join-Path $projectRoot 'src\MiniCodex.Data\Migrations\Migration_0005_Collection_Color.cs'
$dbInitPath = Join-Path $projectRoot 'src\MiniCodex.Data\DatabaseInitializer.cs'
$entPath    = Join-Path $projectRoot 'src\MiniCodex.Core\Models\Entities.cs'
$repoPath   = Join-Path $projectRoot 'src\MiniCodex.Data\Repositories\CollectionRepository.cs'
$isvcPath   = Join-Path $projectRoot 'src\MiniCodex.Core\Services\ICollectionService.cs'
$svcPath    = Join-Path $projectRoot 'src\MiniCodex.Core\Services\CollectionService.cs'
$rowPath    = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\CollectionRow.cs'
$libVmPath  = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$mcVmPath   = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
$libAxPath  = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$mcAxPath   = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
$enPath     = Join-Path $projectRoot 'lang\en.json'
$ruPath     = Join-Path $projectRoot 'lang\ru.json'
$clPath     = Join-Path $projectRoot 'CHANGELOG.md'

foreach ($p in @(
    $dbInitPath,$entPath,$repoPath,$isvcPath,$svcPath,$rowPath,
    $libVmPath,$mcVmPath,$libAxPath,$mcAxPath,$enPath,$ruPath,$clPath)) {
    Assert (Test-Path $p) ("Missing: " + $p)
}

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src/MiniCodex.Data/DatabaseInitializer.cs',
    'src/MiniCodex.Core/Models/Entities.cs',
    'src/MiniCodex.Data/Repositories/CollectionRepository.cs',
    'src/MiniCodex.Core/Services/ICollectionService.cs',
    'src/MiniCodex.Core/Services/CollectionService.cs',
    'src/MiniCodex.App/ViewModels/CollectionRow.cs',
    'src/MiniCodex.App/ViewModels/LibraryViewModel.cs',
    'src/MiniCodex.App/ViewModels/ModelCardPageViewModel.cs',
    'src/MiniCodex.App/Views/LibraryView.axaml',
    'src/MiniCodex.App/Views/ModelCardView.axaml',
    'lang/en.json',
    'lang/ru.json',
    'CHANGELOG.md')) {
    $src = Join-Path $projectRoot ($rel -replace '/', '\')
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir ($rel -replace '/', '\')
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log ("  backup: " + $rel)
    }
}

# ================================================================
# STEP 2: Migration_0005 (new file)
# ================================================================
Log "STEP 2: Migration_0005"

if (Test-Path $migPath) {
    Log "  Migration_0005 already exists - skipping (idempotent)"
} else {
    $migContent = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0005_Collection_Color : IMigration
{
    public int Version => 5;
    public string Description => "Add color to Collection";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE Collection ADD COLUMN color TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
'@
    $migContent = $migContent -replace "`r`n", "`n"
    Set-Content -LiteralPath $migPath -Value $migContent -Encoding UTF8 -NoNewline
    Log ("  created (" + $migContent.Length + " chars)")
}

# ================================================================
# STEP 3: DatabaseInitializer - register migration
# ================================================================
Log "STEP 3: DatabaseInitializer"

$dbInit = Get-Content -LiteralPath $dbInitPath -Raw -Encoding UTF8
$nl = if ($dbInit.Contains("`r`n")) { "`r`n" } else { "`n" }
if ($dbInit.Contains('Migration_0005_Collection_Color')) {
    Log "  already registered - skipping"
} else {
    $oldAnchor = "        new Migration_0004_ModelFile_Hash(),"
    $newAnchor = "        new Migration_0004_ModelFile_Hash()," + $nl + "        new Migration_0005_Collection_Color(),"
    $dbInit = Replace-Exact $dbInit $oldAnchor $newAnchor "DatabaseInitializer: register 0005"
    Set-Content -LiteralPath $dbInitPath -Value $dbInit -Encoding UTF8 -NoNewline
    Log ("  written (" + $dbInit.Length + " chars)")
}

# ================================================================
# STEP 4: Entities - Collection.Color
# ================================================================
Log "STEP 4: Entities.Collection.Color"

$ent = Get-Content -LiteralPath $entPath -Raw -Encoding UTF8
$nl = if ($ent.Contains("`r`n")) { "`r`n" } else { "`n" }
if ($ent.Contains('public string? Color { get; set; }')) {
    # There's already a Color in Tag. Need to specifically check Collection.
    if ($ent -match 'public class Collection\s*\{[^}]*public string\? Color') {
        Log "  Collection already has Color - skipping"
    }
}
# Check Collection block specifically
$collectionBlockPattern = 'public class Collection\s*\{[\s\S]*?\}'
$collMatch = [regex]::Match($ent, $collectionBlockPattern)
Assert ($collMatch.Success) "Entities.cs: Collection class not found"

if ($collMatch.Value.Contains('Color')) {
    Log "  Collection already has Color - skipping"
} else {
    $oldColl = @'
public class Collection
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? FilterQuery { get; set; }
    public bool IsSmart { get; set; } = true;
}
'@
    $newColl = @'
public class Collection
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? FilterQuery { get; set; }
    public bool IsSmart { get; set; } = true;
    public string? Color { get; set; }
}
'@
    $oldColl = $oldColl -replace "`r`n", $nl
    $newColl = $newColl -replace "`r`n", $nl
    $ent = Replace-Exact $ent $oldColl $newColl "Entities: Collection.Color"
    Set-Content -LiteralPath $entPath -Value $ent -Encoding UTF8 -NoNewline
    Log ("  written (" + $ent.Length + " chars)")
}

# ================================================================
# STEP 5: CollectionRepository - Upsert + Map
# ================================================================
Log "STEP 5: CollectionRepository"

$repo = Get-Content -LiteralPath $repoPath -Raw -Encoding UTF8
$nl = if ($repo.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($repo.Contains('color = excluded.color')) {
    Log "  already has color in upsert - skipping"
} else {
    $oldUpsert = @'
        cmd.CommandText = @"
INSERT INTO Collection(id, name, filter_query, is_smart) VALUES($id, $name, $filter_query, $is_smart)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, filter_query = excluded.filter_query, is_smart = excluded.is_smart;";
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.Parameters.AddWithValue("$name", c.Name);
        cmd.Parameters.AddWithValue("$filter_query", (object?)c.FilterQuery ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$is_smart", c.IsSmart ? 1 : 0);
'@
    $newUpsert = @'
        cmd.CommandText = @"
INSERT INTO Collection(id, name, filter_query, is_smart, color) VALUES($id, $name, $filter_query, $is_smart, $color)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, filter_query = excluded.filter_query, is_smart = excluded.is_smart, color = excluded.color;";
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.Parameters.AddWithValue("$name", c.Name);
        cmd.Parameters.AddWithValue("$filter_query", (object?)c.FilterQuery ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$is_smart", c.IsSmart ? 1 : 0);
        cmd.Parameters.AddWithValue("$color", (object?)c.Color ?? DBNull.Value);
'@
    $oldUpsert = $oldUpsert -replace "`r`n", $nl
    $newUpsert = $newUpsert -replace "`r`n", $nl
    $repo = Replace-Exact $repo $oldUpsert $newUpsert "CollectionRepository: upsert"
}

if ($repo.Contains('r.FieldCount > 4')) {
    Log "  Map already handles color - skipping"
} else {
    $oldMap = @'
    private static Collection Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        FilterQuery = r.IsDBNull(2) ? null : r.GetString(2),
        IsSmart = r.GetInt32(3) != 0,
    };
'@
    $newMap = @'
    private static Collection Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        FilterQuery = r.IsDBNull(2) ? null : r.GetString(2),
        IsSmart = r.GetInt32(3) != 0,
        Color = r.FieldCount > 4 && !r.IsDBNull(4) ? r.GetString(4) : null,
    };
'@
    $oldMap = $oldMap -replace "`r`n", $nl
    $newMap = $newMap -replace "`r`n", $nl
    $repo = Replace-Exact $repo $oldMap $newMap "CollectionRepository: map"
}

Set-Content -LiteralPath $repoPath -Value $repo -Encoding UTF8 -NoNewline
Log ("  written (" + $repo.Length + " chars)")

# ================================================================
# STEP 6: ICollectionService.SetColorAsync
# ================================================================
Log "STEP 6: ICollectionService"

$isvc = Get-Content -LiteralPath $isvcPath -Raw -Encoding UTF8
$nl = if ($isvc.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($isvc.Contains('SetColorAsync')) {
    Log "  already has SetColorAsync - skipping"
} else {
    $oldDecl = "    Task DeleteAsync(string id, CancellationToken ct = default);"
    $newDecl = "    Task DeleteAsync(string id, CancellationToken ct = default);" + $nl + "    Task SetColorAsync(string id, string? color, CancellationToken ct = default);"
    $isvc = Replace-Exact $isvc $oldDecl $newDecl "ICollectionService: SetColorAsync decl"
    Set-Content -LiteralPath $isvcPath -Value $isvc -Encoding UTF8 -NoNewline
    Log ("  written (" + $isvc.Length + " chars)")
}

# ================================================================
# STEP 7: CollectionService.SetColorAsync
# ================================================================
Log "STEP 7: CollectionService"

$svc = Get-Content -LiteralPath $svcPath -Raw -Encoding UTF8
$nl = if ($svc.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($svc.Contains('public async Task SetColorAsync')) {
    Log "  already has SetColorAsync - skipping"
} else {
    $oldImpl = "    public Task DeleteAsync(string id, CancellationToken ct = default) => _repo.DeleteAsync(id, ct);"
    $newImpl = @'
    public Task DeleteAsync(string id, CancellationToken ct = default) => _repo.DeleteAsync(id, ct);

    public async Task SetColorAsync(string id, string? color, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(id)) return;
        var c = await _repo.GetAsync(id, ct);
        if (c == null) return;
        c.Color = string.IsNullOrWhiteSpace(color) ? null : color.Trim();
        await _repo.UpsertAsync(c, ct);
    }
'@
    $oldImpl = $oldImpl -replace "`r`n", $nl
    $newImpl = $newImpl -replace "`r`n", $nl
    $svc = Replace-Exact $svc $oldImpl $newImpl "CollectionService: SetColorAsync impl"
    Set-Content -LiteralPath $svcPath -Value $svc -Encoding UTF8 -NoNewline
    Log ("  written (" + $svc.Length + " chars)")
}

# ================================================================
# STEP 8: CollectionRow - full rewrite
# ================================================================
Log "STEP 8: CollectionRow full rewrite"

$row = Get-Content -LiteralPath $rowPath -Raw -Encoding UTF8

if ($row.Contains('public IBrush? ColorBrush')) {
    Log "  CollectionRow already rewritten - skipping"
} else {
    $rowContent = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class CollectionRow : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string Id { get; init; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public SmartCollectionFilter Filter { get; set; } = SmartCollectionFilter.Empty;
    public bool IsSmart { get; set; } = true;

    private string? _color;
    public string? Color
    {
        get => _color;
        set
        {
            if (_color == value) return;
            _color = value;
            Raise();
            Raise(nameof(ColorBrush));
            Raise(nameof(HasColor));
        }
    }

    public IBrush? ColorBrush => string.IsNullOrWhiteSpace(_color)
        ? null
        : (Avalonia.Media.Color.TryParse(_color, out var c) ? new SolidColorBrush(c) : null);

    public bool HasColor => ColorBrush != null;

    public static readonly IReadOnlyList<string> Palette = new[]
    {
        "#E67E22", "#E74C3C", "#F39C12", "#2ECC71",
        "#3498DB", "#9B59B6", "#95A5A6", "#34495E"
    };

    public Action<CollectionRow, string?>? OnColorChange { get; set; }

    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }

    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";

    public CollectionRow()
    {
        SetColorCommand = new RelayCommand(p =>
        {
            if (p is string s) OnColorChange?.Invoke(this, s);
        });
        ClearColorCommand = new RelayCommand(() => OnColorChange?.Invoke(this, null));
    }

    public static CollectionRow From(Collection c) => new()
    {
        Id = c.Id,
        Name = c.Name,
        Filter = CollectionService.DeserializeFilter(c.FilterQuery),
        IsSmart = c.IsSmart,
        Color = c.Color,
    };
}
'@
    $rowContent = $rowContent -replace "`r`n", "`n"
    Set-Content -LiteralPath $rowPath -Value $rowContent -Encoding UTF8 -NoNewline
    Log ("  written (" + $rowContent.Length + " chars)")
}

# ================================================================
# STEP 9: LibraryViewModel
# ================================================================
Log "STEP 9: LibraryViewModel"

$lib = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
$nl = if ($lib.Contains("`r`n")) { "`r`n" } else { "`n" }

# 9a. _tagDirectUsage field
if ($lib.Contains('_tagDirectUsage')) {
    Log "  9a already has _tagDirectUsage - skipping"
} else {
    $oldF = @'
    private string _groupRemoveMessage = string.Empty;

    private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);
'@
    $newF = @'
    private string _groupRemoveMessage = string.Empty;

    private readonly Dictionary<string, int> _tagDirectUsage = new(StringComparer.OrdinalIgnoreCase);

    private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);
'@
    $oldF = $oldF -replace "`r`n", $nl
    $newF = $newF -replace "`r`n", $nl
    $lib = Replace-Exact $lib $oldF $newF "LibraryViewModel: _tagDirectUsage field"
}

# 9b. Populate _tagDirectUsage in LoadTagsAsync
if ($lib.Contains('_tagDirectUsage.Clear();')) {
    Log "  9b already populates _tagDirectUsage - skipping"
} else {
    $oldPop = "            void SumUsage(TagNodeViewModel node)"
    $newPop = "            _tagDirectUsage.Clear();" + $nl + "            foreach (var t in tagUsages) _tagDirectUsage[t.Id] = t.UsageCount;" + $nl + $nl + "            void SumUsage(TagNodeViewModel node)"
    $lib = Replace-Exact $lib $oldPop $newPop "LibraryViewModel: populate _tagDirectUsage"
}

# 9c. OpenDeleteTagDialog - breakdown
if ($lib.Contains('int descendantsOnly')) {
    Log "  9c already has breakdown - skipping"
} else {
    $oldOpen = @'
    private void OpenDeleteTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _deleteTagTarget = node;
        var fmt = App.Loc?.Get("Library.DeleteTagDialog.Message") ?? "Delete tag {0}? Linked rows: {1}.";
        DeleteTagMessage = string.Format(fmt, node.Name, node.UsageCount);
        ShowDeleteTagConfirm = true;
    }
'@
    $newOpen = @'
    private void OpenDeleteTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _deleteTagTarget = node;
        int direct = _tagDirectUsage.TryGetValue(node.Id, out var d) ? d : node.UsageCount;
        int total = node.UsageCount;
        int descendantsOnly = Math.Max(0, total - direct);
        var fmt = App.Loc?.Get("Library.DeleteTagDialog.Message") ?? "Delete tag {0}? Directly tagged: {1}, in subtree (children): {2}.";
        DeleteTagMessage = string.Format(fmt, node.Name, direct, descendantsOnly);
        ShowDeleteTagConfirm = true;
    }
'@
    $oldOpen = $oldOpen -replace "`r`n", $nl
    $newOpen = $newOpen -replace "`r`n", $nl
    $lib = Replace-Exact $lib $oldOpen $newOpen "LibraryViewModel: OpenDeleteTagDialog breakdown"
}

# 9d. LoadCollectionsAsync - wire OnColorChange
if ($lib.Contains('row.OnColorChange = (r, col)')) {
    Log "  9d LoadCollections already wired - skipping"
} else {
    $oldLC = @'
            var all = await _collectionService.GetSmartAsync(ct);
            Collections.Clear();
            foreach (var c in all) Collections.Add(CollectionRow.From(c));
'@
    $newLC = @'
            var all = await _collectionService.GetSmartAsync(ct);
            Collections.Clear();
            foreach (var c in all)
            {
                var row = CollectionRow.From(c);
                row.OnColorChange = (r, col) => _ = ChangeCollectionColorAsync(r, col);
                Collections.Add(row);
            }
'@
    $oldLC = $oldLC -replace "`r`n", $nl
    $newLC = $newLC -replace "`r`n", $nl
    $lib = Replace-Exact $lib $oldLC $newLC "LibraryViewModel: LoadCollections wire OnColorChange"
}

# 9e. ChangeCollectionColorAsync method (insert before ChangeTagColorAsync)
if ($lib.Contains('ChangeCollectionColorAsync')) {
    Log "  9e already has ChangeCollectionColorAsync - skipping"
} else {
    $oldCT = "    public async Task ChangeTagColorAsync(TagNodeViewModel tag, string? color)"
    $newCT = @'
    public async Task ChangeCollectionColorAsync(CollectionRow row, string? color)
    {
        if (_collectionService == null || row == null || string.IsNullOrEmpty(row.Id)) return;
        try
        {
            await _collectionService.SetColorAsync(row.Id, color);
            row.Color = color;
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ChangeCollectionColorAsync failed", ex); }
    }

    public async Task ChangeTagColorAsync(TagNodeViewModel tag, string? color)
'@
    $oldCT = $oldCT -replace "`r`n", $nl
    $newCT = $newCT -replace "`r`n", $nl
    $lib = Replace-Exact $lib $oldCT $newCT "LibraryViewModel: ChangeCollectionColorAsync"
}

Set-Content -LiteralPath $libVmPath -Value $lib -Encoding UTF8 -NoNewline
Log ("  LibraryViewModel.cs written (" + $lib.Length + " chars)")

# post-write sanity
$libBack = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libBack.Contains('_tagDirectUsage')) "post-write: _tagDirectUsage missing"
Assert ($libBack.Contains('int descendantsOnly')) "post-write: descendantsOnly missing"
Assert ($libBack.Contains('row.OnColorChange = (r, col)')) "post-write: OnColorChange wiring missing"
Assert ($libBack.Contains('public async Task ChangeCollectionColorAsync')) "post-write: ChangeCollectionColorAsync missing"
Log "  post-write verify OK"

# ================================================================
# STEP 10: ModelCardPageViewModel - TagCandidates
# ================================================================
Log "STEP 10: ModelCardPageViewModel"

$mc = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
$nl = if ($mc.Contains("`r`n")) { "`r`n" } else { "`n" }

# 10a. Add TagCandidates collection
if ($mc.Contains('public ObservableCollection<string> TagCandidates')) {
    Log "  10a already has TagCandidates - skipping"
} else {
    $oldTC = @'
    public ObservableCollection<TagRowViewModel> TagRows { get; } = new();
    private string _newTagName = string.Empty;
'@
    $newTC = @'
    public ObservableCollection<TagRowViewModel> TagRows { get; } = new();
    public ObservableCollection<string> TagCandidates { get; } = new();
    private string _newTagName = string.Empty;
'@
    $oldTC = $oldTC -replace "`r`n", $nl
    $newTC = $newTC -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldTC $newTC "ModelCardPageViewModel: TagCandidates"
}

# 10b. RefreshTagCandidatesAsync method
if ($mc.Contains('private async Task RefreshTagCandidatesAsync')) {
    Log "  10b already has RefreshTagCandidatesAsync - skipping"
} else {
    $oldRT = "    private async Task AddTagAsync()"
    $newRT = @'
    private async Task RefreshTagCandidatesAsync(CancellationToken ct = default)
    {
        if (AppServices.TagService == null) return;
        try
        {
            var all = await AppServices.TagService.GetAllWithUsageAsync(ct);
            TagCandidates.Clear();
            foreach (var t in all) TagCandidates.Add(t.Name);
        }
        catch { }
    }

    private async Task AddTagAsync()
'@
    $oldRT = $oldRT -replace "`r`n", $nl
    $newRT = $newRT -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldRT $newRT "ModelCardPageViewModel: RefreshTagCandidatesAsync"
}

# 10c. Call in LoadAsync
if ($mc -match 'await RefreshTagCandidatesAsync\(ct\);') {
    Log "  10c already called in LoadAsync - skipping"
} else {
    $oldLA = @'
        await ReloadAssetsAsync(ct);
        await ReloadTagsAsync(ct);
        await ReloadIntegrationsAsync(ct);
'@
    $newLA = @'
        await ReloadAssetsAsync(ct);
        await ReloadTagsAsync(ct);
        await RefreshTagCandidatesAsync(ct);
        await ReloadIntegrationsAsync(ct);
'@
    $oldLA = $oldLA -replace "`r`n", $nl
    $newLA = $newLA -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldLA $newLA "ModelCardPageViewModel: LoadAsync refresh candidates"
}

# 10d. Call in AddTagAsync (after ReloadTagsAsync)
if ($mc -match 'await ReloadTagsAsync\(CancellationToken.None\);\s*await RefreshTagCandidatesAsync') {
    Log "  10d already called in AddTagAsync - skipping"
} else {
    $oldAdd = @'
            await AppServices.TagService.AddToModelAsync(Model.Id, NewTagName.Trim());
            NewTagName = string.Empty;
            await ReloadTagsAsync(CancellationToken.None);
        }
        catch { }
    }
'@
    $newAdd = @'
            await AppServices.TagService.AddToModelAsync(Model.Id, NewTagName.Trim());
            NewTagName = string.Empty;
            await ReloadTagsAsync(CancellationToken.None);
            await RefreshTagCandidatesAsync();
        }
        catch { }
    }
'@
    $oldAdd = $oldAdd -replace "`r`n", $nl
    $newAdd = $newAdd -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldAdd $newAdd "ModelCardPageViewModel: AddTagAsync refresh candidates"
}

Set-Content -LiteralPath $mcVmPath -Value $mc -Encoding UTF8 -NoNewline
Log ("  written (" + $mc.Length + " chars)")

$mcBack = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
Assert ($mcBack.Contains('public ObservableCollection<string> TagCandidates')) "post-write: TagCandidates missing"
Assert ($mcBack.Contains('private async Task RefreshTagCandidatesAsync')) "post-write: RefreshTagCandidatesAsync missing"
Assert ($mcBack.Contains('await RefreshTagCandidatesAsync(ct);')) "post-write: call missing"
Log "  post-write verify OK"

# ================================================================
# STEP 11: LibraryView.axaml - collections item template
# ================================================================
Log "STEP 11: LibraryView.axaml"

$ax = Get-Content -LiteralPath $libAxPath -Raw -Encoding UTF8
$nl = if ($ax.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($ax.Contains('Binding ColorBrush') -and $ax.Contains('ItemsSource="{Binding Collections}"') -and ($ax -match 'Collections[\s\S]{0,2000}ColorBrush')) {
    Log "  collections template already has color - skipping"
} else {
    $oldList = @'
                    <ListBox Grid.Row="3" ItemsSource="{Binding Collections}"
                             SelectedItem="{Binding SelectedCollection, Mode=TwoWay}"
                             Background="Transparent" BorderThickness="0"
                             MaxHeight="220">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding Name}" TextTrimming="CharacterEllipsis"
                                           VerticalAlignment="Center" Padding="4,2"/>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
'@
    $newList = @'
                    <ListBox Grid.Row="3" ItemsSource="{Binding Collections}"
                             SelectedItem="{Binding SelectedCollection, Mode=TwoWay}"
                             Background="Transparent" BorderThickness="0"
                             MaxHeight="220">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid ColumnDefinitions="Auto,*" Background="Transparent">
                                    <Grid.ContextMenu>
                                        <ContextMenu>
                                            <MenuItem Header="{Binding ClearColorLabel}" Command="{Binding ClearColorCommand}"/>
                                            <Separator/>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#E67E22">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#E67E22" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#E74C3C">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#E74C3C" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#F39C12">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#F39C12" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#2ECC71">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#2ECC71" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#3498DB">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#3498DB" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#9B59B6">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#9B59B6" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#95A5A6">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#95A5A6" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#34495E">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#34495E" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                        </ContextMenu>
                                    </Grid.ContextMenu>
                                    <Ellipse Grid.Column="0" Width="8" Height="8" Margin="4,0,6,0"
                                             VerticalAlignment="Center"
                                             Fill="{Binding ColorBrush}"
                                             IsVisible="{Binding HasColor}"/>
                                    <TextBlock Grid.Column="1" Text="{Binding Name}" TextTrimming="CharacterEllipsis"
                                               VerticalAlignment="Center" Padding="0,2"/>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
'@
    $oldList = $oldList -replace "`r`n", $nl
    $newList = $newList -replace "`r`n", $nl
    $ax = Replace-Exact $ax $oldList $newList "LibraryView: collections item template"
    Set-Content -LiteralPath $libAxPath -Value $ax -Encoding UTF8 -NoNewline
    Log ("  written (" + $ax.Length + " chars)")
}

# ================================================================
# STEP 12: ModelCardView.axaml - AutoCompleteBox
# ================================================================
Log "STEP 12: ModelCardView.axaml"

$mcAx = Get-Content -LiteralPath $mcAxPath -Raw -Encoding UTF8
$nl = if ($mcAx.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($mcAx.Contains('AutoCompleteBox Text="{Binding NewTagName}"')) {
    Log "  already AutoCompleteBox - skipping"
} else {
    $oldTag = '                                    <TextBox Text="{Binding NewTagName}" Watermark="{Binding TagPlaceholderText}" Width="200"/>'
    $newTag = '                                    <AutoCompleteBox Text="{Binding NewTagName}" Watermark="{Binding TagPlaceholderText}" ItemsSource="{Binding TagCandidates}" Width="200"/>'
    $mcAx = Replace-Exact $mcAx $oldTag $newTag "ModelCardView: AutoCompleteBox"
    Set-Content -LiteralPath $mcAxPath -Value $mcAx -Encoding UTF8 -NoNewline
    Log ("  written (" + $mcAx.Length + " chars)")
}

# ================================================================
# STEP 13: lang/en.json - DeleteTagDialog.Message 3-param
# ================================================================
Log "STEP 13: en.json"

$en = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8
if ($en.Contains('Directly tagged: {1}, in subtree (children): {2}')) {
    Log "  already 3-param - skipping"
} else {
    $oldEnMsg = '"Message":  "Delete tag {0}? Linked rows: {1}.",'
    $newEnMsg = '"Message":  "Delete tag {0}? Directly tagged: {1}, in subtree (children): {2}.",'
    $en = Replace-Exact $en $oldEnMsg $newEnMsg "en.json: DeleteTagDialog.Message"
    Set-Content -LiteralPath $enPath -Value $en -Encoding UTF8 -NoNewline
    try {
        Get-Content -LiteralPath $enPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  en.json written and parses OK"
    } catch { throw ("en.json invalid JSON: " + $_) }
}

# ================================================================
# STEP 14: lang/ru.json - DeleteTagDialog.Message 3-param (via \uXXXX)
# ================================================================
Log "STEP 14: ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

# Detect: after upgrade, RU message will contain \u043f\u0440\u044f\u043c\u043e (Прямо)
$ruMarker = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0J/RgNGP0LzQvg=='))  # "Прямо"
if ($ru.Contains($ruMarker)) {
    Log "  already 3-param - skipping"
} else {
    # Old value: "Удалить тег {0}? Связанных записей: {1}."
    # Encoded via \uXXXX, decode at runtime.
    $oldB64 = 'IiA6ICAi0KPQtNCw0LvQuNGC0Ywg0YLQtdCzIHswfT8g0KHRgtGP0LfQsNC90L3Ri9GFINC30LDQv9C40YHQtdC5OiB7MX0uIiw='
    $newB64 = 'IiA6ICAi0KPQtNCw0LvQuNGC0Ywg0YLQtdCzIHswfT8g0J/RgNGP0LzQviDQt9Cw0L/QuNGB0LXQudC90YvRhSDQv9GA0Y/QvNC+OiB7MX0sINCyINC/0L7QtNC00LXRgNC10LLQtSDQv9C+0YLQvtC80LrQvtCyOiB7Mn0uIiw='
    $oldMsg = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($oldB64))
    $newMsg = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($newB64))

    $cnt = [regex]::Matches($ru, [regex]::Escape($oldMsg)).Count
    Assert ($cnt -eq 1) ("ru.json: DeleteTagDialog.Message anchor matched $cnt times")
    $ru = $ru.Replace($oldMsg, $newMsg)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline
    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch { throw ("ru.json invalid JSON: " + $_) }
}

# ================================================================
# STEP 15: CHANGELOG.md
# ================================================================
Log "STEP 15: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6c applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6c - Tags / Collections polish

- Migration 0005: Collection.color column. Registered in DatabaseInitializer.
- Entities.Collection: Color string?. ICollectionService.SetColorAsync implemented in CollectionService.
- CollectionRepository: upsert + map color (FieldCount > 4 guard).
- CollectionRow: rewritten with INotifyPropertyChanged, Color, ColorBrush, HasColor, Palette (8 presets), SetColorCommand, ClearColorCommand, OnColorChange callback.
- LibraryViewModel: _tagDirectUsage dict (populated in LoadTagsAsync); DeleteTagDialog shows "directly tagged: N, in subtree: M"; LoadCollectionsAsync wires OnColorChange; ChangeCollectionColorAsync.
- ModelCardPageViewModel: TagCandidates (ObservableCollection<string>) + RefreshTagCandidatesAsync (called in LoadAsync and AddTagAsync).
- LibraryView.axaml: collections ListBox item template gets color dot + context menu (8 preset swatches + Clear color).
- ModelCardView.axaml: New tag TextBox -> AutoCompleteBox (ItemsSource=TagCandidates).
- lang/en.json + lang/ru.json: Library.DeleteTagDialog.Message -> 3-param format (name, direct, descendants).
<!-- patch 0.5.6c applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build + test + run; then 0.5.7 (version bump 0.1.2 -> 0.1.3, HANDOFF sync, release prep)" -ForegroundColor Cyan