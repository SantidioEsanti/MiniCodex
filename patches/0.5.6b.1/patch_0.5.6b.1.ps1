# patch_0.5.6b.1.ps1
# 0.5.6b.1 - Multi-select: backend + ViewModel
#   1. ModelCardViewModel.IsSelected (bool, Raise).
#   2. LibraryViewModel: SelectedCards, GroupTagCandidates, selection state,
#      helpers (OnCardClicked/ClearSelection/SelectAllVisible), group commands
#      (Add tag / Remove / Copy paths / Find duplicates in selection), dialog state.
#      Group "Add to collection" deferred to 0.5.6c (needs manual-collection type).
#   3. lang/en.json + lang/ru.json: Library.GroupTagDialog / GroupRemoveDialog / Group.
#   XAML + PointerPressed wiring: 0.5.6b.2.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6b.1\patch_0.5.6b.1.ps1"

Write-Host "=== MiniCodex patch 0.5.6b.1 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6b.1'
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

$mcVmPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs'
$libVmPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$enPath   = Join-Path $projectRoot 'lang\en.json'
$ruPath   = Join-Path $projectRoot 'lang\ru.json'
$clPath   = Join-Path $projectRoot 'CHANGELOG.md'

Assert (Test-Path $mcVmPath) ("Missing: " + $mcVmPath)
Assert (Test-Path $libVmPath) ("Missing: " + $libVmPath)
Assert (Test-Path $enPath) ("Missing: " + $enPath)
Assert (Test-Path $ruPath) ("Missing: " + $ruPath)

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs',
    'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
    'lang\en.json',
    'lang\ru.json',
    'CHANGELOG.md')) {
    $src = Join-Path $projectRoot $rel
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir $rel
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log ("  backup: " + $rel)
    }
}

# ================================================================
# STEP 2: ModelCardViewModel - add IsSelected
# ================================================================
Log "STEP 2: ModelCardViewModel.IsSelected"

$mc = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
$nl = if ($mc.Contains("`r`n")) { "`r`n" } else { "`n" }

Assert (-not $mc.Contains('IsSelected')) "ModelCardViewModel already has IsSelected"

$oldBlock = @"
    public bool IsHovered
    {
        get => _isHovered;
        set { if (_isHovered != value) { _isHovered = value; Raise(); } }
    }
"@
$newBlock = @"
    public bool IsHovered
    {
        get => _isHovered;
        set { if (_isHovered != value) { _isHovered = value; Raise(); } }
    }

    // --- multi-select (0.5.6b.1) ---
    private bool _isSelected;
    public bool IsSelected
    {
        get => _isSelected;
        set { if (_isSelected != value) { _isSelected = value; Raise(); } }
    }
"@
$oldBlock = $oldBlock -replace "`r`n", $nl
$newBlock = $newBlock -replace "`r`n", $nl
$mc = Replace-Exact $mc $oldBlock $newBlock "ModelCardViewModel: IsSelected"

Set-Content -LiteralPath $mcVmPath -Value $mc -Encoding UTF8 -NoNewline
Log ("  written (" + $mc.Length + " chars)")

# ================================================================
# STEP 3: LibraryViewModel - fields
# ================================================================
Log "STEP 3: LibraryViewModel - fields"

$lib = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
$nl = if ($lib.Contains("`r`n")) { "`r`n" } else { "`n" }

Assert (-not $lib.Contains('_showGroupTagDialog')) "LibraryViewModel already has multi-select fields"

$oldFields = "    private TagNodeViewModel? _colorPickerTagTarget;"
$newFields = @"
    private TagNodeViewModel? _colorPickerTagTarget;

    // --- multi-select (0.5.6b.1) ---
    private int _lastClickedIndex = -1;
    private bool _showGroupTagDialog;
    private string _groupTagName = string.Empty;
    private bool _showGroupRemoveConfirm;
    private string _groupRemoveMessage = string.Empty;
