# patch_0.5.2c.ps1 - Smart Collections + Tag color UI
# One logical step. No C# logic changes beyond ClearColorLabel.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.2c'
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
Write-Log ("Backup dir: {0}" -f $BackupDir)

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.App\Views\LibraryView.axaml',
    'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs',
    'lang\en.json',
    'lang\ru.json',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src = Join-Path $ProjectRoot $rel
    if (-not (Test-Path -LiteralPath $src)) { throw ("Required file missing: {0}" -f $src) }
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. C#: TagNodeViewModel.ClearColorLabel ----------
$tagVmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\TagNodeViewModel.cs'
$tagContent = [IO.File]::ReadAllText($tagVmPath, $utf8NoBom)
if ($tagContent -notmatch 'ClearColorLabel') {
    $nl = if ($tagContent.Contains("`r`n")) { "`r`n" } else { "`n" }
    $old = '    public ICommand ClearColorCommand { get; }'
    $cnt = [regex]::Matches($tagContent, [regex]::Escape($old)).Count
    if ($cnt -ne 1) { throw ("ClearColorLabel anchor: expected 1, got {0}" -f $cnt) }
    $new = $old + $nl + '    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";'
    $tagContent = $tagContent.Replace($old, $new)
    [IO.File]::WriteAllText($tagVmPath, $tagContent, $utf8NoBom)
    Write-Log ("Updated: {0}" -f $tagVmPath)
} else {
    Write-Log 'TagNodeViewModel.cs: ClearColorLabel already present, skip.'
}

# ---------- 3. XAML: 4 targeted Replace-Exact ----------
$axamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'

$editA = @{
    Label = 'sidebar RowDefinitions'
    Old = '<Grid RowDefinitions="Auto,*">'
    New = '<Grid RowDefinitions="Auto,*,Auto,Auto">'
}

$editB = @{
    Label = 'TreeDataTemplate color dot + context menu'
    Old = @'
                                <Grid ColumnDefinitions="*,Auto">
                                    <TextBlock Text="{Binding Name}" TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Grid.Column="1" Text="{Binding UsageCount}"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               FontSize="11" Margin="6,0,0,0"/>
                                </Grid>
'@
    New = @'
                                <Grid ColumnDefinitions="Auto,*,Auto">
                                    <Ellipse Grid.Column="0" Width="8" Height="8" Margin="0,0,6,0"
                                             VerticalAlignment="Center"
                                             Fill="{Binding ColorBrush}"
                                             IsVisible="{Binding HasColor}"/>
                                    <TextBlock Grid.Column="1" Text="{Binding Name}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center">
                                        <TextBlock.ContextMenu>
                                            <ContextMenu>
                                                <MenuItem Header="{Binding ClearColorLabel}" Command="{Binding ClearColorCommand}"/>
                                                <Separator/>
                                                <MenuItem Header="#E67E22" Command="{Binding SetColorCommand}" CommandParameter="#E67E22"/>
                                                <MenuItem Header="#E74C3C" Command="{Binding SetColorCommand}" CommandParameter="#E74C3C"/>
                                                <MenuItem Header="#F39C12" Command="{Binding SetColorCommand}" CommandParameter="#F39C12"/>
                                                <MenuItem Header="#2ECC71" Command="{Binding SetColorCommand}" CommandParameter="#2ECC71"/>
                                                <MenuItem Header="#3498DB" Command="{Binding SetColorCommand}" CommandParameter="#3498DB"/>
                                                <MenuItem Header="#9B59B6" Command="{Binding SetColorCommand}" CommandParameter="#9B59B6"/>
                                                <MenuItem Header="#95A5A6" Command="{Binding SetColorCommand}" CommandParameter="#95A5A6"/>
                                                <MenuItem Header="#34495E" Command="{Binding SetColorCommand}" CommandParameter="#34495E"/>
                                            </ContextMenu>
                                        </TextBlock.ContextMenu>
                                    </TextBlock>
                                    <TextBlock Grid.Column="2" Text="{Binding UsageCount}"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               FontSize="11" Margin="6,0,0,0" VerticalAlignment="Center"/>
                                </Grid>
'@
}

