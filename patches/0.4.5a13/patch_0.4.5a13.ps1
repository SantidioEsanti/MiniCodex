#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a13 - YawDegrees 90deg from 220, theme persistence, auto-save card, preview cleanup.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a13'
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
    Write-Log "Backup: $rel"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# ============ PreviewGeneratorOptions.cs (90deg from 220) ============
$optionsCs = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 384;
    public int Height { get; set; } = 384;
    public float PitchDegrees { get; set; } = 15f;

    // 4 stops over 90deg (220 -> 310). Smoother rotation, starts more "3/4 back".
    public float[] YawDegrees { get; set; } = { 220f, 250f, 280f, 310f };

    public int Supersample { get; set; } = 2;
}
'@

# ============ ModelCardTile.axaml (no gray bg, rounded preview) ============
$cardTileXaml = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardTile"
             x:DataType="vm:ModelCardViewModel">
    <Border Classes="card" Width="220" Height="260" Margin="6" Padding="6">
        <Border.ContextMenu>
            <ContextMenu>
                <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                <Separator/>
                <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                <Separator/>
                <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
            </ContextMenu>
        </Border.ContextMenu>
        <Grid RowDefinitions="180,*,Auto">
            <Border Grid.Row="0" Margin="4" Background="Transparent" CornerRadius="6" ClipToBounds="True">
                <Image Source="{Binding PreviewImage}" Stretch="Uniform"/>
            </Border>

            <Border Grid.Row="0" VerticalAlignment="Bottom" IsVisible="{Binding IsHovered}"
                    Background="#A0000000" CornerRadius="0,0,6,6" Padding="6,3" Margin="4,0,4,4">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <TextBlock Text="{Binding TotalSizeText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding PolygonsText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding FileCountText}" Foreground="#D0D0D0" FontSize="10"
                               IsVisible="{Binding HasMultipleFiles}"/>
                </StackPanel>
            </Border>

            <Button Grid.Row="0"
                    HorizontalAlignment="Right" VerticalAlignment="Top"
                    Margin="8" Padding="6,0" MinWidth="26" MinHeight="26"
                    Content="&#x22EF;"
                    ToolTip.Tip="{Binding MoreActionsTooltip}"
                    IsVisible="{Binding IsHovered}">
                <Button.Flyout>
                    <MenuFlyout Placement="BottomEdgeAlignedRight">
                        <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                        <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                        <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                        <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                        <Separator/>
                        <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                        <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                        <Separator/>
                        <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
                    </MenuFlyout>
                </Button.Flyout>
            </Button>

            <TextBlock Grid.Row="1" Text="{Binding Title}"
                       FontWeight="Bold" TextTrimming="CharacterEllipsis"
                       Margin="0,6,0,0"/>
            <TextBlock Grid.Row="2" FontSize="11"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                       Text="{Binding StatusText}"/>
        </Grid>
    </Border>
