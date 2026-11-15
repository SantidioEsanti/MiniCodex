# patch_0.5.6b.2.ps1
# 0.5.6b.2 - Multi-select: XAML + code-behind
#   VM plumbing:
#     - ModelCardViewModel: optional ctor param onClick + HandleClick(ctrl, shift).
#     - LibraryViewModel: pass OnCardClicked into cards; RefreshSelectionCollections public;
#       HasAnyModalOpen guard on ClearSelection/SelectAllVisible; dialog guard in
#       GroupAddTagAsync/GroupRemoveAsync; GroupSelectionStatusText + GroupClearText.
#   UI:
#     - ModelCardTile.axaml: amber border (#E67E22) on IsSelected via Classes.selected style.
#     - LibraryView.axaml: group toolbar (Row 1, visible when IsMultiSelection) with
#       Add tag / Copy paths / Find duplicates / Remove / Clear; CardsHost Grid wraps ItemsControl
#       and Canvas overlay; Esc + Ctrl+A KeyBindings; group dialogs (tag + remove confirm).
#     - LibraryView.axaml.cs: pointer handlers (single/Ctrl/Shift click, double-click open,
#       rubber band on empty space, right-click selection sync); helpers.
#   Lang:
#     - Library.Group.Clear added to en.json/ru.json.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6b.2\patch_0.5.6b.2.ps1"

Write-Host "=== MiniCodex patch 0.5.6b.2 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6b.2'
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

$mcVmPath   = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs'
$libVmPath  = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$tileAxPath = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardTile.axaml'
$libAxPath  = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$libCsPath  = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml.cs'
$enPath     = Join-Path $projectRoot 'lang\en.json'
$ruPath     = Join-Path $projectRoot 'lang\ru.json'
$clPath     = Join-Path $projectRoot 'CHANGELOG.md'

foreach ($p in @($mcVmPath,$libVmPath,$tileAxPath,$libAxPath,$libCsPath,$enPath,$ruPath,$clPath)) {
    Assert (Test-Path $p) ("Missing: " + $p)
}

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
    'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs',
    'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
    'src\MiniCodex.App\Views\ModelCardTile.axaml',
    'src\MiniCodex.App\Views\LibraryView.axaml',
    'src\MiniCodex.App\Views\LibraryView.axaml.cs',
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
# STEP 2: ModelCardViewModel - onClick callback
# ================================================================
Log "STEP 2: ModelCardViewModel - onClick callback"

$mc = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
$nl = if ($mc.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($mc.Contains('_onClick')) {
    Log "  already has _onClick - skipping (idempotent)"
} else {
    $oldCtor = @'
    private readonly Action<Model> _onOpen;
    private readonly Action<Model> _onAddTag;
    private readonly Action<Model> _onRemoveFromLibrary;
    private readonly IIntegrationService? _integration;
'@
    $newCtor = @'
    private readonly Action<Model> _onOpen;
    private readonly Action<Model> _onAddTag;
    private readonly Action<Model> _onRemoveFromLibrary;
    private readonly Action<ModelCardViewModel, bool, bool>? _onClick;
    private readonly IIntegrationService? _integration;
'@
    $oldCtor = $oldCtor -replace "`r`n", $nl
    $newCtor = $newCtor -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldCtor $newCtor "ModelCardViewModel: fields"

    $oldSig = @'
    public ModelCardViewModel(
        Model model,
        Action<Model> onOpen,
        Action<Model> onAddTag,
        Action<Model> onRemoveFromLibrary,
        IIntegrationService? integration,
        bool hasSlicer,
        bool hasEditor)
    {
        Model = model;
        _onOpen = onOpen;
        _onAddTag = onAddTag;
        _onRemoveFromLibrary = onRemoveFromLibrary;
        _integration = integration;
'@
    $newSig = @'
    public ModelCardViewModel(
        Model model,
        Action<Model> onOpen,
        Action<Model> onAddTag,
        Action<Model> onRemoveFromLibrary,
        IIntegrationService? integration,
        bool hasSlicer,
        bool hasEditor,
        Action<ModelCardViewModel, bool, bool>? onClick = null)
    {
        Model = model;
        _onOpen = onOpen;
        _onAddTag = onAddTag;
        _onRemoveFromLibrary = onRemoveFromLibrary;
        _integration = integration;
        _onClick = onClick;
'@
    $oldSig = $oldSig -replace "`r`n", $nl
    $newSig = $newSig -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldSig $newSig "ModelCardViewModel: ctor"

    $oldHook = @'
    public void RotateTo(int index)
'@
    $newHook = @'
    // 0.5.6b.2: click plumbing (LibraryView passes ctrl/shift + this card)
    public void HandleClick(bool isCtrl, bool isShift) => _onClick?.Invoke(this, isCtrl, isShift);

    public void RotateTo(int index)
'@
    $oldHook = $oldHook -replace "`r`n", $nl
    $newHook = $newHook -replace "`r`n", $nl
    $mc = Replace-Exact $mc $oldHook $newHook "ModelCardViewModel: HandleClick"

    Set-Content -LiteralPath $mcVmPath -Value $mc -Encoding UTF8 -NoNewline
    Log ("  written (" + $mc.Length + " chars)")
}

# ================================================================
# STEP 3: LibraryViewModel - plumbing
# ================================================================
Log "STEP 3: LibraryViewModel - plumbing"

$lib = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
$nl = if ($lib.Contains("`r`n")) { "`r`n" } else { "`n" }

# 3a. Pass OnCardClicked to cards (via optional ctor arg)
$oldCardCtor = @'
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
'@
$newCardCtor = @'
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor, OnCardClickedInternal);
'@
$oldCardCtor = $oldCardCtor -replace "`r`n", $nl
$newCardCtor = $newCardCtor -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldCardCtor $newCardCtor "LibraryViewModel: pass click callback"

# 3b. Add OnCardClickedInternal helper right after OnCardClicked public method
$oldCardClickTail = @'
        RefreshSelectionCollections();
    }

    private void RefreshSelectionCollections()
'@
$newCardClickTail = @'
        RefreshSelectionCollections();
    }

    private void OnCardClickedInternal(ModelCardViewModel card, bool isCtrl, bool isShift)
        => OnCardClicked(card, isCtrl, isShift);

    public void RefreshSelectionCollections()
