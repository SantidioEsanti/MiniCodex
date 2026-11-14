# patch_0.5.3b.2.ps1 - Fix TreeViewItem style (HorizontalContentAlignment not available on TreeViewItem in Avalonia 11)
# One logical step. XAML only.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3b.2'
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
if ($axCheck -notmatch 'HorizontalContentAlignment') { throw 'Pre-flight: expected broken 0.5.3b.1 style not found.' }
if ($axCheck -match 'PART_HeaderPresenter') { throw 'Pre-flight: already applied.' }
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

# ---------- 2. Fix style ----------
$axPairs = @(
    @{
        Label = 'replace TreeViewItem style with PART_HeaderPresenter'
        Old = @'
                        <TreeView.Styles>
                            <Style Selector="TreeViewItem">
                                <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                            </Style>
                        </TreeView.Styles>
'@
        New = @'
                        <TreeView.Styles>
                            <Style Selector="TreeViewItem /template/ ContentPresenter#PART_HeaderPresenter">
                                <Setter Property="HorizontalAlignment" Value="Stretch"/>
                                <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                            </Style>
                        </TreeView.Styles>
'@
    }
)
Replace-Exact $axamlPath $axPairs
Write-Log ("Updated: {0}" -f $axamlPath)

# ---------- 3. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3b\.2 applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3b.2 - Fix TreeViewItem style' + $nl + $nl +
        '- LibraryView.axaml: TreeViewItem does not have HorizontalContentAlignment in Avalonia 11. Replaced with Style Selector="TreeViewItem /template/ ContentPresenter#PART_HeaderPresenter" and both HorizontalAlignment and HorizontalContentAlignment set to Stretch.' + $nl +
        '- This makes the whole tag row stretch, so ContextMenu opens on right-click anywhere on the highlighted row.' + $nl + $nl +
        '<!-- patch 0.5.3b.2 applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)