$editC = @{
    Label = 'Collections section after TreeView'
    Old = @'
                    </TreeView>
                </Grid>
'@
    New = @'
                    </TreeView>
                    <Grid Grid.Row="2" ColumnDefinitions="*,Auto">
                        <TextBlock Text="{Binding CollectionsHeader}" FontWeight="Bold" Margin="6,8,6,4" VerticalAlignment="Center"/>
                        <Button Grid.Column="1" Content="&#x00D7;"
                                Command="{Binding DeleteCollectionCommand}"
                                ToolTip.Tip="{Binding DeleteCollectionTooltip}"
                                Background="Transparent" BorderThickness="0"
                                Padding="4,0" FontSize="14"
                                Margin="0,4,4,0" VerticalAlignment="Center"/>
                    </Grid>
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
                </Grid>
'@
}

$editD = @{
    Label = 'toolbar SaveFilter button'
    Old = '<Button Content="{Binding DuplicatesButtonText}" Command="{Binding ToggleDuplicatesCommand}"/>'
    New = '<Button Content="{Binding DuplicatesButtonText}" Command="{Binding ToggleDuplicatesCommand}"/>' + "`n" + '                        <Button Content="{Binding SaveFilterButtonText}" Command="{Binding SaveCurrentFilterAsCollectionCommand}"/>'
}

Replace-Exact $axamlPath @($editA, $editB, $editC, $editD)
Write-Log ("Updated: {0}" -f $axamlPath)

# ---------- 4. lang/en.json ----------
$enPath = Join-Path $ProjectRoot 'lang\en.json'
$enContent = [IO.File]::ReadAllText($enPath, $utf8NoBom)
if ($enContent -notmatch '"CollectionsHeader"') {
    $pattern = '(\r?\n)([ \t]*)\}(\r?\n)([ \t]*)\},(\r?\n)([ \t]*)"Card":'
    $matches = [regex]::Matches($enContent, $pattern)
    if ($matches.Count -ne 1) { throw ("en.json: expected 1 Card anchor, got {0}" -f $matches.Count) }
    $m = $matches[0]
    $g1 = $m.Groups[1].Value
    $g2 = $m.Groups[2].Value
    $g4 = $m.Groups[4].Value
    $g6 = $m.Groups[6].Value
    $nl = $g1
    $block = $g1 + $g2 + '},' +
        $nl + $g2 + '"CollectionsHeader":  "Collections",' +
        $nl + $g2 + '"SaveFilterButton":  "Save filter",' +
        $nl + $g2 + '"SaveFilterEmpty":  "Filter is empty - set a search or a tag first.",' +
        $nl + $g2 + '"DeleteCollection":  "Delete collection",' +
        $nl + $g2 + '"ClearColor":  "Clear color"' +
        $nl + $g4 + '},' +
        $nl + $g6 + '"Card":'
    $enContent = $enContent.Substring(0, $m.Index) + $block + $enContent.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllText($enPath, $enContent, $utf8NoBom)
    try { $null = [IO.File]::ReadAllText($enPath, $utf8NoBom) | ConvertFrom-Json; Write-Log 'en.json parses OK' }
    catch { throw ("en.json JSON parse failed: {0}" -f $_.Exception.Message) }
    Write-Log ("Updated: {0}" -f $enPath)
} else {
    Write-Log 'en.json: CollectionsHeader already present, skip.'
}

