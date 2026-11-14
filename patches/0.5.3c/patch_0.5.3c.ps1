# patch_0.5.3c.ps1 - Custom Hex Color Picker for Tags
# One logical step. ViewModel + XAML + lang.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3c'
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

function Insert-LangKeys([string]$path, [hashtable]$vals) {
    $lines = [IO.File]::ReadAllLines($path, $utf8NoBom)
    $out = New-Object System.Collections.Generic.List[string]
    $insertedMenu = $false
    $insertedDialog = $false
    $indent = ' ' * 20
    $inner  = ' ' * 24

    foreach ($line in $lines) {
        if (-not $insertedMenu -and $line -match '^\s*"Delete"\s*:\s*".*?"\s*,?\s*$') {
            $trimmed = $line.TrimEnd()
            if (-not $trimmed.EndsWith(',')) { $out.Add($trimmed + ',') } else { $out.Add($line) }
            $out.Add($inner + '"CustomColor":  "' + $vals.CustomColor + '"')
            $insertedMenu = $true
            continue
        }
        if (-not $insertedDialog -and $line -match '^\s*"DeleteTagDialog"\s*:') {
            $out.Add($line)
            $inDelete = $true
            continue
        }
        if ($inDelete) {
            if ($line -match '^\s*\}') {
                $out.Add($line.TrimEnd() + ',')
                $out.Add($indent + '"ColorPickerDialog":  {')
                $out.Add($inner + '"Title":  "' + $vals.ColorTitle + '",')
                $out.Add($inner + '"Placeholder":  "#RRGGBB",')
                $out.Add($inner + '"Save":  "' + $vals.ColorSave + '",')
                $out.Add($inner + '"Cancel":  "' + $vals.ColorCancel + '"')
                $out.Add($indent + '}')
                $insertedDialog = $true
                $inDelete = $false
                continue
            }
        }
        $out.Add($line)
    }
    if (-not $insertedMenu -or -not $insertedDialog) { throw ("Insert points not found in {0}" -f $path) }
    [IO.File]::WriteAllLines($path, $out, $utf8NoBom)
    $null = [IO.File]::ReadAllText($path, $utf8NoBom) | ConvertFrom-Json
    Write-Log ("  inserted lang keys + JSON OK: {0}" -f $path)
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
if ($tagVm -notmatch 'CustomColorLabel') { Write-Log 'TagNodeViewModel needs CustomColorLabel.' } else { throw 'Pre-flight: already applied.' }
$libVm = [IO.File]::ReadAllText($libVmPath, $utf8NoBom)
if ($libVm -match  'ConfirmColorPickerCommand') { throw 'Pre-flight: LibraryViewModel already applied.' }
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
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. TagNodeViewModel.cs ----------
$tagPairs = @(
    @{
        Label = 'add CustomColorCommand and label'
        Old = @'
    public ICommand RenameCommand { get; }
    public ICommand DeleteCommand { get; }
'@
        New = @'
    public ICommand RenameCommand { get; }
    public ICommand DeleteCommand { get; }
    public ICommand CustomColorCommand { get; }
'@
    },
    @{
        Label = 'add CustomColorLabel'
        Old = @'
    public string DeleteLabel => App.Loc?.Get("Library.TagContextMenu.Delete") ?? "Delete";
'@
        New = @'
    public string DeleteLabel => App.Loc?.Get("Library.TagContextMenu.Delete") ?? "Delete";
    public string CustomColorLabel => App.Loc?.Get("Library.TagContextMenu.CustomColor") ?? "Custom color...";
'@
    },
    @{
        Label = 'add OnCustomColor callback'
        Old = @'
    public Action<TagNodeViewModel>? OnRename { get; set; }
    public Action<TagNodeViewModel>? OnDelete { get; set; }
'@
        New = @'
    public Action<TagNodeViewModel>? OnRename { get; set; }
    public Action<TagNodeViewModel>? OnDelete { get; set; }
    public Action<TagNodeViewModel>? OnCustomColor { get; set; }
'@
    },
    @{
        Label = 'raise CustomColorLabel in RefreshLocalized'
        Old = @'
        Raise(nameof(RenameLabel));
        Raise(nameof(DeleteLabel));
'@
        New = @'
        Raise(nameof(RenameLabel));
        Raise(nameof(DeleteLabel));
        Raise(nameof(CustomColorLabel));
'@
    },
    @{
        Label = 'init CustomColorCommand'
        Old = @'
        DeleteCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnDelete?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
'@
        New = @'
        DeleteCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnDelete?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
        CustomColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnCustomColor?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
'@
    }
)
Replace-Exact $tagVmPath $tagPairs
Write-Log ("Updated: {0}" -f $tagVmPath)

# ---------- 3. LibraryViewModel.cs ----------
$libPairs = @(
    @{
        Label = 'add Avalonia.Media using'
        Old = 'using Avalonia.Threading;'
        New = @'
using Avalonia.Threading;
using Avalonia.Media;
'@
    },
    @{
        Label = 'add color picker fields'
        Old = @'
    private bool _showDeleteTagConfirm;
    private TagNodeViewModel? _deleteTagTarget;
    private string _deleteTagMessage = string.Empty;
'@
        New = @'
    private bool _showDeleteTagConfirm;
    private TagNodeViewModel? _deleteTagTarget;
    private string _deleteTagMessage = string.Empty;
    private bool _showColorPickerDialog;
    private string _newTagColor = "#E67E22";
    private TagNodeViewModel? _colorPickerTagTarget;
'@
    },
    @{
        Label = 'add color picker properties'
        Old = @'
    public string DeleteTagDialogCancelText => App.Loc?.Get("Library.DeleteTagDialog.Cancel") ?? "Cancel";
'@
        New = @'
    public string DeleteTagDialogCancelText => App.Loc?.Get("Library.DeleteTagDialog.Cancel") ?? "Cancel";

    public bool ShowColorPickerDialog
    {
        get => _showColorPickerDialog;
        set { if (_showColorPickerDialog == value) return; _showColorPickerDialog = value; Raise(); }
    }
    public string NewTagColor
    {
        get => _newTagColor;
        set
        {
            if (_newTagColor == value) return;
            _newTagColor = value;
            Raise();
            Raise(nameof(ColorPreviewBrush));
        }
    }
    public IBrush? ColorPreviewBrush
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_newTagColor)) return null;
            if (Avalonia.Media.Color.TryParse(_newTagColor, out var c)) return new SolidColorBrush(c);
            return null;
        }
    }
    public string ColorPickerTitle => App.Loc?.Get("Library.ColorPickerDialog.Title") ?? "Custom color";
    public string ColorPickerPlaceholder => App.Loc?.Get("Library.ColorPickerDialog.Placeholder") ?? "#RRGGBB";
    public string ColorPickerSaveText => App.Loc?.Get("Library.ColorPickerDialog.Save") ?? "Save";
    public string ColorPickerCancelText => App.Loc?.Get("Library.ColorPickerDialog.Cancel") ?? "Cancel";
