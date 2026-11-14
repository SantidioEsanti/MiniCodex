# patch_0.5.3b.ps1 - Tag rename/delete UI (ViewModel + XAML + lang)
# One logical step. Requires 0.5.3a/0.5.3a.1 applied.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3b'
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

function Normalize-Indents([string]$path) {
    $lines = [IO.File]::ReadAllLines($path, $utf8NoBom)
    $out = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    $changed = 0
    foreach ($line in $lines) {
        if (-not $inBlock -and $line -match '^ {28,}"CollectionsHeader"') {
            $inBlock = $true
        }
        if ($inBlock) {
            if ($line -match '^ {16,}(.*)$') {
                $line = $line.Substring(16)
                $changed++
            }
        }
        $out.Add($line)
        if ($inBlock -and $line -match '^\s*"ClearColor"\s*:') {
            $inBlock = $false
        }
    }
    if ($changed -gt 0) {
        [IO.File]::WriteAllLines($path, $out, $utf8NoBom)
        Write-Log ("  normalized indent on {0} lines in {1}" -f $changed, $path)
    } else {
        Write-Log ("  no indent normalization needed for {0}" -f $path)
    }
}

function Insert-TagKeys([string]$path, [hashtable]$vals) {
    $lines = [IO.File]::ReadAllLines($path, $utf8NoBom)
    $out = New-Object System.Collections.Generic.List[string]
    $inserted = $false
    $indent = ' ' * 20
    $inner  = ' ' * 24
    foreach ($line in $lines) {
        if (-not $inserted -and $line -match '"ClearColor"\s*:') {
            $trimmed = $line.TrimEnd()
            if (-not $trimmed.EndsWith(',')) {
                $out.Add($trimmed + ',')
            } else {
                $out.Add($line)
            }
            $out.Add($indent + '"TagContextMenu":  {')
            $out.Add($inner + '"Rename":  "' + $vals.TagRename + '",')
            $out.Add($inner + '"Delete":  "' + $vals.TagDelete + '"')
            $out.Add($indent + '},')
            $out.Add($indent + '"RenameTagDialog":  {')
            $out.Add($inner + '"Title":  "' + $vals.RenameTitle + '",')
            $out.Add($inner + '"Placeholder":  "' + $vals.RenamePlaceholder + '",')
            $out.Add($inner + '"Save":  "' + $vals.RenameSave + '",')
            $out.Add($inner + '"Cancel":  "' + $vals.RenameCancel + '"')
            $out.Add($indent + '},')
            $out.Add($indent + '"DeleteTagDialog":  {')
            $out.Add($inner + '"Title":  "' + $vals.DeleteTitle + '",')
            $out.Add($inner + '"Message":  "' + $vals.DeleteMessage + '",')
            $out.Add($inner + '"Delete":  "' + $vals.DeleteButton + '",')
            $out.Add($inner + '"Cancel":  "' + $vals.DeleteCancel + '"')
            $out.Add($indent + '}')
            $inserted = $true
            continue
        }
        $out.Add($line)
    }
    if (-not $inserted) { throw ("Insert point not found: ClearColor in {0}" -f $path) }
    [IO.File]::WriteAllLines($path, $out, $utf8NoBom)
    $null = [IO.File]::ReadAllText($path, $utf8NoBom) | ConvertFrom-Json
    Write-Log ("  inserted tag keys + JSON OK: {0}" -f $path)
}

Write-Log ("Patch {0} started" -f $Version)

# ---------- 0. Pre-flight ----------
$tagVmPath  = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs'
$libVmPath  = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$axamlPath  = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$enPath     = Join-Path $ProjectRoot 'lang\en.json'
$ruPath     = Join-Path $ProjectRoot 'lang\ru.json'
$chPath     = Join-Path $ProjectRoot 'CHANGELOG.md'

foreach ($p in @($tagVmPath, $libVmPath, $axamlPath, $enPath, $ruPath, $chPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ("Required file missing: {0}" -f $p) }
}

