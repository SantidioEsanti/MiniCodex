# patch_0.5.3b.3.ps1 - Add IsDefault/IsCancel to dialog buttons (Enter/Esc keyboard support)
# One logical step. XAML only.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3b.3'
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
if ($axCheck -match 'IsDefault="True"') { throw 'Pre-flight: IsDefault already present. 0.5.3b.3 applied.' }
if ($axCheck -notmatch 'ConfirmRenameTagCommand') { throw 'Pre-flight: expected 0.5.3b content not found.' }
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

# ---------- 2. Apply IsDefault/IsCancel to all dialogs ----------
$axPairs = @(
    @{
        Label = 'ScanWarning dialog'
        Old = @'
                        <Button Content="{Binding ScanWarningCancelText}" Command="{Binding CancelScanCommand}" Padding="14,8"/>
                        <Button Content="{Binding ScanWarningContinueText}" Command="{Binding ConfirmScanCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
        New = @'
                        <Button Content="{Binding ScanWarningCancelText}" Command="{Binding CancelScanCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding ScanWarningContinueText}" Command="{Binding ConfirmScanCommand}" IsDefault="True"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
    },
    @{
        Label = 'SaveFilter dialog'
        Old = @'
                        <Button Content="{Binding SaveFilterDialogCancelText}" Command="{Binding CancelSaveFilterCommand}" Padding="14,8"/>
                        <Button Content="{Binding SaveFilterDialogSaveText}" Command="{Binding ConfirmSaveFilterCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
        New = @'
                        <Button Content="{Binding SaveFilterDialogCancelText}" Command="{Binding CancelSaveFilterCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding SaveFilterDialogSaveText}" Command="{Binding ConfirmSaveFilterCommand}" IsDefault="True"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
    },
    @{
        Label = 'RenameTag dialog'
        Old = @'
                        <Button Content="{Binding RenameTagDialogCancelText}" Command="{Binding CancelRenameTagCommand}" Padding="14,8"/>
                        <Button Content="{Binding RenameTagDialogSaveText}" Command="{Binding ConfirmRenameTagCommand}"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
        New = @'
                        <Button Content="{Binding RenameTagDialogCancelText}" Command="{Binding CancelRenameTagCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding RenameTagDialogSaveText}" Command="{Binding ConfirmRenameTagCommand}" IsDefault="True"
                                Background="#E67E22" Foreground="White" Padding="14,8"/>
'@
    },
    @{
        Label = 'DeleteTag dialog'
        Old = @'
                        <Button Content="{Binding DeleteTagDialogCancelText}" Command="{Binding CancelDeleteTagCommand}" Padding="14,8"/>
                        <Button Content="{Binding DeleteTagDialogDeleteText}" Command="{Binding ConfirmDeleteTagCommand}"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
'@
        New = @'
                        <Button Content="{Binding DeleteTagDialogCancelText}" Command="{Binding CancelDeleteTagCommand}" IsCancel="True" Padding="14,8"/>
                        <Button Content="{Binding DeleteTagDialogDeleteText}" Command="{Binding ConfirmDeleteTagCommand}" IsDefault="True"
                                Background="#E74C3C" Foreground="White" Padding="14,8"/>
'@
    }
)
Replace-Exact $axamlPath $axPairs
Write-Log ("Updated: {0}" -f $axamlPath)

# ---------- 3. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3b\.3 applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3b.3 - Enter/Esc in dialogs' + $nl + $nl +
        '- LibraryView.axaml: added IsDefault="True" / IsCancel="True" to all four dialog buttons (ScanWarning, SaveFilter, RenameTag, DeleteTag).' + $nl +
        '- Enter (Key.Return) triggers the default action (Save/Confirm/Continue).' + $nl +
        '- Esc (Key.Escape) triggers the cancel action.' + $nl + $nl +
        '<!-- patch 0.5.3b.3 applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)