'@
    },
    @{
        Label = 'add color picker commands'
        Old = @'
    public ICommand ConfirmDeleteTagCommand { get; }
    public ICommand CancelDeleteTagCommand { get; }
'@
        New = @'
    public ICommand ConfirmDeleteTagCommand { get; }
    public ICommand CancelDeleteTagCommand { get; }
    public ICommand ConfirmColorPickerCommand { get; }
    public ICommand CancelColorPickerCommand { get; }
'@
    },
    @{
        Label = 'init color picker commands in ctor'
        Old = @'
        ConfirmDeleteTagCommand = new RelayCommand(() => _ = ConfirmDeleteTagAsync());
        CancelDeleteTagCommand = new RelayCommand(() => { ShowDeleteTagConfirm = false; _deleteTagTarget = null; });
'@
        New = @'
        ConfirmDeleteTagCommand = new RelayCommand(() => _ = ConfirmDeleteTagAsync());
        CancelDeleteTagCommand = new RelayCommand(() => { ShowDeleteTagConfirm = false; _deleteTagTarget = null; });
        ConfirmColorPickerCommand = new RelayCommand(() => _ = ConfirmColorPickerAsync());
        CancelColorPickerCommand = new RelayCommand(CancelColorPicker);
'@
    },
    @{
        Label = 'wire OnCustomColor in LoadTagsAsync'
        Old = @'
                    OnRename = OpenRenameTagDialog,
                    OnDelete = OpenDeleteTagDialog,
                };
'@
        New = @'
                    OnRename = OpenRenameTagDialog,
                    OnDelete = OpenDeleteTagDialog,
                    OnCustomColor = OpenColorPickerDialog,
                };
'@
    },
    @{
        Label = 'insert color picker methods after ConfirmDeleteTagAsync'
        Old = @'
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
        New = @'
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

    private void OpenColorPickerDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _colorPickerTagTarget = node;
        NewTagColor = string.IsNullOrWhiteSpace(node.Color) ? "#E67E22" : node.Color;
        ShowColorPickerDialog = true;
    }

    private async Task ConfirmColorPickerAsync()
    {
        var target = _colorPickerTagTarget;
        var color = NewTagColor;
        ShowColorPickerDialog = false;
        _colorPickerTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        if (string.IsNullOrWhiteSpace(color)) return;

        if (!Avalonia.Media.Color.TryParse(color.Trim(), out _)) return;

        await ChangeTagColorAsync(target, color.Trim());
    }

    private void CancelColorPicker()
    {
        ShowColorPickerDialog = false;
        _colorPickerTagTarget = null;
    }