$tagVm = [IO.File]::ReadAllText($tagVmPath, $utf8NoBom)
if ($tagVm -notmatch 'ClearColorLabel')          { throw 'Pre-flight: TagNodeViewModel missing 0.5.2b changes.' }
if ($tagVm -match  'RenameCommand')              { throw 'Pre-flight: TagNodeViewModel already has RenameCommand. 0.5.3b applied.' }
$libVm = [IO.File]::ReadAllText($libVmPath, $utf8NoBom)
if ($libVm -notmatch 'ConfirmSaveFilterCommand') { throw 'Pre-flight: LibraryViewModel missing 0.5.2d changes.' }
if ($libVm -match  'ConfirmRenameTagCommand')    { throw 'Pre-flight: LibraryViewModel already has tag dialog commands. 0.5.3b applied.' }
$enJs = [IO.File]::ReadAllText($enPath, $utf8NoBom)
if ($enJs -notmatch '"ClearColor"')              { throw 'Pre-flight: en.json missing 0.5.2c keys.' }
if ($enJs -match  '"TagContextMenu"')            { throw 'Pre-flight: en.json already has TagContextMenu. 0.5.3b applied.' }
Write-Log 'Pre-flight OK.'

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs',
    'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
    'src\MiniCodex.App\Views\LibraryView.axaml',
    'lang\en.json',
    'lang\ru.json',
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

# ---------- 2. TagNodeViewModel.cs ----------
$tagPairs = @(
    @{
        Label = 'add Rename/Delete commands + labels + callbacks'
        Old = @'
    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }
    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";
'@
        New = @'
    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }
    public ICommand RenameCommand { get; }
    public ICommand DeleteCommand { get; }
    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";
    public string RenameLabel => App.Loc?.Get("Library.TagContextMenu.Rename") ?? "Rename...";
    public string DeleteLabel => App.Loc?.Get("Library.TagContextMenu.Delete") ?? "Delete";

    public Action<TagNodeViewModel>? OnRename { get; set; }
    public Action<TagNodeViewModel>? OnDelete { get; set; }

    public void RefreshLocalized()
    {
        Raise(nameof(ClearColorLabel));
        Raise(nameof(RenameLabel));
        Raise(nameof(DeleteLabel));
        foreach (var c in Children) c.RefreshLocalized();
    }
'@
    },
    @{
        Label = 'ctor new commands'
        Old = @'
        ClearColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnColorChange?.Invoke(this, null); },
            () => !string.IsNullOrEmpty(Id));
'@
        New = @'
        ClearColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnColorChange?.Invoke(this, null); },
            () => !string.IsNullOrEmpty(Id));
        RenameCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnRename?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
        DeleteCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnDelete?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
'@
    }
)
Replace-Exact $tagVmPath $tagPairs
Write-Log ("Updated: {0}" -f $tagVmPath)

