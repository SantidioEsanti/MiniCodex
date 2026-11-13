#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3e - Status as 3 icon buttons, Difficulty as 5 stars.
.DESCRIPTION
    ModelCardPageViewModel: DifficultyValue, IsPlanned/Printed/Painted, Star glyphs, SetStatus/SetDifficulty commands.
    ModelCardView.axaml: replace Status/Difficulty TextBoxes with buttons+stars.
    App.axaml: Button.statusActive and Button.star styles.
    ASCII-only script (Unicode escapes in C# strings via \uXXXX).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3e'
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

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $vmPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $xamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    $appPath  = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml'

    Backup-File $vmPath
    Backup-File $xamlPath
    Backup-File $appPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # ============ VM edits ============
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)

    # --- VM Edit 1: add difficulty value field + computed props after Difficulty ---
    if ($vm -notmatch 'Star1Glyph') {
        $oldDiffBlock = '    private string _difficulty = string.Empty;' + "`r`n" +
                        '    public string Difficulty { get => _difficulty; set { _difficulty = value; Raise(); } }'
        $newDiffBlock = @'
    private string _difficulty = string.Empty;
    public string Difficulty { get => _difficulty; set { _difficulty = value; Raise(); } }

    private int _difficultyValue;
    public bool IsPlanned => string.Equals(_status, "planned", StringComparison.OrdinalIgnoreCase);
    public bool IsPrinted => string.Equals(_status, "printed", StringComparison.OrdinalIgnoreCase);
    public bool IsPainted => string.Equals(_status, "painted", StringComparison.OrdinalIgnoreCase);

    public int DifficultyValue
    {
        get => _difficultyValue;
        set
        {
            var clamped = Math.Clamp(value, 0, 5);
            if (_difficultyValue == clamped) return;
            _difficultyValue = clamped;
            _difficulty = clamped > 0 ? clamped.ToString(CultureInfo.InvariantCulture) : string.Empty;
            Raise();
            Raise(nameof(Difficulty));
            Raise(nameof(Star1Glyph));
            Raise(nameof(Star2Glyph));
            Raise(nameof(Star3Glyph));
            Raise(nameof(Star4Glyph));
            Raise(nameof(Star5Glyph));
        }
    }

    public string Star1Glyph => _difficultyValue >= 1 ? "\u2605" : "\u2606";
    public string Star2Glyph => _difficultyValue >= 2 ? "\u2605" : "\u2606";
    public string Star3Glyph => _difficultyValue >= 3 ? "\u2605" : "\u2606";
    public string Star4Glyph => _difficultyValue >= 4 ? "\u2605" : "\u2606";
    public string Star5Glyph => _difficultyValue >= 5 ? "\u2605" : "\u2606";

    public string StatusPlannedLabel => Loc("Library.Status.Planned", "Planned");
    public string StatusPrintedLabel => Loc("Library.Status.Printed", "Printed");
    public string StatusPaintedLabel => Loc("Library.Status.Painted", "Painted");
'@
        if ($vm.Contains($oldDiffBlock)) {
            $vm = $vm.Replace($oldDiffBlock, $newDiffBlock)
            Write-Log 'VM: added difficulty value + computed properties'
        } else {
            Write-Log 'VM: difficulty block marker not found' 'WARN'
        }
    }

    # --- VM Edit 2: add command declarations ---
    if ($vm -notmatch 'SetStatusCommand\s*\{\s*get;\s*\}') {
        $oldCmdDecl = '    public ICommand ApplyManualScaleCommand { get; }'
        $newCmdDecl = '    public ICommand ApplyManualScaleCommand { get; }' + "`r`n" +
                      '    public ICommand SetStatusCommand { get; }' + "`r`n" +
                      '    public ICommand SetDifficultyCommand { get; }'
        if ($vm.Contains($oldCmdDecl)) {
            $vm = $vm.Replace($oldCmdDecl, $newCmdDecl)
            Write-Log 'VM: added SetStatusCommand/SetDifficultyCommand declarations'
        }
    }

    # --- VM Edit 3: init commands in constructor ---
    $oldCmdInit = '        ApplyManualScaleCommand = new RelayCommand(ApplyManualScale);'
    $newCmdInit = '        ApplyManualScaleCommand = new RelayCommand(ApplyManualScale);' + "`r`n" +
                  '        SetStatusCommand = new RelayCommand(p => SetStatus(p as string));' + "`r`n" +
                  '        SetDifficultyCommand = new RelayCommand(p => SetDifficulty(p as string));'
    if ($vm.Contains($oldCmdInit) -and ($vm -notmatch 'SetStatusCommand = new RelayCommand')) {
        $vm = $vm.Replace($oldCmdInit, $newCmdInit)
        Write-Log 'VM: added SetStatus/SetDifficulty command init'
    }

    # --- VM Edit 4: init _difficultyValue from model ---
    $oldInit = '        _difficulty = model.Difficulty?.ToString() ?? string.Empty;'
    $newInit = '        _difficulty = model.Difficulty?.ToString() ?? string.Empty;' + "`r`n" +
               '        _difficultyValue = model.Difficulty ?? 0;'
    if ($vm.Contains($oldInit) -and ($vm -notmatch '_difficultyValue = model\.Difficulty')) {
        $vm = $vm.Replace($oldInit, $newInit)
        Write-Log 'VM: initialized _difficultyValue from model'
    }

    # --- VM Edit 5: add handlers after ApplyManualScale method ---
    $oldAms = '        ScaleStatus = string.Format(Loc("Card.Scale.AppliedFormat", "Applied: 1:{0}"), m.Value.ToString("0.##", CultureInfo.InvariantCulture));' + "`r`n" +
              '        OnScaleChanged();' + "`r`n" +
              '    }'
    $newAms = $oldAms + "`r`n" + "`r`n" +
              '    private void SetStatus(string? s)' + "`r`n" +
              '    {' + "`r`n" +
              '        if (string.IsNullOrEmpty(s)) return;' + "`r`n" +
              '        _status = s;' + "`r`n" +
              '        Raise(nameof(Status));' + "`r`n" +
              '        Raise(nameof(IsPlanned));' + "`r`n" +
              '        Raise(nameof(IsPrinted));' + "`r`n" +
              '        Raise(nameof(IsPainted));' + "`r`n" +
              '    }' + "`r`n" + "`r`n" +
              '    private void SetDifficulty(string? s)' + "`r`n" +
              '    {' + "`r`n" +
              '        if (s == null || !int.TryParse(s, out var v)) return;' + "`r`n" +
              '        if (v < 1 || v > 5) return;' + "`r`n" +
              '        DifficultyValue = (DifficultyValue == v) ? 0 : v;' + "`r`n" +
              '    }'
    if ($vm.Contains($oldAms) -and ($vm -notmatch 'private void SetStatus\(')) {
        $vm = $vm.Replace($oldAms, $newAms)
        Write-Log 'VM: added SetStatus/SetDifficulty handlers'
    }

    # --- VM Edit 6: update Save to use _difficultyValue ---
    $oldSave = '            Model.Difficulty = int.TryParse(Difficulty, out var d) ? Math.Clamp(d, 1, 5) : null;'
    $newSave = '            Model.Difficulty = _difficultyValue > 0 ? (int?)_difficultyValue : null;'
    if ($vm.Contains($oldSave)) {
        $vm = $vm.Replace($oldSave, $newSave)
        Write-Log 'VM: Save uses _difficultyValue'
    }

    # --- VM Edit 7: RefreshLocalized adds Status labels ---
    $oldRefresh = '        Raise(nameof(LabelStatus));'
    if ($vm.Contains($oldRefresh) -and ($vm -notmatch 'Raise\(nameof\(StatusPlannedLabel\)\)')) {
        $newRefresh = '        Raise(nameof(LabelStatus));' + "`r`n" +
                      '        Raise(nameof(StatusPlannedLabel));' + "`r`n" +
                      '        Raise(nameof(StatusPrintedLabel));' + "`r`n" +
                      '        Raise(nameof(StatusPaintedLabel));'
        $vm = $vm.Replace($oldRefresh, $newRefresh)
        Write-Log 'VM: RefreshLocalized includes Status labels'
    }

    [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))

    # ============ XAML: replace Status/Difficulty block ============
    $xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
    if ($xaml -notmatch 'SetStatusCommand') {
        $oldXaml = '                            <TextBlock Text="{Binding LabelStatus}"/>' + "`r`n" +
                   '                            <TextBox Text="{Binding Status}"/>' + "`r`n" +
                   '                            <TextBlock Text="{Binding LabelDifficulty}"/>' + "`r`n" +
                   '                            <TextBox Text="{Binding Difficulty}"/>'
        $newXaml = @'
                            <TextBlock Text="{Binding LabelStatus}"/>
                            <StackPanel Orientation="Horizontal" Spacing="6">
                                <Button Classes.statusActive="{Binding IsPlanned}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="planned"
                                        ToolTip.Tip="{Binding StatusPlannedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="36">
                                    <TextBlock Text="&#xE823;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18"/>
                                </Button>
                                <Button Classes.statusActive="{Binding IsPrinted}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="printed"
                                        ToolTip.Tip="{Binding StatusPrintedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="36">
                                    <TextBlock Text="&#xE749;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18"/>
                                </Button>
                                <Button Classes.statusActive="{Binding IsPainted}"
                                        Command="{Binding SetStatusCommand}" CommandParameter="painted"
                                        ToolTip.Tip="{Binding StatusPaintedLabel}"
                                        Padding="10,6" MinWidth="44" MinHeight="36">
                                    <TextBlock Text="&#xE8FB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18"/>
                                </Button>
                            </StackPanel>
                            <TextBlock Text="{Binding LabelDifficulty}"/>
                            <StackPanel Orientation="Horizontal" Spacing="0">
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="1">
                                    <TextBlock Text="{Binding Star1Glyph}" FontSize="22" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="2">
                                    <TextBlock Text="{Binding Star2Glyph}" FontSize="22" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="3">
                                    <TextBlock Text="{Binding Star3Glyph}" FontSize="22" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="4">
                                    <TextBlock Text="{Binding Star4Glyph}" FontSize="22" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                                <Button Classes="star" Command="{Binding SetDifficultyCommand}" CommandParameter="5">
                                    <TextBlock Text="{Binding Star5Glyph}" FontSize="22" Foreground="{DynamicResource SystemAccentColorBrush}"/>
                                </Button>
                            </StackPanel>
'@
        if ($xaml.Contains($oldXaml)) {
            $xaml = $xaml.Replace($oldXaml, $newXaml)
            [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))
            Write-Log 'XAML: replaced Status/Difficulty with buttons+stars'
        } else {
            Write-Log 'XAML: Status/Difficulty block not found' 'WARN'
        }
    } else {
        Write-Log 'XAML: SetStatusCommand already present, skipping.' 'WARN'
    }

    # ============ App.axaml: add styles ============
    $app = [IO.File]::ReadAllText($appPath, [Text.Encoding]::UTF8)
    if ($app -notmatch 'Button\.statusActive') {
        $oldStyleMarker = '        <Style Selector="ComboBox">' + "`r`n" +
                          '            <Setter Property="CornerRadius" Value="6"/>' + "`r`n" +
                          '        </Style>'
        $newStyles = $oldStyleMarker + "`r`n" + "`r`n" +
                     '        <Style Selector="Button.statusActive">' + "`r`n" +
                     '            <Setter Property="Background" Value="#E67E22"/>' + "`r`n" +
                     '            <Setter Property="Foreground" Value="White"/>' + "`r`n" +
                     '        </Style>' + "`r`n" + "`r`n" +
                     '        <Style Selector="Button.star">' + "`r`n" +
                     '            <Setter Property="Background" Value="Transparent"/>' + "`r`n" +
                     '            <Setter Property="BorderThickness" Value="0"/>' + "`r`n" +
                     '            <Setter Property="Padding" Value="2,0"/>' + "`r`n" +
                     '            <Setter Property="CornerRadius" Value="0"/>' + "`r`n" +
                     '        </Style>' + "`r`n" + "`r`n" +
                     '        <Style Selector="Button.star:pointerover">' + "`r`n" +
                     '            <Setter Property="Background" Value="#20E67E22"/>' + "`r`n" +
                     '        </Style>'
        if ($app.Contains($oldStyleMarker)) {
            $app = $app.Replace($oldStyleMarker, $newStyles)
            [IO.File]::WriteAllText($appPath, $app, [Text.UTF8Encoding]::new($false))
            Write-Log 'App.axaml: added Button.statusActive / Button.star styles'
        } else {
            Write-Log 'App.axaml: ComboBox style marker not found' 'WARN'
        }
    } else {
        Write-Log 'App.axaml: statusActive style already present, skipping.' 'WARN'
    }

    # ============ README ============
    $readme = @'