'@
$oldCardClickTail = $oldCardClickTail -replace "`r`n", $nl
$newCardClickTail = $newCardClickTail -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldCardClickTail $newCardClickTail "LibraryViewModel: RefreshSelectionCollections public + helper"

# 3c. Guard on ClearSelection
$oldClear = @'
    public void ClearSelection()
    {
        foreach (var c in Cards) c.IsSelected = false;
        _lastClickedIndex = -1;
        RefreshSelectionCollections();
    }
'@
$newClear = @'
    public void ClearSelection()
    {
        if (HasAnyModalOpen()) return;
        foreach (var c in Cards) c.IsSelected = false;
        _lastClickedIndex = -1;
        RefreshSelectionCollections();
    }
'@
$oldClear = $oldClear -replace "`r`n", $nl
$newClear = $newClear -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldClear $newClear "LibraryViewModel: ClearSelection guard"

# 3d. Guard on SelectAllVisible
$oldSelAll = @'
    public void SelectAllVisible()
    {
        foreach (var c in Cards) c.IsSelected = true;
        _lastClickedIndex = Cards.Count - 1;
        RefreshSelectionCollections();
    }
'@
$newSelAll = @'
    public void SelectAllVisible()
    {
        if (HasAnyModalOpen()) return;
        foreach (var c in Cards) c.IsSelected = true;
        _lastClickedIndex = Cards.Count - 1;
        RefreshSelectionCollections();
    }
'@
$oldSelAll = $oldSelAll -replace "`r`n", $nl
$newSelAll = $newSelAll -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldSelAll $newSelAll "LibraryViewModel: SelectAllVisible guard"

# 3e. Guard in GroupAddTagAsync
$oldAddTag = @'
        if (_tagService == null || SelectedCards.Count == 0) return;
        var name = (_groupTagName ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(name)) return;
'@
$newAddTag = @'
        if (!ShowGroupTagDialog) return;
        if (_tagService == null || SelectedCards.Count == 0) return;
        var name = (_groupTagName ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(name)) return;
'@
$oldAddTag = $oldAddTag -replace "`r`n", $nl
$newAddTag = $newAddTag -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldAddTag $newAddTag "LibraryViewModel: GroupAddTagAsync guard"

# 3f. Guard in GroupRemoveAsync
$oldRem = @'
        if (_models == null || SelectedCards.Count == 0) return;
        var cards = SelectedCards.ToList();
'@
$newRem = @'
        if (!ShowGroupRemoveConfirm) return;
        if (_models == null || SelectedCards.Count == 0) return;
        var cards = SelectedCards.ToList();
'@
$oldRem = $oldRem -replace "`r`n", $nl
$newRem = $newRem -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldRem $newRem "LibraryViewModel: GroupRemoveAsync guard"