# ---------- 3. LibraryViewModel.cs ----------
$libPairs = @(
    @{
        Label = 'add dialog fields'
        Old = @'
    private readonly RelayCommand _deleteCollectionCommand;
    private bool _showSaveFilterDialog;
    private string _newCollectionName = string.Empty;
'@
        New = @'
    private readonly RelayCommand _deleteCollectionCommand;
    private bool _showSaveFilterDialog;
    private string _newCollectionName = string.Empty;
    private bool _showRenameTagDialog;
    private string _newTagName = string.Empty;
    private TagNodeViewModel? _renameTagTarget;
    private bool _showDeleteTagConfirm;
    private TagNodeViewModel? _deleteTagTarget;
    private string _deleteTagMessage = string.Empty;
'@
    },
    @{
        Label = 'add tag dialog properties'
        Old = @'
    public string SaveFilterDialogCancelText => App.Loc?.Get("Library.SaveFilterDialog.Cancel") ?? "Cancel";
'@
        New = @'
    public string SaveFilterDialogCancelText => App.Loc?.Get("Library.SaveFilterDialog.Cancel") ?? "Cancel";

    public bool ShowRenameTagDialog
    {
        get => _showRenameTagDialog;
        set { if (_showRenameTagDialog == value) return; _showRenameTagDialog = value; Raise(); }
    }
    public string NewTagName
    {
        get => _newTagName;
        set { if (_newTagName == value) return; _newTagName = value; Raise(); }
    }
    public string RenameTagDialogTitle => App.Loc?.Get("Library.RenameTagDialog.Title") ?? "Rename tag";
    public string RenameTagDialogPlaceholder => App.Loc?.Get("Library.RenameTagDialog.Placeholder") ?? "Tag name";
    public string RenameTagDialogSaveText => App.Loc?.Get("Library.RenameTagDialog.Save") ?? "Save";
    public string RenameTagDialogCancelText => App.Loc?.Get("Library.RenameTagDialog.Cancel") ?? "Cancel";

    public bool ShowDeleteTagConfirm
    {
        get => _showDeleteTagConfirm;
        set { if (_showDeleteTagConfirm == value) return; _showDeleteTagConfirm = value; Raise(); }
    }
    public string DeleteTagMessage
    {
        get => _deleteTagMessage;
        private set { if (_deleteTagMessage == value) return; _deleteTagMessage = value; Raise(); }
    }
    public string DeleteTagDialogTitle => App.Loc?.Get("Library.DeleteTagDialog.Title") ?? "Delete tag?";
    public string DeleteTagDialogDeleteText => App.Loc?.Get("Library.DeleteTagDialog.Delete") ?? "Delete";
    public string DeleteTagDialogCancelText => App.Loc?.Get("Library.DeleteTagDialog.Cancel") ?? "Cancel";
'@
    },
    @{
        Label = 'add commands declarations'
        Old = @'
    public ICommand ConfirmSaveFilterCommand { get; }
    public ICommand CancelSaveFilterCommand { get; }
'@
        New = @'
    public ICommand ConfirmSaveFilterCommand { get; }
    public ICommand CancelSaveFilterCommand { get; }
    public ICommand ConfirmRenameTagCommand { get; }
    public ICommand CancelRenameTagCommand { get; }
    public ICommand ConfirmDeleteTagCommand { get; }
    public ICommand CancelDeleteTagCommand { get; }
'@
    },
    @{
        Label = 'ctor wire tag commands'
        Old = @'
        ConfirmSaveFilterCommand = new RelayCommand(() => _ = ConfirmSaveFilterAsync());
        CancelSaveFilterCommand = new RelayCommand(CancelSaveFilter);
'@
        New = @'
        ConfirmSaveFilterCommand = new RelayCommand(() => _ = ConfirmSaveFilterAsync());
        CancelSaveFilterCommand = new RelayCommand(CancelSaveFilter);
        ConfirmRenameTagCommand = new RelayCommand(() => _ = ConfirmRenameTagAsync());
        CancelRenameTagCommand = new RelayCommand(() => { ShowRenameTagDialog = false; _renameTagTarget = null; });
        ConfirmDeleteTagCommand = new RelayCommand(() => _ = ConfirmDeleteTagAsync());
        CancelDeleteTagCommand = new RelayCommand(() => { ShowDeleteTagConfirm = false; _deleteTagTarget = null; });
'@
    },
    @{
        Label = 'RefreshLocalized refresh tag nodes'
        Old = @'
        Raise(nameof(CollectionsHeader));
        Raise(nameof(SaveFilterButtonText));
        Raise(nameof(DeleteCollectionTooltip));
'@
        New = @'
        Raise(nameof(CollectionsHeader));
        Raise(nameof(SaveFilterButtonText));
        Raise(nameof(DeleteCollectionTooltip));
        foreach (var t in Tags) t.RefreshLocalized();
'@
    },
    @{
        Label = 'LoadTagsAsync wire OnRename/OnDelete'
        Old = @'
                    Color = t.Color,
                    OnColorChange = (node, c) => _ = ChangeTagColorAsync(node, c),
                };
'@
        New = @'
                    Color = t.Color,
                    OnColorChange = (node, c) => _ = ChangeTagColorAsync(node, c),
                    OnRename = OpenRenameTagDialog,
                    OnDelete = OpenDeleteTagDialog,
                };