"@
$newFields = $newFields -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldFields $newFields "LibraryViewModel: fields"

# ================================================================
# STEP 4: LibraryViewModel - collections
# ================================================================
Log "STEP 4: LibraryViewModel - collections"

$oldColl = "    public ObservableCollection<CollectionRow> Collections { get; } = new();"
$newColl = @"
    public ObservableCollection<CollectionRow> Collections { get; } = new();
    public ObservableCollection<ModelCardViewModel> SelectedCards { get; } = new();
    public ObservableCollection<string> GroupTagCandidates { get; } = new();
"@
$newColl = $newColl -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldColl $newColl "LibraryViewModel: collections"

# ================================================================
# STEP 5: LibraryViewModel - command declarations
# ================================================================
Log "STEP 5: LibraryViewModel - command declarations"

$oldCmd = @"
    public ICommand ConfirmColorPickerCommand { get; }
    public ICommand CancelColorPickerCommand { get; }
"@
$newCmd = @"
    public ICommand ConfirmColorPickerCommand { get; }
    public ICommand CancelColorPickerCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand SelectAllVisibleCommand { get; }
    public ICommand GroupAddTagCommand { get; }
    public ICommand GroupRemoveCommand { get; }
    public ICommand GroupCopyPathsCommand { get; }
    public ICommand GroupFindDuplicatesCommand { get; }
    public ICommand ConfirmGroupTagCommand { get; }
    public ICommand CancelGroupTagCommand { get; }
    public ICommand ConfirmGroupRemoveCommand { get; }
    public ICommand CancelGroupRemoveCommand { get; }
"@
$oldCmd = $oldCmd -replace "`r`n", $nl
$newCmd = $newCmd -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldCmd $newCmd "LibraryViewModel: command decls"

# ================================================================
# STEP 6: LibraryViewModel - command init in ctor
# ================================================================
Log "STEP 6: LibraryViewModel - command init"

$oldInit = "            () => SelectedCollection != null);"
$newInit = @"
            () => SelectedCollection != null);

        // --- multi-select (0.5.6b.1) ---
        ClearSelectionCommand = new RelayCommand(ClearSelection);
        SelectAllVisibleCommand = new RelayCommand(SelectAllVisible);
        GroupAddTagCommand = new RelayCommand(() => OpenGroupAddTagDialog());
        GroupRemoveCommand = new RelayCommand(() => OpenGroupRemoveDialog());
        GroupCopyPathsCommand = new RelayCommand(() => _ = GroupCopyPathsAsync());
        GroupFindDuplicatesCommand = new RelayCommand(() => _ = GroupFindDuplicatesAsync());
        ConfirmGroupTagCommand = new RelayCommand(() => _ = GroupAddTagAsync());
        CancelGroupTagCommand = new RelayCommand(() => { ShowGroupTagDialog = false; GroupTagName = string.Empty; });
        ConfirmGroupRemoveCommand = new RelayCommand(() => _ = GroupRemoveAsync());
        CancelGroupRemoveCommand = new RelayCommand(() => { ShowGroupRemoveConfirm = false; });
"@
$newInit = $newInit -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldInit $newInit "LibraryViewModel: ctor command init"

# ================================================================
# STEP 7: LibraryViewModel - selection reset in ReloadModelsCoreAsync
# ================================================================
Log "STEP 7: LibraryViewModel - selection reset on reload"

$oldReset = "            Cards.Clear();"
$newReset = @"
            Cards.Clear();
            _lastClickedIndex = -1;
            SelectedCards.Clear();
            Raise(nameof(SelectedCount));
            Raise(nameof(HasSelection));
            Raise(nameof(IsMultiSelection));
"@
$oldReset = $oldReset -replace "`r`n", $nl
$newReset = $newReset -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldReset $newReset "LibraryViewModel: reload selection reset"

# ================================================================
# STEP 8: LibraryViewModel - property/method block before LoadAsync
# ================================================================
Log "STEP 8: LibraryViewModel - multi-select block"