</UserControl>
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $optionsPath    = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'
    $previewGenPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    $tilePath       = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardTile.axaml'
    $cardViewPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    $mainVmPath     = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'
    $cardVmPath     = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'

    Backup-File $optionsPath
    Backup-File $previewGenPath
    Backup-File $tilePath
    Backup-File $cardViewPath
    Backup-File $mainVmPath
    Backup-File $cardVmPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ 1. YawDegrees ============
    Write-Text -Path $optionsPath -Content $optionsCs
    Write-Log 'updated: PreviewGeneratorOptions.cs (YawDegrees 220/250/280/310, 90deg span)'

    # ============ 2. RendererVersion bump ============
    $pg = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    $pg = $pg -replace 'RendererVersion\s*=\s*"0\.4\.5a\d+(\.\d+)?"', 'RendererVersion = "0.4.5a13"'
    [IO.File]::WriteAllText($previewGenPath, $pg, [Text.UTF8Encoding]::new($false))
    Write-Log 'updated: PreviewGenerator.cs (RendererVersion = 0.4.5a13)'

    # ============ 3. ModelCardTile.axaml ============
    Write-Text -Path $tilePath -Content $cardTileXaml
    Write-Log 'updated: ModelCardTile.axaml (no gray bg, rounded preview)'

    # ============ 4. ModelCardView.axaml - remove Save button ============
    $cv = [IO.File]::ReadAllText($cardViewPath, [Text.Encoding]::UTF8)
    $saveBtnOld = '<Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>' + "`r`n" + '            '
    if ($cv.Contains($saveBtnOld)) {
        $cv = $cv.Replace($saveBtnOld, '')
        [IO.File]::WriteAllText($cardViewPath, $cv, [Text.UTF8Encoding]::new($false))
        Write-Log 'XAML: removed Save button from ModelCardView (auto-save active)'
    } elseif ($cv -match 'SaveCommand') {
        # Try without trailing whitespace
        $saveBtnOld2 = '<Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>'
        $cv = $cv.Replace($saveBtnOld2, '')
        [IO.File]::WriteAllText($cardViewPath, $cv, [Text.UTF8Encoding]::new($false))
        Write-Log 'XAML: removed Save button (fallback)'
    } else {
        Write-Log 'XAML: Save button not found' 'WARN'
    }

    # ============ 5. MainWindowViewModel: theme persistence ============
    $mainVm = [IO.File]::ReadAllText($mainVmPath, [Text.Encoding]::UTF8)

    # 5a. Add theme load at start of ctor
    $ctorStartOld = '        Library = new LibraryViewModel('
    $ctorStartNew = @'
        // Load saved theme (sync, one-time at startup, ~1ms)
        string initialTheme = "auto";
        try
        {
            if (AppServices.Settings != null)
            {
                var saved = AppServices.Settings.GetAsync("UI.Theme").GetAwaiter().GetResult();
                if (!string.IsNullOrEmpty(saved) && (saved == "light" || saved == "dark" || saved == "auto"))
                {
                    initialTheme = saved;
                }
            }
        }
        catch { }
        _theme = initialTheme;
        App.Theme?.Apply(initialTheme);

        Library = new LibraryViewModel(
'@
    if ($mainVm.Contains($ctorStartOld) -and ($mainVm -notmatch 'Load saved theme')) {
        $mainVm = $mainVm.Replace($ctorStartOld, $ctorStartNew)
        Write-Log 'MainVM: theme load in ctor'
    }

    # 5b. Add save on setter
    $setterOld = @'
        if (!Set(ref _theme, value)) return;
        App.Theme?.Apply(value);
        Raise(nameof(ThemeIconGlyph));
        Raise(nameof(ThemeTooltip));
    }
'@
    $setterNew = @'
        if (!Set(ref _theme, value)) return;
        App.Theme?.Apply(value);
        Raise(nameof(ThemeIconGlyph));
        Raise(nameof(ThemeTooltip));
        _ = SaveThemeAsync(value);
    }

    private static async Task SaveThemeAsync(string theme)
    {
        if (AppServices.Settings == null) return;
        try { await AppServices.Settings.SetAsync("UI.Theme", theme); } catch { }
    }
'@
    $mainVmNorm = $mainVm -replace "`r`n", "`n"
    $setterOldNorm = $setterOld -replace "`r`n", "`n"
    if ($mainVmNorm.Contains($setterOldNorm)) {
        $mainVmNorm = $mainVmNorm.Replace($setterOldNorm, ($setterNew -replace "`r`n", "`n"))
        $mainVm = $mainVmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'MainVM: theme save on setter + SaveThemeAsync helper'
    } else {
        Write-Log 'MainVM: setter pattern not found' 'WARN'
    }

    # Ensure 'using System.Threading.Tasks;' present (MainWindowViewModel likely has ImplicitUsings so Task available)
    [IO.File]::WriteAllText($mainVmPath, $mainVm, [Text.UTF8Encoding]::new($false))

    # ============ 6. ModelCardPageViewModel: auto-save ============
    $cardVm = [IO.File]::ReadAllText($cardVmPath, [Text.Encoding]::UTF8)

    # 6a. Add _saveDebounceCts field after existing fields near top (after _onBack)
    $anchor = '    private readonly Action _onBack;'
    $newAnchor = $anchor + "`r`n" + '    private CancellationTokenSource? _saveDebounceCts;'
    if ($cardVm.Contains($anchor) -and ($cardVm -notmatch '_saveDebounceCts')) {
        $cardVm = $cardVm.Replace($anchor, $newAnchor)
        Write-Log 'VM: added _saveDebounceCts field'
    }

    # 6b. Modify text setters: add ScheduleSave
    # Title
    $titleOld = 'public string Title { get => _title; set { _title = value; Raise(); } }'
    $titleNew = 'public string Title { get => _title; set { if (_title != value) { _title = value; Raise(); ScheduleSave(); } } }'
    if ($cardVm.Contains($titleOld)) { $cardVm = $cardVm.Replace($titleOld, $titleNew); Write-Log 'VM: Title autosave' }

    # Author
    $authorOld = 'public string Author { get => _author; set { _author = value; Raise(); } }'
    $authorNew = 'public string Author { get => _author; set { if (_author != value) { _author = value; Raise(); ScheduleSave(); } } }'
    if ($cardVm.Contains($authorOld)) { $cardVm = $cardVm.Replace($authorOld, $authorNew); Write-Log 'VM: Author autosave' }

    # SourceUrl
    $srcOld = 'public string SourceUrl { get => _sourceUrl; set { _sourceUrl = value; Raise(); } }'
    $srcNew = 'public string SourceUrl { get => _sourceUrl; set { if (_sourceUrl != value) { _sourceUrl = value; Raise(); ScheduleSave(); } } }'
    if ($cardVm.Contains($srcOld)) { $cardVm = $cardVm.Replace($srcOld, $srcNew); Write-Log 'VM: SourceUrl autosave' }

    # Notes
    $notesOld = 'public string Notes { get => _notes; set { _notes = value; Raise(); } }'
    $notesNew = 'public string Notes { get => _notes; set { if (_notes != value) { _notes = value; Raise(); ScheduleSave(); } } }'
    if ($cardVm.Contains($notesOld)) { $cardVm = $cardVm.Replace($notesOld, $notesNew); Write-Log 'VM: Notes autosave' }

    # 6c. RealHeightMmText: add ScheduleSave after parse block
    $realOld = @'
            if (float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var mm)
                && mm > 0 && TryGetDenom(out var d))
            {
                var mh = ScaleCatalog.CalculateModelHeightMm(mm, d);
                if (mh != null) SetHeightsInternal(null, mh.Value);
            }
        }
    }
