# patch_0.5.2d.ps1 - Save Filter dialog + HANDOFF sync
# Requires 0.5.2c applied. One logical step. No DB migrations.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.2d'
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
        if ($cnt -gt 1) { throw ("Anchor ambiguous ({0}): {1}" -f $cnt, $p.Label) }
        $c = $c.Replace($old, $new)
        Write-Log ("  replaced: {0}" -f $p.Label)
    }
    if ($hadCrLf) { $c = $c.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $c, $utf8NoBom)
}

function Chars([int[]]$codes) { -join ([char[]]$codes) }

Write-Log ("Patch {0} started" -f $Version)

# ---------- 0. Pre-flight ----------
$axamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$libVmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$enPath    = Join-Path $ProjectRoot 'lang\en.json'
$ruPath    = Join-Path $ProjectRoot 'lang\ru.json'
$handPath  = Join-Path $ProjectRoot 'docs\HANDOFF.md'
$chPath    = Join-Path $ProjectRoot 'CHANGELOG.md'

foreach ($p in @($axamlPath, $libVmPath, $enPath, $ruPath, $handPath, $chPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ("Required file missing: {0}" -f $p) }
}

$libVmCheck = [IO.File]::ReadAllText($libVmPath, $utf8NoBom)
if ($libVmCheck -notmatch 'SaveCurrentFilterAsCollectionCommand') { throw 'Pre-flight failed: LibraryViewModel.cs does not contain 0.5.2b changes. Apply 0.5.2b first.' }
if ($libVmCheck -notmatch 'OpenSaveFilterDialog') { Write-Log 'Pre-flight: 0.5.2d not yet applied (OpenSaveFilterDialog not found).' } else { throw 'Pre-flight: OpenSaveFilterDialog already present. 0.5.2d already applied.' }

$enCheck = [IO.File]::ReadAllText($enPath, $utf8NoBom)
if ($enCheck -notmatch '"SaveFilterDialog"') { Write-Log 'Pre-flight: en.json has no SaveFilterDialog yet.' } else { throw 'Pre-flight: en.json already has SaveFilterDialog. 0.5.2d already applied.' }

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
    'src\MiniCodex.App\Views\LibraryView.axaml',
    'lang\en.json',
    'lang\ru.json',
    'docs\HANDOFF.md',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src    = Join-Path $ProjectRoot $rel
    $dst    = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. LibraryViewModel.cs - 5 edits ----------
$libPairs = @(
    @{
        Label = 'add dialog fields after _deleteCollectionCommand'
        Old = '    private readonly RelayCommand _deleteCollectionCommand;'
        New = @'
    private readonly RelayCommand _deleteCollectionCommand;
    private bool _showSaveFilterDialog;
    private string _newCollectionName = string.Empty;
'@
    },
    @{
        Label = 'add dialog properties after DuplicatesButtonText'
        Old = '    public string DuplicatesButtonText => ShowDuplicatesOnly ? (App.Loc?.Get("Library.ShowAll") ?? "Show all") : (App.Loc?.Get("Library.FindDuplicates") ?? "Find duplicates");'
        New = @'
    public string DuplicatesButtonText => ShowDuplicatesOnly ? (App.Loc?.Get("Library.ShowAll") ?? "Show all") : (App.Loc?.Get("Library.FindDuplicates") ?? "Find duplicates");

    public bool ShowSaveFilterDialog
    {
        get => _showSaveFilterDialog;
        set { if (_showSaveFilterDialog == value) return; _showSaveFilterDialog = value; Raise(); }
    }
    public string NewCollectionName
    {
        get => _newCollectionName;
        set { if (_newCollectionName == value) return; _newCollectionName = value; Raise(); }
    }
    public string SaveFilterDialogTitle => App.Loc?.Get("Library.SaveFilterDialog.Title") ?? "Name your collection";
    public string SaveFilterDialogPlaceholder => App.Loc?.Get("Library.SaveFilterDialog.Placeholder") ?? "Collection name";
    public string SaveFilterDialogSaveText => App.Loc?.Get("Library.SaveFilterDialog.Save") ?? "Save";
    public string SaveFilterDialogCancelText => App.Loc?.Get("Library.SaveFilterDialog.Cancel") ?? "Cancel";
'@
    },
    @{
        Label = 'add commands after DeleteCollectionCommand'
        Old = '    public ICommand DeleteCollectionCommand => _deleteCollectionCommand;'
        New = @'
    public ICommand DeleteCollectionCommand => _deleteCollectionCommand;
    public ICommand ConfirmSaveFilterCommand { get; }
    public ICommand CancelSaveFilterCommand { get; }
'@
    },
    @{
        Label = 'rewire SaveCurrentFilterAsCollectionCommand in ctor'
        Old = '        SaveCurrentFilterAsCollectionCommand = new RelayCommand(() => _ = SaveCurrentFilterAsync(null));'
        New = @'
        SaveCurrentFilterAsCollectionCommand = new RelayCommand(() => OpenSaveFilterDialog());
        ConfirmSaveFilterCommand = new RelayCommand(() => _ = ConfirmSaveFilterAsync());
        CancelSaveFilterCommand = new RelayCommand(CancelSaveFilter);
'@
    },
    @{
        Label = 'insert dialog helper methods before SaveCurrentFilterAsync'
        Old = '    public async Task SaveCurrentFilterAsync(string? name)'
        New = @'
    private void OpenSaveFilterDialog()
    {
        var tag = _selectedTag;
        var filter = new SmartCollectionFilter(
            string.IsNullOrWhiteSpace(_searchQuery) ? null : _searchQuery.Trim(),
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Id,
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Name);
        if (filter.IsEmpty)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.SaveFilterEmpty") ?? "Filter is empty - set a search or a tag first.");
            return;
        }
        NewCollectionName = string.IsNullOrEmpty(tag?.Name)
            ? ("Filter " + DateTime.Now.ToString("HH:mm"))
            : tag!.Name;
        ShowSaveFilterDialog = true;
    }

    private async Task ConfirmSaveFilterAsync()
    {
        var name = NewCollectionName;
        ShowSaveFilterDialog = false;
        await SaveCurrentFilterAsync(name);
    }

    private void CancelSaveFilter()
    {
        ShowSaveFilterDialog = false;
    }

    public async Task SaveCurrentFilterAsync(string? name)
'@
    }
)
Replace-Exact $libVmPath $libPairs
Write-Log ("Updated: {0}" -f $libVmPath)