# 3g. GroupSelectionStatusText + GroupClearText + HasAnyModalOpen, inserted right before RefreshLocalized
$oldRefresh = @'
    public void RefreshLocalized()
    {
'@
$newRefresh = @'
    public string GroupSelectionStatusText => string.Format(GroupSelectionStatusFormat, SelectedCount);
    public string GroupClearText => App.Loc?.Get("Library.Group.Clear") ?? "Clear";

    private bool HasAnyModalOpen()
    {
        return _showScanWarning || _showSaveFilterDialog || _showRenameTagDialog
            || _showDeleteTagConfirm || _showColorPickerDialog
            || _showGroupTagDialog || _showGroupRemoveConfirm;
    }

    public void RefreshLocalized()
    {
'@
$oldRefresh = $oldRefresh -replace "`r`n", $nl
$newRefresh = $newRefresh -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldRefresh $newRefresh "LibraryViewModel: new props + HasAnyModalOpen"

# 3h. Raise GroupSelectionStatusText in RefreshSelectionCollections
$oldRSC = @'
        Raise(nameof(SelectedCount));
        Raise(nameof(HasSelection));
        Raise(nameof(IsMultiSelection));
    }
'@
$newRSC = @'
        Raise(nameof(SelectedCount));
        Raise(nameof(HasSelection));
        Raise(nameof(IsMultiSelection));
        Raise(nameof(GroupSelectionStatusText));
    }
'@
$oldRSC = $oldRSC -replace "`r`n", $nl
$newRSC = $newRSC -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldRSC $newRSC "LibraryViewModel: Raise GroupSelectionStatusText"

# 3i. Raise GroupSelectionStatusText + GroupClearText in RefreshLocalized (already adds other props)
$oldRL = @'
        Raise(nameof(GroupSelectionStatusFormat));
        UpdatePreviewsStatus();
'@
$newRL = @'
        Raise(nameof(GroupSelectionStatusFormat));
        Raise(nameof(GroupSelectionStatusText));
        Raise(nameof(GroupClearText));
        UpdatePreviewsStatus();
'@
$oldRL = $oldRL -replace "`r`n", $nl
$newRL = $newRL -replace "`r`n", $nl
$lib = Replace-Exact $lib $oldRL $newRL "LibraryViewModel: RefreshLocalized extra raises"

Set-Content -LiteralPath $libVmPath -Value $lib -Encoding UTF8 -NoNewline
Log ("  LibraryViewModel.cs written (" + $lib.Length + " chars)")

# post-write sanity
$libBack = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libBack.Contains('public void RefreshSelectionCollections()')) "post-write: RefreshSelectionCollections not public"
Assert ($libBack.Contains('OnCardClickedInternal')) "post-write: OnCardClickedInternal missing"
Assert ($libBack.Contains('if (HasAnyModalOpen()) return;')) "post-write: HasAnyModalOpen guard missing"
Assert ($libBack.Contains('public string GroupSelectionStatusText')) "post-write: GroupSelectionStatusText missing"
Assert ($libBack.Contains('private bool HasAnyModalOpen()')) "post-write: HasAnyModalOpen missing"
Log "  post-write verify OK"

# ================================================================
# STEP 4: ModelCardTile.axaml - amber border on selection
# ================================================================
Log "STEP 4: ModelCardTile.axaml"

$tile = Get-Content -LiteralPath $tileAxPath -Raw -Encoding UTF8
$nl = if ($tile.Contains("`r`n")) { "`r`n" } else { "`n" }

if ($tile.Contains('Classes.selected="{Binding IsSelected}"')) {
    Log "  already has Classes.selected - skipping (idempotent)"
} else {
    # 4a. Insert UserControl.Styles with selected-card style + base card style
    $oldHeader = @'
             x:Class="MiniCodex.App.Views.ModelCardTile"
             x:DataType="vm:ModelCardViewModel" Margin="6,6,6,20" ClipToBounds="False">
    <!-- patch 0.5.0a2 applied -->
'@
    $newHeader = @'
             x:Class="MiniCodex.App.Views.ModelCardTile"
             x:DataType="vm:ModelCardViewModel" Margin="6,6,6,20" ClipToBounds="False">
    <!-- patch 0.5.0a2 applied -->
    <!-- patch 0.5.6b.2 applied -->
    <UserControl.Styles>
        <Style Selector="Border.card">
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="2"/>
        </Style>
        <Style Selector="Border.card.selected">
            <Setter Property="BorderBrush" Value="#E67E22"/>
        </Style>
    </UserControl.Styles>
'@
    $oldHeader = $oldHeader -replace "`r`n", $nl
    $newHeader = $newHeader -replace "`r`n", $nl
    $tile = Replace-Exact $tile $oldHeader $newHeader "ModelCardTile: styles block"

    # 4b. Add Classes.selected to outer Border
    $oldBorder = @'
    <Border Classes="card" Width="220" Height="260" Margin="6" Padding="6" CornerRadius="{DynamicResource CornerRadiusLarge}" BoxShadow="{DynamicResource CardShadow}" ClipToBounds="False">
'@
    $newBorder = @'
    <Border Classes="card" Classes.selected="{Binding IsSelected}" Width="220" Height="260" Margin="6" Padding="6" CornerRadius="{DynamicResource CornerRadiusLarge}" BoxShadow="{DynamicResource CardShadow}" ClipToBounds="False">
'@
    $oldBorder = $oldBorder -replace "`r`n", $nl
    $newBorder = $newBorder -replace "`r`n", $nl
    $tile = Replace-Exact $tile $oldBorder $newBorder "ModelCardTile: Classes.selected"

    Set-Content -LiteralPath $tileAxPath -Value $tile -Encoding UTF8 -NoNewline
    Log ("  written (" + $tile.Length + " chars)")
}

