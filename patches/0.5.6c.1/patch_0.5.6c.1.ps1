# patch_0.5.6c.1.ps1
# 0.5.6c.1 - Fix for 0.5.6c STEP 9e + complete STEP 10-15
#   0.5.6c STEP 9e detection was too loose: Contains('ChangeCollectionColorAsync')
#   matched the lambda reference added by STEP 9d, so the method definition was
#   skipped and post-write verify aborted. Data-layer changes (0005..CollectionRow,
#   _tagDirectUsage, breakdown, LoadCollections wiring) applied cleanly.
#   This patch:
#     STEP 1  Backup.
#     STEP 2  Insert ChangeCollectionColorAsync method (strict detection).
#     STEP 3  ModelCardPageViewModel: TagCandidates + RefreshTagCandidatesAsync
#             (re-run of 0.5.6c STEP 10 - idempotent).
#     STEP 4  LibraryView.axaml: collections item template (re-run of STEP 11).
#     STEP 5  ModelCardView.axaml: AutoCompleteBox (re-run of STEP 12).
#     STEP 6  en.json: DeleteTagDialog.Message 3-param (re-run of STEP 13).
#     STEP 7  ru.json: DeleteTagDialog.Message 3-param (re-run of STEP 14).
#     STEP 8  CHANGELOG.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6c.1\patch_0.5.6c.1.ps1"

Write-Host "=== MiniCodex patch 0.5.6c.1 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6c.1'
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

$libVmPath  = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$mcVmPath   = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
$libAxPath  = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$mcAxPath   = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
$enPath     = Join-Path $projectRoot 'lang\en.json'
$ruPath     = Join-Path $projectRoot 'lang\ru.json'
$clPath     = Join-Path $projectRoot 'CHANGELOG.md'

foreach ($p in @($libVmPath,$mcVmPath,$libAxPath,$mcAxPath,$enPath,$ruPath,$clPath)) {
    Assert (Test-Path $p) ("Missing: " + $p)
}

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
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
# STEP 2: LibraryViewModel - insert ChangeCollectionColorAsync
# ================================================================
Log "STEP 2: LibraryViewModel - ChangeCollectionColorAsync"

$lib = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
$nl = if ($lib.Contains("`r`n")) { "`r`n" } else { "`n" }

# STRICT detection: method DEFINITION, not the lambda reference added in 0.5.6c STEP 9d.
if ($lib.Contains('public async Task ChangeCollectionColorAsync')) {
    Log "  method definition already present - skipping (idempotent)"
} else {
    # Sanity: reference from 9d should already be there.
    Assert ($lib.Contains('ChangeCollectionColorAsync(r, col)')) "0.5.6c STEP 9d reference missing - unexpected state, abort"

    $oldAnchor = "    public async Task ChangeTagColorAsync(TagNodeViewModel tag, string? color)"
    $newAnchor = @'
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
    $oldAnchor = $oldAnchor -replace "`r`n", $nl
    $newAnchor = $newAnchor -replace "`r`n", $nl
    $lib = Replace-Exact $lib $oldAnchor $newAnchor "LibraryViewModel: insert ChangeCollectionColorAsync"

    Set-Content -LiteralPath $libVmPath -Value $lib -Encoding UTF8 -NoNewline
    Log ("  written (" + $lib.Length + " chars)")
}

$libBack = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libBack.Contains('public async Task ChangeCollectionColorAsync')) "post-write: method definition missing"
$defCount = [regex]::Matches($libBack, 'public async Task ChangeCollectionColorAsync').Count
Assert ($defCount -eq 1) ("post-write: method definition count = $defCount (expected 1)")
Log "  post-write verify OK"

# ================================================================
# STEP 3: ModelCardPageViewModel - TagCandidates + RefreshTagCandidatesAsync
# ================================================================
Log "STEP 3: ModelCardPageViewModel"

$mc = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
$nl = if ($mc.Contains("`r`n")) { "`r`n" } else { "`n" }