'@
    }
)
Replace-Exact $libVmPath $libPairs
Write-Log ("Updated: {0}" -f $libVmPath)

# ---------- 4. LibraryView.axaml ----------
$axamlPairs = @(
    @{
        Label = 'add KeyBindings for Color Picker'
        Old = @'
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmRenameTagCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelRenameTagCommand}" />
        </Panel.KeyBindings>
'@
        New = @'
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmRenameTagCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelRenameTagCommand}" />
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmColorPickerCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelColorPickerCommand}" />
        </Panel.KeyBindings>
'@
    },
    @{
        Label = 'add Custom Color menu item'
        Old = @'
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#34495E">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#34495E" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                        </ContextMenu>
'@
        New = @'
                                            <MenuItem Command="{Binding SetColorCommand}" CommandParameter="#34495E">
                                                <MenuItem.Header><Border Width="16" Height="16" CornerRadius="8" Background="#34495E" Margin="4,2"/></MenuItem.Header>
                                            </MenuItem>
                                            <MenuItem Header="{Binding CustomColorLabel}" Command="{Binding CustomColorCommand}"/>
                                        </ContextMenu>
'@
    },
    @{
        Label = 'add ColorPicker overlay dialog'
        Old = @'
        <Border IsVisible="{Binding ShowDeleteTagConfirm}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="480"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding DeleteTagDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBlock Text="{Binding DeleteTagMessage}" TextWrapping="Wrap" MaxWidth="440"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding DeleteTagDialogCancelText}" Command="{Binding CancelDeleteTagCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding DeleteTagDialogDeleteText}" Command="{Binding ConfirmDeleteTagCommand}" IsDefault="True"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>
    </Panel>
</UserControl>
'@
        New = @'
        <Border IsVisible="{Binding ShowDeleteTagConfirm}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="480"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding DeleteTagDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBlock Text="{Binding DeleteTagMessage}" TextWrapping="Wrap" MaxWidth="440"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding DeleteTagDialogCancelText}" Command="{Binding CancelDeleteTagCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding DeleteTagDialogDeleteText}" Command="{Binding ConfirmDeleteTagCommand}" IsDefault="True"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>

        <Border IsVisible="{Binding ShowColorPickerDialog}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="440"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding ColorPickerTitle}" FontSize="18" FontWeight="Bold"/>
                    <StackPanel Orientation="Horizontal" Spacing="12">
                        <TextBox Text="{Binding NewTagColor, Mode=TwoWay}"
                                 Watermark="{Binding ColorPickerPlaceholder}"
                                 MinWidth="240" VerticalAlignment="Center"/>
                        <Border Width="32" Height="32" CornerRadius="4"
                                Background="{Binding ColorPreviewBrush}"
                                BorderBrush="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                BorderThickness="1" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding ColorPickerCancelText}" Command="{Binding CancelColorPickerCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding ColorPickerSaveText}" Command="{Binding ConfirmColorPickerCommand}" IsDefault="True"
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

# ---------- 5. lang/en.json ----------
Insert-LangKeys $enPath @{
    CustomColor = 'Custom color...'
    ColorTitle  = 'Custom color'
    ColorSave   = 'Save'
    ColorCancel = 'Cancel'
}

# ---------- 6. lang/ru.json ----------
$ruCustomColor = Chars @(0x421,0x432,0x43E,0x439,0x20,0x446,0x432,0x435,0x442,0x2E,0x2E,0x2E)
$ruColorTitle  = Chars @(0x421,0x432,0x43E,0x439,0x20,0x446,0x432,0x435,0x442)
$ruColorSave   = Chars @(0x421,0x43E,0x445,0x440,0x430,0x43D,0x438,0x442,0x44C)
$ruColorCancel = Chars @(0x41E,0x442,0x43C,0x435,0x43D,0x430)

Insert-LangKeys $ruPath @{
    CustomColor = $ruCustomColor
    ColorTitle  = $ruColorTitle
    ColorSave   = $ruColorSave
    ColorCancel = $ruColorCancel
}

# ---------- 7. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3c applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3c - Custom Hex Color Picker' + $nl + $nl +
        '- TagNodeViewModel: CustomColorCommand, CustomColorLabel, OnCustomColor callback.' + $nl +
        '- LibraryViewModel: ShowColorPickerDialog, NewTagColor, ColorPreviewBrush, 4 computed strings, 2 commands, 3 methods (Open/Confirm/Cancel), wire in LoadTagsAsync.' + $nl +
        '- LibraryView.axaml: Custom Color... menu item, ColorPicker overlay (TextBox + preview), KeyBindings for Enter/Esc.' + $nl +
        '- lang: TagContextMenu.CustomColor, ColorPickerDialog.* keys.' + $nl + $nl +
        '<!-- patch 0.5.3c applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)