# ---------- 3. LibraryView.axaml - add dialog overlay ----------
$axamlPairs = @(
    @{
        Label = 'append Save Filter dialog overlay'
        Old = @'
        </Border>
    </Panel>
</UserControl>
'@
        New = @'
        </Border>

        <Border IsVisible="{Binding ShowSaveFilterDialog}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="440"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding SaveFilterDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBox Text="{Binding NewCollectionName, Mode=TwoWay}"
                             Watermark="{Binding SaveFilterDialogPlaceholder}"
                             MinWidth="320"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding SaveFilterDialogCancelText}" Command="{Binding CancelSaveFilterCommand}" Padding="14,8"/>
                        <Button Content="{Binding SaveFilterDialogSaveText}" Command="{Binding ConfirmSaveFilterCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>
    </Panel>
</UserControl>
'@
    }
)
Replace-Exact $axamlPath $axamlPairs
Write-Log ("Updated: {0}" -f $axamlPath)

# ---------- 4. Lang: insert SaveFilterDialog object per file ----------
function Insert-DialogKeys([string]$path, [hashtable]$vals) {
    $lines = [IO.File]::ReadAllLines($path, $utf8NoBom)
    $out   = New-Object System.Collections.Generic.List[string]
    $inserted = $false
    foreach ($line in $lines) {
        $out.Add($line)
        if (-not $inserted -and $line -match '^\s*"SaveFilterEmpty"\s*:') {
            $indent = ($line -replace '^(\s*).*$', '$1')
            $out.Add($indent + '"SaveFilterDialog":  {')
            $out.Add($indent + '    "Title":  "' + $vals.Title + '",')
            $out.Add($indent + '    "Placeholder":  "' + $vals.Placeholder + '",')
            $out.Add($indent + '    "Save":  "' + $vals.Save + '",')
            $out.Add($indent + '    "Cancel":  "' + $vals.Cancel + '"')
            $out.Add($indent + '},')
            $inserted = $true
        }
    }
    if (-not $inserted) { throw ("SaveFilterEmpty anchor not found in {0}" -f $path) }
    [IO.File]::WriteAllLines($path, $out, $utf8NoBom)
    $null = [IO.File]::ReadAllText($path, $utf8NoBom) | ConvertFrom-Json
    Write-Log ("Updated + JSON OK: {0}" -f $path)
}

Insert-DialogKeys $enPath @{
    Title       = 'Name your collection'
    Placeholder = 'Collection name'
    Save        = 'Save'
    Cancel      = 'Cancel'
}

$ruTitle       = Chars @(0x41D,0x430,0x437,0x432,0x430,0x43D,0x438,0x435,0x20,0x43A,0x43E,0x43B,0x43B,0x435,0x43A,0x446,0x438,0x438)
$ruPlaceholder = Chars @(0x412,0x432,0x435,0x434,0x438,0x442,0x435,0x20,0x438,0x43C,0x44F)
$ruSave        = Chars @(0x421,0x43E,0x445,0x440,0x430,0x43D,0x438,0x442,0x44C)
$ruCancel      = Chars @(0x41E,0x442,0x43C,0x435,0x43D,0x430)

Insert-DialogKeys $ruPath @{
    Title       = $ruTitle
    Placeholder = $ruPlaceholder
    Save        = $ruSave
    Cancel      = $ruCancel
}