'@
    },
    @{
        Label = 'insert tag dialog methods after ChangeTagColorAsync'
        Old = @'
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
'@
        New = @'
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

    private void OpenRenameTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _renameTagTarget = node;
        NewTagName = node.Name;
        ShowRenameTagDialog = true;
    }

    private async Task ConfirmRenameTagAsync()
    {
        var target = _renameTagTarget;
        var name = NewTagName;
        ShowRenameTagDialog = false;
        _renameTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        if (string.IsNullOrWhiteSpace(name)) return;
        try
        {
            await _tagService.RenameAsync(target.Id, name.Trim());
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ConfirmRenameTagAsync failed", ex); }
    }

    private void OpenDeleteTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _deleteTagTarget = node;
        var fmt = App.Loc?.Get("Library.DeleteTagDialog.Message") ?? "Delete tag {0}? Linked rows: {1}.";
        DeleteTagMessage = string.Format(fmt, node.Name, node.UsageCount);
        ShowDeleteTagConfirm = true;
    }

    private async Task ConfirmDeleteTagAsync()
    {
        var target = _deleteTagTarget;
        ShowDeleteTagConfirm = false;
        _deleteTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        try
        {
            await _tagService.DeleteAsync(target.Id);
            await LoadTagsAsync(CancellationToken.None);
            if (SelectedTag == null && Tags.Count > 0)
                SelectedTag = Tags[0];
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ConfirmDeleteTagAsync failed", ex); }
    }
'@
    }
)
Replace-Exact $libVmPath $libPairs
Write-Log ("Updated: {0}" -f $libVmPath)