$oldLoad = "    public async Task LoadAsync(CancellationToken ct = default)"
$newBlock = @"
    // ============================================================
    // Multi-select (0.5.6b.1)
    // ============================================================
    public int SelectedCount => SelectedCards.Count;
    public bool HasSelection => SelectedCards.Count > 0;
    public bool IsMultiSelection => SelectedCards.Count > 1;

    public bool ShowGroupTagDialog
    {
        get => _showGroupTagDialog;
        set { if (_showGroupTagDialog == value) return; _showGroupTagDialog = value; Raise(); }
    }
    public string GroupTagName
    {
        get => _groupTagName;
        set { if (_groupTagName == value) return; _groupTagName = value; Raise(); }
    }
    public string GroupTagDialogTitle => App.Loc?.Get("Library.GroupTagDialog.Title") ?? "Add tag to selection";
    public string GroupTagDialogPlaceholder => App.Loc?.Get("Library.GroupTagDialog.Placeholder") ?? "Tag name";
    public string GroupTagDialogAddText => App.Loc?.Get("Library.GroupTagDialog.Add") ?? "Add";
    public string GroupTagDialogCancelText => App.Loc?.Get("Library.GroupTagDialog.Cancel") ?? "Cancel";

    public bool ShowGroupRemoveConfirm
    {
        get => _showGroupRemoveConfirm;
        set { if (_showGroupRemoveConfirm == value) return; _showGroupRemoveConfirm = value; Raise(); }
    }
    public string GroupRemoveMessage
    {
        get => _groupRemoveMessage;
        private set { if (_groupRemoveMessage == value) return; _groupRemoveMessage = value; Raise(); }
    }
    public string GroupRemoveDialogTitle => App.Loc?.Get("Library.GroupRemoveDialog.Title") ?? "Remove models?";
    public string GroupRemoveDialogRemoveText => App.Loc?.Get("Library.GroupRemoveDialog.Remove") ?? "Remove";
    public string GroupRemoveDialogCancelText => App.Loc?.Get("Library.GroupRemoveDialog.Cancel") ?? "Cancel";

    public string GroupAddTagMenuText => App.Loc?.Get("Library.Group.AddTag") ?? "Add tag to selected";
    public string GroupRemoveMenuText => App.Loc?.Get("Library.Group.Remove") ?? "Remove selected";
    public string GroupCopyPathsMenuText => App.Loc?.Get("Library.Group.CopyPaths") ?? "Copy paths of selected";
    public string GroupFindDuplicatesMenuText => App.Loc?.Get("Library.Group.FindDuplicates") ?? "Find duplicates in selection";
    public string GroupSelectionStatusFormat => App.Loc?.Get("Library.Group.SelectionCount") ?? "Selected: {0}";

    public void ClearSelection()
    {
        foreach (var c in Cards) c.IsSelected = false;
        _lastClickedIndex = -1;
        RefreshSelectionCollections();
    }

    public void SelectAllVisible()
    {
        foreach (var c in Cards) c.IsSelected = true;
        _lastClickedIndex = Cards.Count - 1;
        RefreshSelectionCollections();
    }

    // Public entry point for code-behind (0.5.6b.2): handles plain / Ctrl / Shift clicks.
    public void OnCardClicked(ModelCardViewModel card, bool isCtrl, bool isShift)
    {
        if (card == null) return;
        int idx = Cards.IndexOf(card);
        if (idx < 0) return;

        if (isShift && _lastClickedIndex >= 0 && _lastClickedIndex < Cards.Count)
        {
            var from = Math.Min(_lastClickedIndex, idx);
            var to = Math.Max(_lastClickedIndex, idx);
            foreach (var c in Cards) c.IsSelected = false;
            for (int i = from; i <= to; i++) Cards[i].IsSelected = true;
        }
        else if (isCtrl)
        {
            card.IsSelected = !card.IsSelected;
            _lastClickedIndex = idx;
        }
        else
        {
            foreach (var c in Cards) c.IsSelected = false;
            card.IsSelected = true;
            _lastClickedIndex = idx;
        }
        RefreshSelectionCollections();
    }

    private void RefreshSelectionCollections()
    {
        SelectedCards.Clear();
        foreach (var c in Cards) if (c.IsSelected) SelectedCards.Add(c);
        Raise(nameof(SelectedCount));
        Raise(nameof(HasSelection));
        Raise(nameof(IsMultiSelection));
    }

    private void RefreshGroupTagCandidates()
    {
        GroupTagCandidates.Clear();
        void AddRec(TagNodeViewModel node)
        {
            if (!string.IsNullOrEmpty(node.Id)) GroupTagCandidates.Add(node.Name);
            foreach (var child in node.Children) AddRec(child);
        }
        foreach (var t in Tags) AddRec(t);
    }

    private void OpenGroupAddTagDialog()
    {
        if (SelectedCards.Count == 0) return;
        RefreshGroupTagCandidates();
        GroupTagName = string.Empty;
        ShowGroupTagDialog = true;
    }

    private async Task GroupAddTagAsync()
    {
        if (_tagService == null || SelectedCards.Count == 0) return;
        var name = (_groupTagName ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(name)) return;
        try
        {
            int count = 0;
            foreach (var card in SelectedCards.ToList())
            {
                try { await _tagService.AddToModelAsync(card.Model.Id, name); count++; } catch { }
            }
            ShowGroupTagDialog = false;
            GroupTagName = string.Empty;
            var fmt = App.Loc?.Get("Library.Group.TagAppliedFormat") ?? "Applied tag to {0} models";
            SetStatus(StatusState.Scanning, 0, string.Format(fmt, count));
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupAddTag failed", ex); }
    }

    private void OpenGroupRemoveDialog()
    {
        if (SelectedCards.Count == 0) return;
        var fmt = App.Loc?.Get("Library.GroupRemoveDialog.Message") ?? "Remove {0} models from library? This cannot be undone.";
        GroupRemoveMessage = string.Format(fmt, SelectedCards.Count);
        ShowGroupRemoveConfirm = true;
    }

    private async Task GroupRemoveAsync()
    {
        if (_models == null || SelectedCards.Count == 0) return;
        var cards = SelectedCards.ToList();
        try
        {
            foreach (var card in cards)
            {
                try { await _models.DeleteAsync(card.Model.Id); } catch { }
            }
            foreach (var card in cards) Cards.Remove(card);
            ClearSelection();
            ShowGroupRemoveConfirm = false;
            SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
            Raise(nameof(IsEmpty));
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupRemove failed", ex); }
    }

    private async Task GroupCopyPathsAsync()
    {
        if (_files == null || SelectedCards.Count == 0) return;
        var paths = new List<string>();
        foreach (var card in SelectedCards)
        {
            try
            {
                var fs = await _files.GetByModelAsync(card.Model.Id);
                var primary = fs.FirstOrDefault(f => f.Id == card.Model.PrimaryModelFileId) ?? fs.FirstOrDefault();
                if (primary?.Path != null) paths.Add(primary.Path);
            }
            catch { }
        }
        if (paths.Count == 0) return;
        try
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop
                && desktop.MainWindow?.Clipboard != null)
            {
                await desktop.MainWindow.Clipboard.SetTextAsync(string.Join(Environment.NewLine, paths));
                var fmt = App.Loc?.Get("Library.Group.CopiedFormat") ?? "Copied {0} paths";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, paths.Count));
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupCopyPaths failed", ex); }
    }

    private async Task GroupFindDuplicatesAsync()
    {
        if (_files == null || SelectedCards.Count == 0) return;
        var hashToModels = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var card in SelectedCards)
        {
            try
            {
                var fs = await _files.GetByModelAsync(card.Model.Id);
                foreach (var f in fs)
                {
                    if (string.IsNullOrEmpty(f.FileHash)) continue;
                    if (!hashToModels.TryGetValue(f.FileHash, out var list))
                    {
                        list = new List<string>();
                        hashToModels[f.FileHash] = list;
                    }
                    if (!list.Contains(card.Model.Id)) list.Add(card.Model.Id);
                }
            }
            catch { }
        }
        var dupIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in hashToModels)
            if (kv.Value.Count > 1)
                foreach (var id in kv.Value) dupIds.Add(id);
        if (dupIds.Count == 0)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Group.NoDuplicates") ?? "No duplicates found in selection");
            return;
        }
        var toRemove = Cards.Where(c => !dupIds.Contains(c.Model.Id)).ToList();
        foreach (var c in toRemove) Cards.Remove(c);
        ClearSelection();
        SetStatus(StatusState.ModelCount, Cards.Count);
        Raise(nameof(IsEmpty));
    }

    public async Task LoadAsync(CancellationToken ct = default)