# ---------- 5. HANDOFF.md: lesson 11 + section 19 ----------
$handPairs = @(
    @{
        Label = 'HANDOFF lesson 11'
        Old = '10. **Event signatures in code-behind** - DragEventArgs for DragDrop.Drop and DragDrop.DragOver. Not RoutedEventArgs.'
        New = @'
10. **Event signatures in code-behind** - DragEventArgs for DragDrop.Drop and DragDrop.DragOver. Not RoutedEventArgs.

11. **String.Split(string) does not exist in PS 5.1** - it silently binds to Split(char[]), so "abc".Split("b") iterates chars and returns 3 pieces, not 2. For occurrence counting use: [regex]::Matches($text, [regex]::Escape($anchor)).Count. Symptom: "Anchor ambiguous (14782 occurrences)" for a 45-char string. Cost: one lost patch run in 0.5.2b. If you write a custom Replace-Exact helper (recommended), always validate anchor count == 1 before replacing.
'@
    },
    @{
        Label = 'HANDOFF section 19'
        Old = '<!-- patch 0.5.1a39 applied -->'
        New = @'
<!-- patch 0.5.1a39 applied -->

---

## 19. Session 2026-11-13 evening - Smart Collections (v0.5.2a..d)

### 19.1 What was added
- **0.5.2a** backend: SmartCollectionFilter DTO (Core.Models), ICollectionService + CollectionService (Core.Services), ITagService.SetColorAsync, AppServices.CollectionService wiring, CollectionServiceTests (5 tests). Tests 50 -> 55.
- **0.5.2b** ViewModels: CollectionRow.cs; TagNodeViewModel gains Color/ColorBrush/HasColor/static Palette (8 hex)/SetColorCommand/ClearColorCommand/OnColorChange; LibraryViewModel gains Collections/SelectedCollection/commands/LoadCollectionsAsync/SaveCurrentFilterAsync/DeleteCollectionAsync/ChangeTagColorAsync/ApplyCollectionAsync/FindTagById and 7th optional ICollectionService ctor param; MainWindowViewModel passes AppServices.CollectionService.
- **0.5.2c** UI: LibraryView.axaml Collections section (header + delete button + ListBox) under the tag tree; per-tag color dot + 8-swatch context menu + Clear in TreeDataTemplate; Save filter button in toolbar. TagNodeViewModel.ClearColorLabel. lang/en.json + lang/ru.json +5 keys each.
- **0.5.2d** Save Filter dialog: LibraryViewModel.ShowSaveFilterDialog/NewCollectionName/ConfirmSaveFilterCommand/CancelSaveFilterCommand/OpenSaveFilterDialog/ConfirmSaveFilterAsync/CancelSaveFilter; LibraryView.axaml overlay dialog; lang +4 keys per file (SaveFilterDialog.Title/Placeholder/Save/Cancel); HANDOFF lesson 11 (String.Split) + this section.

### 19.2 SmartCollectionFilter format
JSON: {"Search":"...","TagId":"...","TagName":"..."}. Stored in Collection.filter_query; Collection.is_smart = 1. CollectionService.DeserializeFilter is null-safe and returns SmartCollectionFilter.Empty on bad JSON. SaveSmartAsync matches existing by name OrdinalIgnoreCase -> upsert (no duplicates by name).

### 19.3 Known limitations of the 0.5.2 series
- Tag color picker is a fixed 8-color palette (TagNodeViewModel.Palette). No custom hex input yet.
- Smart Collection stores single TagId, not subtree. Filtering by a parent tag already includes descendants (LibraryViewModel.FilterTagIds uses GetDescendantIds), so if the collection references a parent tag, subtree filtering works.
- Saving a filter while a collection is selected reads current UI state (_searchQuery/_selectedTag), not SelectedCollection.Filter. Re-saving with the same name overwrites (upsert).
- Right-click on an unselected tag also selects it (Avalonia default TreeView behavior) -> filter applies before the context menu opens. Works fine but unexpected; if it becomes a nuisance, handle ContextRequested with e.Handled = true (deferred to 0.5.3).

### 19.4 Next steps
1. v0.1.2 release if 55 tests green.
2. Deferred to 0.5.3: tag rename/delete UI, custom hex color picker, per-tag subtree saved as collection.
3. Deferred to v1.1: bulk tag editing, multi-select grid, printer bed fit check.
'@
    }
)
Replace-Exact $handPath $handPairs
Write-Log ("Updated: {0}" -f $handPath)

# ---------- 6. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.2d applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.2d - Save Filter dialog + HANDOFF sync' + $nl + $nl +
        '- LibraryViewModel: ShowSaveFilterDialog, NewCollectionName, SaveFilterDialog{Title,Placeholder,SaveText,CancelText}, OpenSaveFilterDialog, ConfirmSaveFilterAsync, CancelSaveFilter, ConfirmSaveFilterCommand, CancelSaveFilterCommand. SaveCurrentFilterAsCollectionCommand now opens the dialog instead of saving with placeholder name.' + $nl +
        '- LibraryView.axaml: modal overlay dialog (name + Save/Cancel) matching the ShowScanWarning style.' + $nl +
        '- lang/en.json + lang/ru.json: SaveFilterDialog block (4 keys each).' + $nl +
        '- HANDOFF.md: added lesson 11 (String.Split pitfall), added section 19 (0.5.2 series state).' + $nl + $nl +
        '<!-- patch 0.5.2d applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next: build + test + run'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)