# ================================================================
# STEP 5: LibraryView.axaml - group toolbar + CardsHost grid + dialogs
# ================================================================
Log "STEP 5: LibraryView.axaml"

$ax = Get-Content -LiteralPath $libAxPath -Raw -Encoding UTF8
$nl = if ($ax.Contains("`r`n")) { "`r`n" } else { "`n" }

# 5a. Extend Panel.KeyBindings with Esc + Ctrl+A + group dialog Enter/Esc
$oldKB = @'
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmColorPickerCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelColorPickerCommand}" />
        </Panel.KeyBindings>
'@
$newKB = @'
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmColorPickerCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelColorPickerCommand}" />
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmGroupTagCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelGroupTagCommand}" />
            <KeyBinding Gesture="Enter" Command="{Binding ConfirmGroupRemoveCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding CancelGroupRemoveCommand}" />
            <KeyBinding Gesture="Escape" Command="{Binding ClearSelectionCommand}" />
            <KeyBinding Gesture="Ctrl+A" Command="{Binding SelectAllVisibleCommand}" />
        </Panel.KeyBindings>
'@
$oldKB = $oldKB -replace "`r`n", $nl
$newKB = $newKB -replace "`r`n", $nl
$ax = Replace-Exact $ax $oldKB $newKB "LibraryView: KeyBindings"

# 5b. Right grid RowDefinitions Auto,* -> Auto,Auto,*
$oldRowDef = '<Grid Grid.Column="1" RowDefinitions="Auto,*" Background="Transparent">'
$newRowDef = '<Grid Grid.Column="1" RowDefinitions="Auto,Auto,*" Background="Transparent">'
$ax = Replace-Exact $ax $oldRowDef $newRowDef "LibraryView: right grid rows"

# 5c. Insert group toolbar between top toolbar Border and ScrollViewer
$oldBetween = @'
                    <ProgressBar IsIndeterminate="True" IsVisible="{Binding IsBusy}"
                                 Width="120" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>

            <ScrollViewer Grid.Row="1" Background="Transparent" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
                                    <ItemsControl ItemsSource="{Binding Cards}" Margin="4">
                    <ItemsControl.ItemsPanel>
                        <ItemsPanelTemplate>
                            <WrapPanel Orientation="Horizontal" />
                        </ItemsPanelTemplate>
                    </ItemsControl.ItemsPanel>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
                </ScrollViewer>

                <TextBlock Grid.Row="1" Text="{Binding EmptyStateText}"
                           HorizontalAlignment="Center" VerticalAlignment="Center"
                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                           IsVisible="{Binding IsEmpty}"/>