'@
    $realNew = @'
            if (float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var mm)
                && mm > 0 && TryGetDenom(out var d))
            {
                var mh = ScaleCatalog.CalculateModelHeightMm(mm, d);
                if (mh != null) SetHeightsInternal(null, mh.Value);
            }
            ScheduleSave();
        }
    }
'@
    # There are two such blocks (Real and Model). Replace all occurrences.
    $countReal = ([regex]::Matches($cardVm, [regex]::Escape(($realOld -replace "`r`n", "`n")))).Count
    if ($countReal -eq 0) {
        # Try with normalized LF
        $cardVmNorm = $cardVm -replace "`r`n", "`n"
        if ($cardVmNorm.Contains(($realOld -replace "`r`n", "`n"))) {
            $cardVmNorm = $cardVmNorm.Replace(($realOld -replace "`r`n", "`n"), ($realNew -replace "`r`n", "`n"))
            $cardVm = $cardVmNorm -replace "(?<!`r)`n", "`r`n"
            Write-Log 'VM: scale autosave (LF) - Real + Model height'
        } else {
            Write-Log 'VM: scale autosave block not found' 'WARN'
        }
    }

    # 6d. OnScaleChanged: add ScheduleSave
    $onScaleOld = @'
    private void OnScaleChanged()
    {
        if (_updatingHeights) return;
        if (float.TryParse(_realHeightMmText, NumberStyles.Float, CultureInfo.InvariantCulture, out var realMm)
            && realMm > 0 && TryGetDenom(out var d))
        {
            var mh = ScaleCatalog.CalculateModelHeightMm(realMm, d);
            if (mh != null) SetHeightsInternal(null, mh.Value);
        }
    }