"@
$newBlock = $newBlock -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldLoad $newBlock "LibraryViewModel: multi-select block"

# ================================================================
# STEP 9: LibraryViewModel - RefreshLocalized additions
# ================================================================
Log "STEP 9: LibraryViewModel - RefreshLocalized"

$oldRL = @"
        foreach (var t in Tags) t.RefreshLocalized();
        foreach (var c in Cards) c.RefreshLocalized();
        UpdatePreviewsStatus();
"@
$newRL = @"
        foreach (var t in Tags) t.RefreshLocalized();
        foreach (var c in Cards) c.RefreshLocalized();
        Raise(nameof(GroupTagDialogTitle));
        Raise(nameof(GroupTagDialogPlaceholder));
        Raise(nameof(GroupTagDialogAddText));
        Raise(nameof(GroupTagDialogCancelText));
        Raise(nameof(GroupRemoveDialogTitle));
        Raise(nameof(GroupRemoveDialogRemoveText));
        Raise(nameof(GroupRemoveDialogCancelText));
        Raise(nameof(GroupAddTagMenuText));
        Raise(nameof(GroupRemoveMenuText));
        Raise(nameof(GroupCopyPathsMenuText));
        Raise(nameof(GroupFindDuplicatesMenuText));
        Raise(nameof(GroupSelectionStatusFormat));
        UpdatePreviewsStatus();