# Patch 0.4.3e - Status as 3 icon buttons, Difficulty as 5 stars

**Iteration:** 0.4

## What it does

- ModelCardPageViewModel:
  - _difficultyValue (int), DifficultyValue property.
  - IsPlanned/IsPrinted/IsPainted (bool) - for Classes.statusActive binding.
  - Star1Glyph..Star5Glyph - filled/empty star Unicode glyphs.
  - SetStatusCommand / SetDifficultyCommand.
  - SetDifficulty: click same value -> toggle to 0.
  - Save uses _difficultyValue (int).
  - Load initializes _difficultyValue from Model.Difficulty.
- ModelCardView.axaml:
  - Status: 3 icon buttons (Clock / Print / CheckMark) via Segoe Fluent Icons.
  - Difficulty: 5 clickable stars, amber.
- App.axaml:
  - Style Button.statusActive: amber background, white foreground.
  - Style Button.star: transparent bg, no border.
  - Style Button.star:pointerover: light amber hover.

## Notes

- Status and Difficulty changes are LOCAL until user clicks Save.
- If highlighting (Classes.statusActive) does not work on some Avalonia version,
  fix in follow-up patch.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Card Info panel: Status = 3 icon buttons, Difficulty = 5 stars.
- Click status icon -> highlights amber.
- Click star N -> first N stars filled, rest empty.
- Click same star again -> clears to 0.
- Save -> reopen -> values preserved.
'@
    $readmePath = Join-Path $PatchDir 'README.md'
    [IO.File]::WriteAllText($readmePath, $readme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.3e\README.md'

    # ============ CHANGELOG ============
    $marker = '<!-- patch 0.4.3e applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3e] - 2026-11-12`r`n`r`n### Changed`r`n- Status: 3 icon buttons (Segoe Fluent Icons) instead of text field.`r`n- Difficulty: 5 clickable stars instead of text field.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3d\].*)$', "$entry`$1"
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