'@
$newBetween = @'
                    <ProgressBar IsIndeterminate="True" IsVisible="{Binding IsBusy}"
                                 Width="120" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>

            <Border Grid.Row="1" IsVisible="{Binding IsMultiSelection}"
                    Background="{DynamicResource GlassPanelBackgroundBrush}"
                    BorderBrush="{DynamicResource GlassPanelBorderBrush}"
                    BorderThickness="1"
                    CornerRadius="{DynamicResource CornerRadiusLarge}"
                    Margin="8,0,8,4" Padding="8,6"
                    BoxShadow="{DynamicResource GlassPanelShadow}">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <TextBlock Text="{Binding GroupSelectionStatusText}"
                               FontWeight="Bold" VerticalAlignment="Center"/>
                    <Button Content="{Binding GroupAddTagMenuText}" Command="{Binding GroupAddTagCommand}"/>
                    <Button Content="{Binding GroupCopyPathsMenuText}" Command="{Binding GroupCopyPathsCommand}"/>
                    <Button Content="{Binding GroupFindDuplicatesMenuText}" Command="{Binding GroupFindDuplicatesCommand}"/>
                    <Button Content="{Binding GroupRemoveMenuText}" Command="{Binding GroupRemoveCommand}"/>
                    <Button Content="{Binding GroupClearText}" Command="{Binding ClearSelectionCommand}"/>
                </StackPanel>
            </Border>

            <ScrollViewer Grid.Row="2" Background="Transparent" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
                <Grid x:Name="CardsHost" Background="Transparent"
                      PointerPressed="OnCardsPointerPressed"
                      PointerMoved="OnCardsPointerMoved"
                      PointerReleased="OnCardsPointerReleased">
                    <ItemsControl x:Name="CardsItemsControl" ItemsSource="{Binding Cards}" Margin="4">
                        <ItemsControl.ItemsPanel>
                            <ItemsPanelTemplate>
                                <WrapPanel Orientation="Horizontal" />
                            </ItemsPanelTemplate>
                        </ItemsControl.ItemsPanel>
                        <ItemsControl.ItemTemplate>
                            <DataTemplate DataType="vm:ModelCardViewModel">
                                <views:ModelCardTile/>
                            </DataTemplate>
                        </ItemsControl.ItemTemplate>
                    </ItemsControl>
                    <Canvas x:Name="SelectionCanvas" IsHitTestVisible="False">
                        <Rectangle x:Name="SelectionRect" IsVisible="False"
                                   Stroke="#E67E22" StrokeThickness="1"
                                   Fill="#20E67E22"/>
                    </Canvas>
                </Grid>
            </ScrollViewer>

            <TextBlock Grid.Row="2" Text="{Binding EmptyStateText}"
                       HorizontalAlignment="Center" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                       IsVisible="{Binding IsEmpty}"/>
'@
$oldBetween = $oldBetween -replace "`r`n", $nl
$newBetween = $newBetween -replace "`r`n", $nl
$ax = Replace-Exact $ax $oldBetween $newBetween "LibraryView: group toolbar + CardsHost grid"

# 5d. Append group dialogs right before final </Panel>
$oldEnd = @'
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
$newEnd = @'
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

        <!-- 0.5.6b.2: Group tag dialog -->
        <Border IsVisible="{Binding ShowGroupTagDialog}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="440"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding GroupTagDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <AutoCompleteBox ItemsSource="{Binding GroupTagCandidates}"
                                     Text="{Binding GroupTagName, Mode=TwoWay}"
                                     Watermark="{Binding GroupTagDialogPlaceholder}"
                                     MinWidth="320"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding GroupTagDialogCancelText}" Command="{Binding CancelGroupTagCommand}" Padding="14,8"/>
                        <Button Content="{Binding GroupTagDialogAddText}" Command="{Binding ConfirmGroupTagCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>

        <!-- 0.5.6b.2: Group remove confirm -->
        <Border IsVisible="{Binding ShowGroupRemoveConfirm}" Background="#80000000">
            <Border Background="{DynamicResource CardBackgroundBrush}"
                    CornerRadius="8" Padding="24" MaxWidth="480"
                    HorizontalAlignment="Center" VerticalAlignment="Center"
                    BoxShadow="0 8 24 0 #50000000">
                <StackPanel Spacing="14">
                    <TextBlock Text="{Binding GroupRemoveDialogTitle}" FontSize="18" FontWeight="Bold"/>
                    <TextBlock Text="{Binding GroupRemoveMessage}" TextWrapping="Wrap" MaxWidth="440"/>
                    <StackPanel Orientation="Horizontal" Spacing="8" HorizontalAlignment="Right">
                        <Button Content="{Binding GroupRemoveDialogCancelText}" Command="{Binding CancelGroupRemoveCommand}" Padding="14,8"/>
                        <Button Content="{Binding GroupRemoveDialogRemoveText}" Command="{Binding ConfirmGroupRemoveCommand}"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Border>
    </Panel>
</UserControl>
'@
$oldEnd = $oldEnd -replace "`r`n", $nl
$newEnd = $newEnd -replace "`r`n", $nl
$ax = Replace-Exact $ax $oldEnd $newEnd "LibraryView: group dialogs"

Set-Content -LiteralPath $libAxPath -Value $ax -Encoding UTF8 -NoNewline
Log ("  LibraryView.axaml written (" + $ax.Length + " chars)")