# 3a. TagCandidates
if ($mc.Contains('public ObservableCollection<string> TagCandidates')) {
    Log "  3a already has TagCandidates - skipping"
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

# 3b. RefreshTagCandidatesAsync method
if ($mc.Contains('private async Task RefreshTagCandidatesAsync')) {
    Log "  3b already has RefreshTagCandidatesAsync - skipping"
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

# 3c. Call in LoadAsync
if ($mc -match 'await RefreshTagCandidatesAsync\(ct\);') {
    Log "  3c already called in LoadAsync - skipping"
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

# 3d. Call in AddTagAsync (after ReloadTagsAsync)
if ($mc -match 'await ReloadTagsAsync\(CancellationToken.None\);\s*await RefreshTagCandidatesAsync') {
    Log "  3d already called in AddTagAsync - skipping"
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
Log "  post-write verify OK"

# ================================================================
# STEP 4: LibraryView.axaml - collections item template
# ================================================================
Log "STEP 4: LibraryView.axaml"

$ax = Get-Content -LiteralPath $libAxPath -Raw -Encoding UTF8
$nl = if ($ax.Contains("`r`n")) { "`r`n" } else { "`n" }

# Detection: both the color dot and the swatch context menu should be present
# in the Collections ListBox block (first 5000 chars after ItemsSource=Collections).
$collectionsIdx = $ax.IndexOf('ItemsSource="{Binding Collections}"')
$hasColorInCollections = $false
if ($collectionsIdx -gt 0) {
    $windowLen = [Math]::Min(5000, $ax.Length - $collectionsIdx)
    $window = $ax.Substring($collectionsIdx, $windowLen)
    if ($window.Contains('Fill="{Binding ColorBrush}"') -and $window.Contains('CommandParameter="#E67E22"')) {
        $hasColorInCollections = $true
    }
}

if ($hasColorInCollections) {
    Log "  collections template already has color dot + context menu - skipping"
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
# STEP 5: ModelCardView.axaml - AutoCompleteBox for NewTagName
# ================================================================
Log "STEP 5: ModelCardView.axaml"

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
# STEP 6: lang/en.json - DeleteTagDialog.Message 3-param
# ================================================================
Log "STEP 6: en.json"

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
# STEP 7: lang/ru.json - DeleteTagDialog.Message 3-param
# ================================================================
Log "STEP 7: ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

# Marker for the new version: "Прямо" (part of "Прямо задействовано")
$ruMarker = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0J/RgNGP0LzQvg=='))
if ($ru.Contains($ruMarker)) {
    Log "  already 3-param - skipping"
} else {
    # Old: "Удалить тег {0}? Связанных записей: {1}."
    # New: "Удалить тег {0}? Прямо задействовано: {1}, в поддереве потомков: {2}."
    $oldB64 = 'IiA6ICAi0KPQtNCw0LvQuNGC0Ywg0YLQtdCzIHswfT8g0KHRgtGP0LfQsNC90L3Ri9GFINC30LDQv9C40YHQtdC5OiB7MX0uIiw='
    $newB64 = 'IiA6ICAi0KPQtNCw0LvQuNGC0Ywg0YLQtdCzIHswfT8g0J/RgNGP0LzQviDQt9Cw0LTQtdC50YHRgtCy0L7QstCw0L3Qvjoge7F9LCDQsiDQv9C+0LTQtNC10YDQtdCy0LUg0L/QvtGC0L7QvNC60L7Qsjoge7J9LiIs'
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
# STEP 8: CHANGELOG.md
# ================================================================
Log "STEP 8: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

$need6c  = -not $cl.Contains('<!-- patch 0.5.6c applied -->')
$need6c1 = -not $cl.Contains('<!-- patch 0.5.6c.1 applied -->')

if (-not $need6c -and -not $need6c1) {
    Log "  CHANGELOG.md already has both markers - skipping"
} else {
    $parts = @()
    if ($need6c) {
        $parts += @'

## 0.5.6c - Tags / Collections polish

- Migration 0005: Collection.color column.
- Entities.Collection: Color string?. ICollectionService.SetColorAsync implemented.
- CollectionRepository: upsert + map color (FieldCount > 4 guard).
- CollectionRow: rewritten with INotifyPropertyChanged, Color, ColorBrush, HasColor, Palette (8 presets), SetColorCommand, ClearColorCommand, OnColorChange callback.
- LibraryViewModel: _tagDirectUsage dict; DeleteTagDialog shows direct vs subtree breakdown; LoadCollectionsAsync wires OnColorChange; ChangeCollectionColorAsync.
- ModelCardPageViewModel: TagCandidates + RefreshTagCandidatesAsync (called in LoadAsync and AddTagAsync).
- LibraryView.axaml: collections ListBox item template gets color dot + context menu (8 preset swatches + Clear color).
- ModelCardView.axaml: New tag TextBox -> AutoCompleteBox (ItemsSource=TagCandidates).
- lang/en.json + lang/ru.json: Library.DeleteTagDialog.Message -> 3-param format.
<!-- patch 0.5.6c applied -->
'@
    }
    if ($need6c1) {
        $parts += @'

## 0.5.6c.1 - Fix for 0.5.6c

- STEP 9e detection was too loose (matched the lambda reference from STEP 9d), so ChangeCollectionColorAsync method was never inserted; post-write verify aborted at STEP 9 and STEP 10-15 never ran.
- Fix: strict detection (public async Task ChangeCollectionColorAsync); method inserted before ChangeTagColorAsync. STEP 10-15 re-executed (ModelCardPageViewModel TagCandidates, LibraryView collections item template, ModelCardView AutoCompleteBox, en/ru DeleteTagDialog.Message, CHANGELOG).
<!-- patch 0.5.6c.1 applied -->
'@
    }
    Add-Content -LiteralPath $clPath -Value ($parts -join "`r`n") -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; dotnet test; dotnet run; then 0.5.7 (version bump 0.1.2 -> 0.1.3)" -ForegroundColor Cyan