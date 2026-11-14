# patch_0.5.3c.2.ps1 - Line-based fix for ru.json (CustomColor + ColorPickerDialog)
# Fallback after Replace-Exact anchors failed. Line-by-line insertion by trimmed match.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3c.2'
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

function Chars([int[]]$codes) { -join ([char[]]$codes) }

Write-Log ("Patch {0} started" -f $Version)

$enPath = Join-Path $ProjectRoot 'lang\en.json'
$ruPath = Join-Path $ProjectRoot 'lang\ru.json'
$chPath = Join-Path $ProjectRoot 'CHANGELOG.md'

foreach ($p in @($enPath, $ruPath, $chPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ("Required file missing: {0}" -f $p) }
}

# ---------- 0. Pre-flight ----------
$ruText = [IO.File]::ReadAllText($ruPath, $utf8NoBom)
if ($ruText -match '"CustomColor"')      { throw 'Pre-flight: ru.json already has CustomColor.' }
if ($ruText -match '"ColorPickerDialog"'){ throw 'Pre-flight: ru.json already has ColorPickerDialog.' }
Write-Log 'Pre-flight OK.'

# ---------- 1. Backup ----------
$filesToBackup = @('lang\ru.json', 'CHANGELOG.md')
foreach ($rel in $filesToBackup) {
    $src    = Join-Path $ProjectRoot $rel
    $dst    = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. Line-based fix for ru.json ----------
$ruCustomColor   = Chars @(0x421,0x432,0x43E,0x439,0x20,0x446,0x432,0x435,0x442,0x2E,0x2E,0x2E)
$ruColorTitle    = Chars @(0x421,0x432,0x43E,0x439,0x20,0x446,0x432,0x435,0x442)
$ruColorSave     = Chars @(0x421,0x43E,0x445,0x440,0x430,0x43D,0x438,0x442,0x44C)
$ruColorCancel   = Chars @(0x41E,0x442,0x43C,0x435,0x43D,0x430)

$lines = [IO.File]::ReadAllLines($ruPath, $utf8NoBom)
$out = New-Object System.Collections.Generic.List[string]

$inTagCtx = $false
$tagCtxDone = $false
$inDeleteTag = $false
$deleteTagDone = $false
$customColorInserted = $false
$colorPickerInserted = $false

for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    $trim = $line.Trim()
    $indent = ($line -replace '^(\s*).*$', '$1')

    # Enter TagContextMenu block
    if (-not $tagCtxDone -and -not $customColorInserted) {
        if ($trim -eq '"TagContextMenu":  {' -or $trim -eq '"TagContextMenu": {') {
            $inTagCtx = $true
            $out.Add($line)
            continue
        }
    }

    if ($inTagCtx) {
        if ($trim.StartsWith('"Delete"')) {
            if ($trim.EndsWith(',')) {
                $out.Add($line)
            } else {
                $out.Add($line.TrimEnd() + ',')
            }
            $out.Add($indent + '"CustomColor":  "' + $ruCustomColor + '"')
            $customColorInserted = $true
            $inTagCtx = $false
            $tagCtxDone = $true
            continue
        }
        $out.Add($line)
        continue
    }

    # Enter DeleteTagDialog block
    if (-not $deleteTagDone -and -not $colorPickerInserted) {
        if ($trim -eq '"DeleteTagDialog":  {' -or $trim -eq '"DeleteTagDialog": {') {
            $inDeleteTag = $true
            $out.Add($line)
            continue
        }
    }

    if ($inDeleteTag) {
        if ($trim -eq '}' -or $trim -eq '},') {
            if ($trim -eq '}') {
                $out.Add($indent + '},')
            } else {
                $out.Add($line)
            }
            $out.Add($indent + '"ColorPickerDialog":  {')
            $out.Add($indent + '    "Title":  "' + $ruColorTitle + '",')
            $out.Add($indent + '    "Placeholder":  "#RRGGBB",')
            $out.Add($indent + '    "Save":  "' + $ruColorSave + '",')
            $out.Add($indent + '    "Cancel":  "' + $ruColorCancel + '"')
            $out.Add($indent + '}')
            $colorPickerInserted = $true
            $inDeleteTag = $false
            $deleteTagDone = $true
            continue
        }
        $out.Add($line)
        continue
    }

    $out.Add($line)
}

if (-not $customColorInserted) { throw 'CustomColor not inserted: TagContextMenu block or Delete line not found in ru.json.' }
if (-not $colorPickerInserted) { throw 'ColorPickerDialog not inserted: DeleteTagDialog block or closing brace not found in ru.json.' }

[IO.File]::WriteAllLines($ruPath, $out, $utf8NoBom)
$null = [IO.File]::ReadAllText($ruPath, $utf8NoBom) | ConvertFrom-Json
Write-Log ('ru.json fixed and valid: CustomColor + ColorPickerDialog inserted.')

# ---------- 3. Verify en.json (should be OK after 0.5.3c.1) ----------
$enText = [IO.File]::ReadAllText($enPath, $utf8NoBom)
if ($enText -notmatch '"CustomColor"')       { throw 'en.json missing CustomColor - 0.5.3c.1 not applied?' }
if ($enText -notmatch '"ColorPickerDialog"') { throw 'en.json missing ColorPickerDialog - 0.5.3c not applied?' }
$null = $enText | ConvertFrom-Json
Write-Log 'en.json verified (already OK from 0.5.3c.1).'

# ---------- 4. CHANGELOG ----------
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
    Write-Log 'CHANGELOG.md updated (marker 0.5.3c applied).'
} else {
    Write-Log 'CHANGELOG.md: marker 0.5.3c already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next: build + test + run (expect 60/60, 0/0)'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)