# post-write sanity
$axBack = Get-Content -LiteralPath $libAxPath -Raw -Encoding UTF8
Assert ($axBack.Contains('x:Name="CardsHost"')) "post-write: CardsHost missing"
Assert ($axBack.Contains('x:Name="SelectionRect"')) "post-write: SelectionRect missing"
Assert ($axBack.Contains('PointerPressed="OnCardsPointerPressed"')) "post-write: PointerPressed handler missing"
Assert ($axBack.Contains('IsVisible="{Binding IsMultiSelection}"')) "post-write: group toolbar visibility missing"
Assert ($axBack.Contains('Command="{Binding GroupAddTagCommand}"')) "post-write: group add tag button missing"
Assert ($axBack.Contains('AutoCompleteBox')) "post-write: AutoCompleteBox missing"
Assert ($axBack.Contains('ShowGroupRemoveConfirm')) "post-write: group remove dialog missing"
$kbCount = [regex]::Matches($axBack, 'Gesture="Escape"').Count
Assert ($kbCount -ge 5) ("post-write: Esc KeyBinding count = $kbCount (expected >=5)")
Log "  post-write verify OK"

# ================================================================
# STEP 6: LibraryView.axaml.cs - full replacement
# ================================================================
Log "STEP 6: LibraryView.axaml.cs"

$cs = @'
using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.VisualTree;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Logging;

namespace MiniCodex.App.Views;

public partial class LibraryView : UserControl
{
    // --- rubber-band state ---
    private bool _rubberActive;
    private Point _rubberStart;
    private Point _rubberCurrent;
    private bool _rubberWasDragged;
    private bool _rubberAdditive;
    private HashSet<ModelCardViewModel> _rubberOriginalSelection = new();

    // --- double-click detection ---
    private DateTime _lastClickTime = DateTime.MinValue;
    private ModelCardViewModel? _lastClickedCard;