'@
    $onScaleNew = @'
    private void OnScaleChanged()
    {
        if (_updatingHeights) return;
        if (float.TryParse(_realHeightMmText, NumberStyles.Float, CultureInfo.InvariantCulture, out var realMm)
            && realMm > 0 && TryGetDenom(out var d))
        {
            var mh = ScaleCatalog.CalculateModelHeightMm(realMm, d);
            if (mh != null) SetHeightsInternal(null, mh.Value);
        }
        ScheduleSave();
    }

    private void ScheduleSave()
    {
        _saveDebounceCts?.Cancel();
        _saveDebounceCts = new CancellationTokenSource();
        _ = DebouncedSaveAsync(_saveDebounceCts.Token);
    }

    private async Task DebouncedSaveAsync(CancellationToken ct)
    {
        try
        {
            await Task.Delay(500, ct);
            await SaveAsync();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { Log.Exception("[ModelCardPageViewModel] autosave failed", ex); }
    }
'@
    $cardVmNorm = $cardVm -replace "`r`n", "`n"
    $onScaleOldNorm = $onScaleOld -replace "`r`n", "`n"
    if ($cardVmNorm.Contains($onScaleOldNorm) -and ($cardVm -notmatch 'private void ScheduleSave')) {
        $cardVmNorm = $cardVmNorm.Replace($onScaleOldNorm, ($onScaleNew -replace "`r`n", "`n"))
        $cardVm = $cardVmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: ScheduleSave/DebouncedSaveAsync + OnScaleChanged autosave'
    } else {
        Write-Log 'VM: OnScaleChanged block not found or ScheduleSave already present' 'WARN'
    }

    [IO.File]::WriteAllText($cardVmPath, $cardVm, [Text.UTF8Encoding]::new($false))

    # README
    $readme = @'
# Patch 0.4.5a13 - Final polish

**Iteration:** 0.4.5

## What it does

1. YawDegrees { 180, 220, 260, 300 } -> { 220, 250, 280, 310 }.
   Range 90deg (was 120). 4 stops at 30deg apart. Starts at 220 (3/4 back).

2. Theme persistence (Setting "UI.Theme"):
   - MainWindowViewModel ctor loads saved theme synchronously (one-time, ~1ms).
   - Setter saves on each change.

3. Auto-save in model card:
   - Text fields Title, Author, SourceUrl, Notes: debounce 500ms -> SaveAsync.
   - Scale fields (RealHeightMmText, ModelHeightMmText, OnScaleChanged): debounce 500ms -> SaveAsync.
   - Status/Difficulty were already auto-saved (0.4.3e.1).
   - Tags, primary file were already auto-saved via commands.
   - Save button removed from toolbar. "Saved" status still appears after autosave.

4. Library preview cleanup:
   - ModelCardTile.axaml: gray background around preview removed (Background=Transparent).
   - Image wrapped in Border with CornerRadius=6 + ClipToBounds=True: preview itself rounded.
   - Hover overlay aligned to new margins.

5. RendererVersion 0.4.5a13 (angles changed -> regen needed).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Library: no gray rectangle around preview; preview corners rounded.
- Model card: Save button gone. Type in Title -> after 500ms "Saved" appears.
- Change theme -> close app -> reopen -> theme restored.
- Hover rotation: 30deg steps.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a13\README.md'

    # Verify
    $vOpt = [IO.File]::ReadAllText($optionsPath, [Text.Encoding]::UTF8)
    if ($vOpt -match '220f, 250f, 280f, 310f') { Write-Log 'verify OK: 90deg angles' } else { Write-Log 'verify FAIL: angles wrong' 'WARN' }

    $vP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($vP -match '"0\.4\.5a13"') { Write-Log 'verify OK: RendererVersion 0.4.5a13' }

    $vTile = [IO.File]::ReadAllText($tilePath, [Text.Encoding]::UTF8)
    if ($vTile -match 'ClipToBounds="True"') { Write-Log 'verify OK: preview clipped' }
    if ($vTile -notmatch 'SystemControlBackgroundBaseLowBrush') { Write-Log 'verify OK: gray bg removed from tile' } else { Write-Log 'verify FAIL: gray bg still in tile' 'WARN' }

    $vMain = [IO.File]::ReadAllText($mainVmPath, [Text.Encoding]::UTF8)
    if ($vMain -match 'UI\.Theme') { Write-Log 'verify OK: theme persistence' }

    $vCard = [IO.File]::ReadAllText($cardVmPath, [Text.Encoding]::UTF8)
    if ($vCard -match 'ScheduleSave') { Write-Log 'verify OK: ScheduleSave' }
    if ($vCard -match '_saveDebounceCts') { Write-Log 'verify OK: _saveDebounceCts' }

    $vCv = [IO.File]::ReadAllText($cardViewPath, [Text.Encoding]::UTF8)
    if ($vCv -notmatch 'SaveButtonText') { Write-Log 'verify OK: Save button removed from ModelCardView' } else { Write-Log 'verify WARN: Save button still in ModelCardView' 'WARN' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a13 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a13] - 2026-11-13`r`n`r`n### Changed`r`n- YawDegrees 220/250/280/310 (90deg span, 30deg apart).`r`n- Theme persisted in Setting (UI.Theme).`r`n- Model card auto-saves all fields (500ms debounce), Save button removed.`r`n- Library preview: no gray bg, rounded corners on image.`r`n- RendererVersion 0.4.5a13.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a12\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}