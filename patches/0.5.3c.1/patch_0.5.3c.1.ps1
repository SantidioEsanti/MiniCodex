# patch_0.5.3c.1.ps1 - Fix JSON lang files for 0.5.3c
# Repairs en.json (remove from Common, add to TagContextMenu) and applies ru.json keys.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3c.1'
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

$enPath = Join-Path $ProjectRoot 'lang\en.json'
$ruPath = Join-Path $ProjectRoot 'lang\ru.json'
$chPath = Join-Path $ProjectRoot 'CHANGELOG.md'

$filesToBackup = @('lang\en.json', 'lang\ru.json', 'CHANGELOG.md')
foreach ($rel in $filesToBackup) {
    $src    = Join-Path $ProjectRoot $rel
    $dst    = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- Fix en.json ----------
$enPairs = @(
    @{
        Label = 'remove bad CustomColor from Common'
        Old = @'
                   "Delete":  "Delete",
                        "CustomColor":  "Custom color..."
                   "Close":  "Close",
'@
        New = @'
                   "Delete":  "Delete",
                   "Close":  "Close",
'@
    },
    @{
        Label = 'add CustomColor to TagContextMenu'
        Old = @'
                    "TagContextMenu":  {
                        "Rename":  "Rename...",
                        "Delete":  "Delete"
                    },
'@
        New = @'
                    "TagContextMenu":  {
                        "Rename":  "Rename...",
                        "Delete":  "Delete",
                        "CustomColor":  "Custom color..."
                    },
'@
    }
)
Replace-Exact $enPath $enPairs
$null = [IO.File]::ReadAllText($enPath, $utf8NoBom) | ConvertFrom-Json
Write-Log ("en.json fixed and valid.")

# ---------- Fix ru.json ----------
$ruPairs = @(
    @{
        Label = 'add CustomColor to TagContextMenu'
        Old = @'
                    "TagContextMenu":  {
                        "Rename":  "Переименовать...",
                        "Delete":  "Удалить"
                    },
'@
        New = @'
                    "TagContextMenu":  {
                        "Rename":  "Переименовать...",
                        "Delete":  "Удалить",
                        "CustomColor":  "Свой цвет..."
                    },
'@
    },
    @{
        Label = 'add ColorPickerDialog after DeleteTagDialog'
        Old = @'
                    "DeleteTagDialog":  {
                        "Title":  "Удалить тег?",
                        "Message":  "Удалить тег {0}? Связанных записей: {1}.",
                        "Delete":  "Удалить",
                        "Cancel":  "Отмена"
                    }
'@
        New = @'
                    "DeleteTagDialog":  {
                        "Title":  "Удалить тег?",
                        "Message":  "Удалить тег {0}? Связанных записей: {1}.",
                        "Delete":  "Удалить",
                        "Cancel":  "Отмена"
                    },
                    "ColorPickerDialog":  {
                        "Title":  "Свой цвет",
                        "Placeholder":  "#RRGGBB",
                        "Save":  "Сохранить",
                        "Cancel":  "Отмена"
                    }
'@
    }
)
Replace-Exact $ruPath $ruPairs
$null = [IO.File]::ReadAllText($ruPath, $utf8NoBom) | ConvertFrom-Json
Write-Log ("ru.json fixed and valid.")

# ---------- CHANGELOG ----------
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