    public LibraryView()
    {
        InitializeComponent();
    }

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is LibraryViewModel vm)
            vm.FocusSearchRequested += OnFocusSearchRequested;
    }

    protected override async void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is LibraryViewModel vm)
        {
            vm.FocusSearchRequested -= OnFocusSearchRequested;
            try
            {
                await vm.DisposeAsync();
            }
            catch (Exception ex)
            {
                Log.Exception("[LibraryView] dispose failed", ex);
            }
        }
        base.OnDetachedFromVisualTree(e);
    }

    private void OnFocusSearchRequested(object? sender, EventArgs e)
    {
        SearchBox?.Focus();
    }

    protected override async void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        try
        {
            if (DataContext is LibraryViewModel vm)
            {
                Log.Info("[LibraryView] OnLoaded -> vm.LoadAsync");
                await vm.LoadAsync();
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnLoaded failed", ex); }
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        try
        {
            Log.Info("[LibraryView] OnScanClick begin");
            if (DataContext is not LibraryViewModel vm) return;
            var topLevel = TopLevel.GetTopLevel(this);
            if (topLevel?.StorageProvider is null) return;

            var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = App.Loc?.Get("Library.ScanFolderTitle") ?? "Select source folder",
                AllowMultiple = true,
            });
            Log.Info("[LibraryView] OnScanClick folders=" + folders.Count);
            if (folders.Count == 0) return;

            var paths = folders
                .Select(f => f.TryGetLocalPath())
                .Where(p => !string.IsNullOrEmpty(p))
                .Cast<string>()
                .ToList();
            if (paths.Count == 0) return;

            await vm.ScanAsync(paths);
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnScanClick failed", ex); }
    }

    private void OnTagSelectionChanged(object? sender, Avalonia.Controls.SelectionChangedEventArgs e)
    {
        if (sender is Avalonia.Controls.TreeView tv && tv.SelectedItem is MiniCodex.App.ViewModels.TagNodeViewModel node)
        {
            if (DataContext is MiniCodex.App.ViewModels.LibraryViewModel vm && vm.SelectedTag != node)
            {
                vm.SelectedTag = node;
            }
        }
    }

    // ============================================================
    // Multi-select (0.5.6b.2)
    // ============================================================

    private void OnCardsPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Handled) return;
        if (DataContext is not LibraryViewModel vm) return;
        if (CardsHost == null) return;

        var point = e.GetCurrentPoint(CardsHost);
        var tile = FindAncestor<ModelCardTile>(e.Source as Visual);

        // Right-click: sync selection to the clicked card if not selected.
        if (point.Properties.IsRightButtonPressed)
        {
            if (tile != null && tile.DataContext is ModelCardViewModel rc && !rc.IsSelected)
            {
                vm.ClearSelection();
                rc.IsSelected = true;
                vm.RefreshSelectionCollections();
            }
            return; // let context menu open
        }

        if (!point.Properties.IsLeftButtonPressed) return;

        // Card click (single / Ctrl / Shift / double for open)
        if (tile != null && tile.DataContext is ModelCardViewModel card)
        {
            var isCtrl = (e.KeyModifiers & KeyModifiers.Control) != 0;
            var isShift = (e.KeyModifiers & KeyModifiers.Shift) != 0;

            var now = DateTime.UtcNow;
            if (!isCtrl && !isShift
                && ReferenceEquals(card, _lastClickedCard)
                && (now - _lastClickTime).TotalMilliseconds < 400)
            {
                _lastClickedCard = null;
                _lastClickTime = DateTime.MinValue;
                if (card.OpenCommand.CanExecute(null)) card.OpenCommand.Execute(null);
                e.Handled = true;
                return;
            }
            _lastClickedCard = card;
            _lastClickTime = now;

            vm.OnCardClicked(card, isCtrl, isShift);
            e.Handled = true;
            return;
        }

        // Empty space: start rubber band
        _rubberActive = true;
        _rubberStart = point.Position;
        _rubberCurrent = _rubberStart;
        _rubberWasDragged = false;
        _rubberAdditive = (e.KeyModifiers & KeyModifiers.Control) != 0;
        _rubberOriginalSelection = new HashSet<ModelCardViewModel>(vm.SelectedCards);

        if (!_rubberAdditive)
        {
            foreach (var c in vm.Cards) c.IsSelected = false;
            vm.RefreshSelectionCollections();
        }

        e.Pointer.Capture(CardsHost);
        e.Handled = true;
    }

    private void OnCardsPointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_rubberActive) return;
        if (DataContext is not LibraryViewModel vm) return;
        if (CardsHost == null || SelectionRect == null) return;

        _rubberCurrent = e.GetPosition(CardsHost);
        var dx = Math.Abs(_rubberCurrent.X - _rubberStart.X);
        var dy = Math.Abs(_rubberCurrent.Y - _rubberStart.Y);
        if (dx > 3 || dy > 3) _rubberWasDragged = true;
        if (!_rubberWasDragged) return;

        var rect = new Rect(
            Math.Min(_rubberStart.X, _rubberCurrent.X),
            Math.Min(_rubberStart.Y, _rubberCurrent.Y),
            dx, dy);

        Canvas.SetLeft(SelectionRect, rect.X);
        Canvas.SetTop(SelectionRect, rect.Y);
        SelectionRect.Width = rect.Width;
        SelectionRect.Height = rect.Height;
        SelectionRect.IsVisible = true;

        UpdateRubberSelection(vm, rect);
    }

    private void UpdateRubberSelection(LibraryViewModel vm, Rect rubberRect)
    {
        if (CardsItemsControl == null || CardsHost == null) return;
        var wrapPanel = FindVisualChild<WrapPanel>(CardsItemsControl);
        if (wrapPanel == null) return;

        var intersecting = new HashSet<ModelCardViewModel>();
        foreach (var child in wrapPanel.Children)
        {
            if (child is ContentPresenter cp && cp.Child is ModelCardTile tile
                && tile.DataContext is ModelCardViewModel card)
            {
                var topLeft = tile.TranslatePoint(new Point(0, 0), CardsHost);
                if (topLeft == null) continue;
                var tileRect = new Rect(topLeft.Value, tile.Bounds.Size);
                if (tileRect.Intersects(rubberRect))
                    intersecting.Add(card);
            }
        }

        foreach (var card in vm.Cards)
        {
            card.IsSelected = _rubberAdditive
                ? _rubberOriginalSelection.Contains(card) || intersecting.Contains(card)
                : intersecting.Contains(card);
        }
        vm.RefreshSelectionCollections();
    }

    private void OnCardsPointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_rubberActive) return;
        _rubberActive = false;
        e.Pointer.Capture(null);

        if (SelectionRect != null)
        {
            SelectionRect.IsVisible = false;
            SelectionRect.Width = 0;
            SelectionRect.Height = 0;
        }

        if (DataContext is LibraryViewModel vm)
        {
            if (!_rubberWasDragged && !_rubberAdditive)
            {
                vm.ClearSelection();
            }
            else
            {
                vm.RefreshSelectionCollections();
            }
        }
        e.Handled = true;
    }

    private static T? FindAncestor<T>(Visual? visual) where T : Visual
    {
        var current = visual;
        while (current != null)
        {
            if (current is T t) return t;
            current = current.GetVisualParent();
        }
        return null;
    }

    private static T? FindVisualChild<T>(Visual? parent) where T : Visual
    {
        if (parent == null) return null;
        foreach (var child in parent.GetVisualChildren())
        {
            if (child is T t) return t;
            var res = FindVisualChild<T>(child);
            if (res != null) return res;
        }
        return null;
    }
}
'@
$cs = $cs -replace "`r`n", "`n"
Set-Content -LiteralPath $libCsPath -Value $cs -Encoding UTF8 -NoNewline
Log ("  written (" + $cs.Length + " chars)")

