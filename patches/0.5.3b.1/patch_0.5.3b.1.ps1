# patch_0.5.3b.1.ps1 - Fix TreeView ContextMenu hit area and color swatches
# One logical step. XAML only.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3b.1'
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

Write-Log ("Patch {0} started" -f $Version)

# ---------- 0. Pre-flight ----------
$axamlPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$chPath    = Join-Path $ProjectRoot 'CHANGELOG.md'

if (-not (Test-Path -LiteralPath $axamlPath)) { throw 'LibraryView.axaml not found.' }
$axCheck = [IO.File]::ReadAllText($axamlPath, $utf8NoBom)
if ($axCheck -match 'HorizontalContentAlignment') { throw 'Pre-flight: already applied.' }
if ($axCheck -notmatch 'TagTreeView') { throw 'Pre-flight: unexpected LibraryView.axaml.' }
Write-Log 'Pre-flight OK.'

# ---------- 1. Backup ----------
$filesToBackup = @('src\MiniCodex.App\Views\LibraryView.axaml', 'CHANGELOG.md')
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

# ---------- 2. Apply XAML fixes ----------
$axPairs = @(
    @{
        Label = 'TreeView stretch header'
        Old = @'
                    <TreeView x:Name="TagTreeView" Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag, Mode=TwoWay}" Background="Transparent" BorderThickness="0">
                        <TreeView.ItemTemplate>
'@
        New = @'
                    <TreeView x:Name="TagTreeView" Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag, Mode=TwoWay}" Background="Transparent" BorderThickness="0">
                        <TreeView.Styles>
                            <Style Selector="TreeViewItem">
                                <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                            </Style>
                        </TreeView.Styles>
                        <TreeView.ItemTemplate>
'@
    },
    @{
        Label = 'TreeDataTemplate ContextMenu on Grid + Color Swatches'
        Old = @'
                                <Grid ColumnDefinitions="Auto,*,Auto">
                                    <Ellipse Grid.Column="0" Width="8" Height="8" Margin="0,0,6,0"
                                             VerticalAlignment="Center"
                                             Fill="{Binding ColorBrush}"
                                             IsVisible="{Binding HasColor}"/>
                                    <TextBlock Grid.Column="1" Text="{Binding Name}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center">
                                        <TextBlock.ContextMenu>
                                            <ContextMenu>
                                                <MenuItem Header="{Binding RenameLabel}" Command="{Binding RenameCommand}"/>
                                                <MenuItem Header="{Binding DeleteLabel}" Command="{Binding DeleteCommand}"/>
                                                <Separator/>
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
        New = @'
                                <Grid ColumnDefinitions="Auto,*,Auto" Background="Transparent">
                                    <Grid.ContextMenu>
                                        <ContextMenu>
                                            <MenuItem Header="{Binding RenameLabel}" Command="{Binding RenameCommand}"/>
                                            <MenuItem Header="{Binding DeleteLabel}" Command="{Binding DeleteCommand}"/>
                                            <Separator/>
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
                                    <Ellipse Grid.Column="0" Width="8" Height="8" Margin="0,0,6,0"
                                             VerticalAlignment="Center"
                                             Fill="{Binding ColorBrush}"
                                             IsVisible="{Binding HasColor}"/>
                                    <TextBlock Grid.Column="1" Text="{Binding Name}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                                    <TextBlock Grid.Column="2" Text="{Binding UsageCount}"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               FontSize="11" Margin="6,0,0,0" VerticalAlignment="Center"/>
                                </Grid>
'@
    }
)
Replace-Exact $axamlPath $axPairs
Write-Log ("Updated: {0}" -f $axamlPath)

# ---------- 3. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3b\.1 applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3b.1 - Tag UI polish' + $nl + $nl +
        '- LibraryView.axaml: ContextMenu moved from TextBlock to root Grid + added HorizontalContentAlignment=Stretch style for TreeViewItem. Now right-click works anywhere on the tag row.' + $nl +
        '- LibraryView.axaml: color swatches use Border (16x16, CornerRadius=8) instead of hex code strings.' + $nl + $nl +
        '<!-- patch 0.5.3b.1 applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)