"@
$oldRL = $oldRL -replace "`r`n", $nl
$newRL = $newRL -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldRL $newRL "LibraryViewModel: RefreshLocalized"

Set-Content -LiteralPath $libVmPath -Value $lib -Encoding UTF8 -NoNewline
Log ("  LibraryViewModel.cs written (" + $lib.Length + " chars)")

# post-write sanity
$libBack = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libBack.Contains('public ObservableCollection<ModelCardViewModel> SelectedCards')) "post-write: SelectedCards missing"
Assert ($libBack.Contains('public void OnCardClicked(ModelCardViewModel card, bool isCtrl, bool isShift)')) "post-write: OnCardClicked missing"
Assert ($libBack.Contains('public void ClearSelection()')) "post-write: ClearSelection missing"
Assert ($libBack.Contains('public void SelectAllVisible()')) "post-write: SelectAllVisible missing"
$groupCmdCount = 0
foreach ($n in @('GroupAddTagCommand','GroupRemoveCommand','GroupCopyPathsCommand','GroupFindDuplicatesCommand')) {
    if ($libBack.Contains($n)) { $groupCmdCount++ }
}
Assert ($groupCmdCount -eq 4) ("post-write: expected 4 group commands, found $groupCmdCount")
Log "  post-write verify OK"

# ================================================================
# STEP 10: lang/en.json
# ================================================================
Log "STEP 10: lang/en.json"

$en = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8