# ================================================================
# STEP 7: lang/en.json - Library.Group.Clear
# ================================================================
Log "STEP 7: lang/en.json"

$en = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8
if ($en.Contains('"Clear":  "Clear"')) {
    Log "  en.json already has Group.Clear - skipping"
} else {
    $enOld = @'
                        "NoDuplicates":  "No duplicates found in selection"
                    }
                },
'@
    $enNew = @'
                        "NoDuplicates":  "No duplicates found in selection",
                        "Clear":  "Clear"
                    }
                },
'@
    $enOld = $enOld -replace "`r`n", "`n"
    $enNew = $enNew -replace "`r`n", "`n"
    $cnt = [regex]::Matches($en, [regex]::Escape($enOld)).Count
    Assert ($cnt -eq 1) ("en.json: Group anchor matched $cnt times")
    $en = $en.Replace($enOld, $enNew)
    Set-Content -LiteralPath $enPath -Value $en -Encoding UTF8 -NoNewline
    try {
        Get-Content -LiteralPath $enPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  en.json written and parses OK"
    } catch { throw ("en.json invalid JSON: " + $_) }
}

# ================================================================
# STEP 8: lang/ru.json - Library.Group.Clear (with \uXXXX)
# ================================================================
Log "STEP 8: lang/ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8
# Detect by ASCII anchor - the 'Clear' key may not have Cyrillic source text we can grep for.
if ($ru.Contains('"Clear":')) {
    Log "  ru.json already has Group.Clear - skipping"
} else {
    $ruOld = @'
                        "NoDuplicates":  "\u0412 \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u0438\u0438 \u043D\u0435\u0442 \u0434\u0443\u0431\u043B\u0438\u043A\u0430\u0442\u043E\u0432"
                    }
                },
'@
    $ruNew = @'
                        "NoDuplicates":  "\u0412 \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u0438\u0438 \u043D\u0435\u0442 \u0434\u0443\u0431\u043B\u0438\u043A\u0430\u0442\u043E\u0432",
                        "Clear":  "\u0421\u0431\u0440\u043E\u0441\u0438\u0442\u044C"
                    }
                },
'@
    # Decode \uXXXX -> real Cyrillic for BOTH old (to find anchor) and new (to write).
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    $ruOldDecoded = [regex]::Replace($ruOld, '\\u([0-9A-Fa-f]{4})', $evaluator)
    $ruNewDecoded = [regex]::Replace($ruNew, '\\u([0-9A-Fa-f]{4})', $evaluator)

    $cnt = [regex]::Matches($ru, [regex]::Escape($ruOldDecoded)).Count
    Assert ($cnt -eq 1) ("ru.json: Group anchor matched $cnt times")
    $ru = $ru.Replace($ruOldDecoded, $ruNewDecoded)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline
    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch { throw ("ru.json invalid JSON: " + $_) }
}

# ================================================================
# STEP 9: CHANGELOG.md
# ================================================================
Log "STEP 9: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.6b.2 applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clEntry = @'

## 0.5.6b.2 - Multi-select (UI)

- ModelCardTile.axaml: amber border (#E67E22, 2px) on IsSelected via Classes.selected style.
- LibraryView.axaml: group toolbar (Row 1) visible when IsMultiSelection; buttons: Add tag / Copy paths / Find duplicates / Remove / Clear.
- LibraryView.axaml: CardsHost Grid wraps ItemsControl and Canvas overlay (SelectionRect for rubber band); PointerPressed/Moved/Released handlers.
- LibraryView.axaml: Esc + Ctrl+A KeyBindings; group dialogs (AutoCompleteBox for tag, red confirm for remove).
- LibraryView.axaml.cs: full click pipeline - plain / Ctrl / Shift click, double-click open (400ms), right-click selection sync, rubber band on empty space with intersection-based selection, Ctrl-held additive mode.
- LibraryViewModel/ModelCardViewModel plumbing: onClick callback, RefreshSelectionCollections public, HasAnyModalOpen guards on ClearSelection/SelectAllVisible, dialog guards in GroupAddTag/GroupRemoveAsync.
- lang/en.json + lang/ru.json: Library.Group.Clear.
<!-- patch 0.5.6b.2 applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then verify in UI; then 0.5.6c (tags/collections polish)" -ForegroundColor Cyan