# ---------- 4. LibraryView.axaml ----------
$axamlPairs = @(
    @{
        Label = 'ContextMenu Rename + Delete'
        Old = @'
                                            <ContextMenu>
                                                <MenuItem Header="{Binding ClearColorLabel}" Command="{Binding ClearColorCommand}"/>
                                                <Separator/>
'@
        New = @'
                                            <ContextMenu>
                                                <MenuItem Header="{Binding RenameLabel}" Command="{Binding RenameCommand}"/>
                                                <MenuItem Header="{Binding DeleteLabel}" Command="{Binding DeleteCommand}"/>
                                                <Separator/>
                                                <MenuItem Header="{Binding ClearColorLabel}" Command="{Binding ClearColorCommand}"/>
                                                <Separator/>
'@
    },
    @{
        Label = 'append Rename + Delete overlays before Panel close'
        Old = @'
    </Panel>
</UserControl>
'@
        New = @'
        <Border IsVisible="{Binding ShowRenameTagDialog}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="440"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding RenameTagDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBox Text="{Binding NewTagName, Mode=TwoWay}"
                             Watermark="{Binding RenameTagDialogPlaceholder}"
                             MinWidth="320"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding RenameTagDialogCancelText}" Command="{Binding CancelRenameTagCommand}" Padding="14,8"/>
                        <Button Content="{Binding RenameTagDialogSaveText}" Command="{Binding ConfirmRenameTagCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>

        <Border IsVisible="{Binding ShowDeleteTagConfirm}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="480"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding DeleteTagDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBlock Text="{Binding DeleteTagMessage}" TextWrapping="Wrap" MaxWidth="440"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding DeleteTagDialogCancelText}" Command="{Binding CancelDeleteTagCommand}" Padding="14,8"/>
                        <Button Content="{Binding DeleteTagDialogDeleteText}" Command="{Binding ConfirmDeleteTagCommand}"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
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

# ---------- 5. lang/en.json ----------
Normalize-Indents $enPath
Insert-TagKeys $enPath @{
    TagRename         = 'Rename...'
    TagDelete         = 'Delete'
    RenameTitle       = 'Rename tag'
    RenamePlaceholder = 'Tag name'
    RenameSave        = 'Save'
    RenameCancel      = 'Cancel'
    DeleteTitle       = 'Delete tag?'
    DeleteMessage     = 'Delete tag {0}? Linked rows: {1}.'
    DeleteButton      = 'Delete'
    DeleteCancel      = 'Cancel'
}

# ---------- 6. lang/ru.json ----------
Normalize-Indents $ruPath
$ruTagRename         = Chars @(0x41F,0x435,0x440,0x435,0x438,0x43C,0x435,0x43D,0x43E,0x432,0x430,0x442,0x44C,0x2E,0x2E,0x2E)
$ruTagDelete         = Chars @(0x423,0x434,0x430,0x43B,0x438,0x442,0x44C)
$ruRenameTitle       = Chars @(0x41F,0x435,0x440,0x435,0x438,0x43C,0x435,0x43D,0x43E,0x432,0x430,0x442,0x44C,0x20,0x442,0x435,0x433)
$ruRenamePlaceholder = Chars @(0x418,0x43C,0x44F,0x20,0x442,0x435,0x433,0x430)
$ruRenameSave        = Chars @(0x421,0x43E,0x445,0x440,0x430,0x43D,0x438,0x442,0x44C)
$ruRenameCancel      = Chars @(0x41E,0x442,0x43C,0x435,0x43D,0x430)
$ruDeleteTitle       = Chars @(0x423,0x434,0x430,0x43B,0x438,0x442,0x44C,0x20,0x442,0x435,0x433,0x3F)
$ruDeleteMessage     = Chars @(0x423,0x434,0x430,0x43B,0x438,0x442,0x44C,0x20,0x442,0x435,0x433,0x20,0x7B,0x30,0x7D,0x3F,0x20,0x421,0x432,0x44F,0x437,0x430,0x43D,0x43D,0x44B,0x445,0x20,0x437,0x430,0x43F,0x438,0x441,0x435,0x439,0x3A,0x20,0x7B,0x31,0x7D,0x2E)
$ruDeleteButton      = Chars @(0x423,0x434,0x430,0x43B,0x438,0x442,0x44C)
$ruDeleteCancel      = Chars @(0x41E,0x442,0x43C,0x435,0x43D,0x430)

Insert-TagKeys $ruPath @{
    TagRename         = $ruTagRename
    TagDelete         = $ruTagDelete
    RenameTitle       = $ruRenameTitle
    RenamePlaceholder = $ruRenamePlaceholder
    RenameSave        = $ruRenameSave
    RenameCancel      = $ruRenameCancel
    DeleteTitle       = $ruDeleteTitle
    DeleteMessage     = $ruDeleteMessage
    DeleteButton      = $ruDeleteButton
    DeleteCancel      = $ruDeleteCancel
}

# ---------- 7. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3b applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3b - Tag rename/delete UI' + $nl + $nl +
        '- TagNodeViewModel: OnRename/OnDelete callbacks, RenameCommand/DeleteCommand (CanExecute=false for Id==""), RenameLabel/DeleteLabel, RefreshLocalized() (fixes stale ClearColorLabel/RenameLabel/DeleteLabel after language switch).' + $nl +
        '- LibraryViewModel: 6 new fields (dialog state + targets), 9 computed properties, 4 commands (Confirm/Cancel x Rename/Delete), 4 private methods (Open/Confirm x Rename/Delete), wire OnRename/OnDelete in LoadTagsAsync, RefreshLocalized for all TagNodeViewModel nodes. After delete: if SelectedTag was null, falls back to first (All models).' + $nl +
        '- LibraryView.axaml: 2 MenuItem (Rename, Delete) in TreeDataTemplate ContextMenu; 2 overlay dialogs (Rename styled like SaveFilter, Delete with red confirm button like ScanWarning).' + $nl +
        '- lang/en.json + lang/ru.json: 10 keys (TagContextMenu.Rename/Delete, RenameTagDialog.{Title,Placeholder,Save,Cancel}, DeleteTagDialog.{Title,Message,Delete,Cancel}). Indent normalized on 5 keys from 0.5.2c (36/40 -> 20/24).' + $nl + $nl +
        '<!-- patch 0.5.3b applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next: build + test + run (expect 60/60, 0/0)'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)