if ($en.Contains('"GroupTagDialog"')) {
    Log "  en.json already has GroupTagDialog - skipping"
} else {
    $enOld = @"
                    "ColorPickerDialog":  {
                        "Title":  "Custom color",
                        "Placeholder":  "#RRGGBB",
                        "Save":  "Save",
                        "Cancel":  "Cancel"
                    }
                },
    "Card":  {
"@
    $enNew = @"
                    "ColorPickerDialog":  {
                        "Title":  "Custom color",
                        "Placeholder":  "#RRGGBB",
                        "Save":  "Save",
                        "Cancel":  "Cancel"
                    },
                    "GroupTagDialog":  {
                        "Title":  "Add tag to selection",
                        "Placeholder":  "Tag name",
                        "Add":  "Add",
                        "Cancel":  "Cancel"
                    },
                    "GroupRemoveDialog":  {
                        "Title":  "Remove models?",
                        "Message":  "Remove {0} models from library? This cannot be undone.",
                        "Remove":  "Remove",
                        "Cancel":  "Cancel"
                    },
                    "Group":  {
                        "AddTag":  "Add tag to selected",
                        "Remove":  "Remove selected",
                        "CopyPaths":  "Copy paths of selected",
                        "FindDuplicates":  "Find duplicates in selection",
                        "SelectionCount":  "Selected: {0}",
                        "CopiedFormat":  "Copied {0} paths",
                        "TagAppliedFormat":  "Applied tag to {0} models",
                        "NoDuplicates":  "No duplicates found in selection"
                    }
                },
    "Card":  {
"@
    $enOld = $enOld -replace "`r`n", "`n"
    $enNew = $enNew -replace "`r`n", "`n"
    $cnt = [regex]::Matches($en, [regex]::Escape($enOld)).Count
    Assert ($cnt -eq 1) ("en.json: ColorPickerDialog anchor matched $cnt times")
    $en = $en.Replace($enOld, $enNew)
    Set-Content -LiteralPath $enPath -Value $en -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $enPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  en.json written and parses OK"
    } catch {
        throw ("en.json invalid JSON after patch: " + $_)
    }
}

# ================================================================
# STEP 11: lang/ru.json (ASCII anchors + \uXXXX escapes)
# ================================================================
Log "STEP 11: lang/ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