# ---------- 5. lang/ru.json ----------
$ruPath = Join-Path $ProjectRoot 'lang\ru.json'
$ruContent = [IO.File]::ReadAllText($ruPath, $utf8NoBom)
if ($ruContent -notmatch '"CollectionsHeader"') {
    $ruCollHeader      = Chars @(0x41A,0x43E,0x43B,0x43B,0x435,0x43A,0x446,0x438,0x438)
    $ruSaveFilter      = Chars @(0x421,0x43E,0x445,0x440,0x430,0x43D,0x438,0x442,0x44C,0x20,0x444,0x438,0x43B,0x44C,0x442,0x440)
    $ruSaveFilterEmpty = Chars @(0x424,0x438,0x43B,0x44C,0x442,0x440,0x20,0x43F,0x443,0x441,0x442,0x20,0x2D,0x20,0x437,0x430,0x434,0x430,0x439,0x442,0x435,0x20,0x43F,0x43E,0x438,0x441,0x43A,0x20,0x438,0x43B,0x438,0x20,0x442,0x435,0x433,0x2E)
    $ruDeleteColl      = Chars @(0x423,0x434,0x430,0x43B,0x438,0x442,0x44C,0x20,0x43A,0x43E,0x43B,0x43B,0x435,0x43A,0x446,0x438,0x44E)
    $ruClearColor      = Chars @(0x421,0x431,0x440,0x43E,0x441,0x438,0x442,0x44C,0x20,0x446,0x432,0x435,0x442)

    $pattern = '(\r?\n)([ \t]*)\}(\r?\n)([ \t]*)\},(\r?\n)([ \t]*)"Card":'
    $matches = [regex]::Matches($ruContent, $pattern)
    if ($matches.Count -ne 1) { throw ("ru.json: expected 1 Card anchor, got {0}" -f $matches.Count) }
    $m = $matches[0]
    $g1 = $m.Groups[1].Value
    $g2 = $m.Groups[2].Value
    $g4 = $m.Groups[4].Value
    $g6 = $m.Groups[6].Value
    $nl = $g1
    $block = $g1 + $g2 + '},' +
        $nl + $g2 + '"CollectionsHeader":  "' + $ruCollHeader + '",' +
        $nl + $g2 + '"SaveFilterButton":  "' + $ruSaveFilter + '",' +
        $nl + $g2 + '"SaveFilterEmpty":  "' + $ruSaveFilterEmpty + '",' +
        $nl + $g2 + '"DeleteCollection":  "' + $ruDeleteColl + '",' +
        $nl + $g2 + '"ClearColor":  "' + $ruClearColor + '"' +
        $nl + $g4 + '},' +
        $nl + $g6 + '"Card":'
    $ruContent = $ruContent.Substring(0, $m.Index) + $block + $ruContent.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllText($ruPath, $ruContent, $utf8NoBom)
    Write-Log ("Updated: {0}" -f $ruPath)
} else {
    Write-Log 'ru.json: CollectionsHeader already present, skip.'
}

# ---------- 6. CHANGELOG ----------
$chPath = Join-Path $ProjectRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $chPath) {
    $c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
    if ($c -notmatch 'patch 0\.5\.2c applied') {
        $nl2 = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
        $entry = $nl2 +
            '## 0.5.2c - Smart Collections + Tag color (UI)' + $nl2 + $nl2 +
            '- LibraryView.axaml: Collections section (header + delete button + ListBox) under the tag tree; per-tag color dot + context menu with 8 swatches + Clear in TreeDataTemplate; "Save filter" button in toolbar.' + $nl2 +
            '- TagNodeViewModel: added ClearColorLabel.' + $nl2 +
            '- lang/en.json + lang/ru.json: 5 new keys (CollectionsHeader, SaveFilterButton, SaveFilterEmpty, DeleteCollection, ClearColor).' + $nl2 + $nl2 +
            '<!-- patch 0.5.2c applied -->' + $nl2
        [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
        Write-Log 'CHANGELOG.md updated.'
    } else {
        Write-Log 'CHANGELOG.md: marker already present, skip.'
    }
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next:'
Write-Log '  1) dotnet build D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  2) dotnet test  D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  3) dotnet run --project D:\AI\MiniCodex\src\MiniCodex.App\MiniCodex.App.csproj'
Write-Log '  Expect: 0 errors, 0 warnings, 55 tests.'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)