if ($ru.Contains('"GroupTagDialog"')) {
    Log "  ru.json already has GroupTagDialog - skipping"
} else {
    # ASCII anchor: closing of Library block -> opening of Card block.
    $idxCard = $ru.IndexOf('    "Card":  {')
    Assert ($idxCard -gt 0) "ru.json: 'Card' block not found"
    $idxClose = $ru.LastIndexOf("                },", $idxCard)
    Assert ($idxClose -gt 0) "ru.json: Library closer '                },' not found"

    # Find the closer of ColorPickerDialog right before (20 spaces + '}').
    $idxCpd = $ru.LastIndexOf("                    `n", $idxClose)
    Assert ($idxCpd -gt 0) "ru.json: ColorPickerDialog closer not found"
    $insertAt = $idxCpd + "                    `n".Length

    # Also need to insert a comma after the ColorPickerDialog closer's '}'.
    # The closing '}' is right before the '\n' we just located - replace last '}' with '},'.
    $before = $ru.Substring(0, $idxClose)
    $closerIdx = $before.LastIndexOf("                    }")
    Assert ($closerIdx -gt 0) "ru.json: ColorPickerDialog '}' not found"
    # We'll insert ",<group blocks>" after '}' (which becomes '},<group blocks>').

    $ruBlockTemplate = @'

                    "GroupTagDialog":  {
                        "Title":  "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0442\u0435\u0433 \u043a \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u043d\u044b\u043c",
                        "Placeholder":  "\u0418\u043c\u044f \u0442\u0435\u0433\u0430",
                        "Add":  "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c",
                        "Cancel":  "\u041e\u0442\u043c\u0435\u043d\u0430"
                    },
                    "GroupRemoveDialog":  {
                        "Title":  "\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u043c\u043e\u0434\u0435\u043b\u0438?",
                        "Message":  "\u0423\u0434\u0430\u043b\u0438\u0442\u044c {0} \u043c\u043e\u0434\u0435\u043b\u0435\u0439 \u0438\u0437 \u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0438? \u042d\u0442\u043e \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0435 \u043d\u0435\u043b\u044c\u0437\u044f \u043e\u0442\u043c\u0435\u043d\u0438\u0442\u044c.",
                        "Remove":  "\u0423\u0434\u0430\u043b\u0438\u0442\u044c",
                        "Cancel":  "\u041e\u0442\u043c\u0435\u043d\u0430"
                    },
                    "Group":  {
                        "AddTag":  "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0442\u0435\u0433 \u043a \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u043d\u044b\u043c",
                        "Remove":  "\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u043d\u044b\u0435",
                        "CopyPaths":  "\u041a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u043f\u0443\u0442\u0438 \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u043d\u044b\u0445",
                        "FindDuplicates":  "\u041d\u0430\u0439\u0442\u0438 \u0434\u0443\u0431\u043b\u0438\u043a\u0430\u0442\u044b \u0432 \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u043d\u044b\u0445",
                        "SelectionCount":  "\u0412\u044b\u0434\u0435\u043b\u0435\u043d\u043e: {0}",
                        "CopiedFormat":  "\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d\u043e \u043f\u0443\u0442\u0435\u0439: {0}",
                        "TagAppliedFormat":  "\u0422\u0435\u0433 \u043f\u0440\u0438\u043c\u0435\u043d\u0451\u043d \u043a {0} \u043c\u043e\u0434\u0435\u043b\u044f\u043c",
                        "NoDuplicates":  "\u0412 \u0432\u044b\u0434\u0435\u043b\u0435\u043d\u0438\u0438 \u043d\u0435\u0442 \u0434\u0443\u0431\u043b\u0438\u043a\u0430\u0442\u043e\u0432"
                    }
'@

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    $ruBlock = [regex]::Replace($ruBlockTemplate, '\\u([0-9A-Fa-f]{4})', $evaluator)

    # Insert ',' after the ColorPickerDialog closer '}' and append the block.
    # $closerIdx points at the '}' of ColorPickerDialog.
    # Replace that '}' with '},' + block.
    $ru = $ru.Substring(0, $closerIdx) + "}," + $ruBlock + $ru.Substring($closerIdx + 1)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch {
        throw ("ru.json invalid JSON after patch: " + $_)
    }
}

# ================================================================
# STEP 12: CHANGELOG.md
# ================================================================
Log "STEP 12: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6b.1 applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6b.1 - Multi-select (backend + ViewModel)

- ModelCardViewModel: IsSelected bool property with Raise.
- LibraryViewModel: SelectedCards (ObservableCollection), GroupTagCandidates; SelectedCount/HasSelection/IsMultiSelection; OnCardClicked(card, ctrl, shift) public entry point (code-behind wires in 0.5.6b.2); ClearSelection/SelectAllVisible; RefreshSelectionCollections.
- LibraryViewModel group commands: GroupAddTagCommand (AutoCompleteBox on GroupTagCandidates + free text), GroupRemoveCommand (confirm dialog), GroupCopyPathsCommand (clipboard, one path per line), GroupFindDuplicatesCommand (in-place filter by file_hash intersection within selection).
- LibraryViewModel dialog state: ShowGroupTagDialog / GroupTagName / ShowGroupRemoveConfirm / GroupRemoveMessage + 4 confirm/cancel commands.
- LibraryViewModel: selection reset on ReloadModelsCoreAsync (Cards.Clear resets selection state).
- lang/en.json + lang/ru.json: Library.GroupTagDialog / GroupRemoveDialog / Group blocks.
- Deferred to 0.5.6c: GroupAddToCollection (requires manual-collection type - Collection model is currently smart-filter-only).
<!-- patch 0.5.6b.1 applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then 0.5.6b.2 (LibraryView.axaml rubber band + Ctrl/Shift wiring)" -ForegroundColor Cyan