# patch_0.5.6c.1b.ps1
# 0.5.6c.1b - Fix for 0.5.6c.1 STEP 7 (ru.json DeleteTagDialog.Message)
#   The base64 I used for the old value decoded to ":  <russian>" - missing
#   the "Message" key name - so the anchor never matched (0 times).
#   All other 0.5.6c.1 steps applied cleanly (STEP 2..6).
#   This patch:
#     STEP 0  Verify 0.5.6c.1 STEP 2-6 applied (else abort with restore hint).
#     STEP 1  Backup.
#     STEP 2  ru.json: line-based replacement via ASCII anchors
#             (IndexOf "DeleteTagDialog", then "Message"); new line built
#             via [char] codes so .ps1 source stays pure ASCII.
#     STEP 3  CHANGELOG.md (0.5.6c + 0.5.6c.1 + 0.5.6c.1b markers).
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6c.1b\patch_0.5.6c.1b.ps1"

Write-Host "=== MiniCodex patch 0.5.6c.1b STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6c.1b'
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

Log ("=== MiniCodex patch " + $version + " ===")

$libVmPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$mcVmPath  = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
$libAxPath = Join-Path $projectRoot 'src\MiniCodex.App\Views\LibraryView.axaml'
$mcAxPath  = Join-Path $projectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
$enPath    = Join-Path $projectRoot 'lang\en.json'
$ruPath    = Join-Path $projectRoot 'lang\ru.json'
$clPath    = Join-Path $projectRoot 'CHANGELOG.md'

foreach ($p in @($libVmPath,$mcVmPath,$libAxPath,$mcAxPath,$enPath,$ruPath,$clPath)) {
    Assert (Test-Path $p) ("Missing: " + $p)
}

# ================================================================
# STEP 0: Verify 0.5.6c.1 prior steps
# ================================================================
Log "STEP 0: Verify 0.5.6c.1 STEP 2-6"

$libBack = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libBack.Contains('public async Task ChangeCollectionColorAsync')) "0.5.6c.1 STEP 2 missing. Restore backups/0.5.6c.1_*/src/MiniCodex.App/ViewModels/LibraryViewModel.cs"

$mcBack = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
Assert ($mcBack.Contains('public ObservableCollection<string> TagCandidates')) "0.5.6c.1 STEP 3 (TagCandidates) missing"
Assert ($mcBack.Contains('private async Task RefreshTagCandidatesAsync')) "0.5.6c.1 STEP 3 (RefreshTagCandidatesAsync) missing"

$axBack = Get-Content -LiteralPath $libAxPath -Raw -Encoding UTF8
$collectionsIdx = $axBack.IndexOf('ItemsSource="{Binding Collections}"')
Assert ($collectionsIdx -gt 0) "LibraryView: Collections ListBox not found"
$colWindowLen = [Math]::Min(5000, $axBack.Length - $collectionsIdx)
$colWindow = $axBack.Substring($collectionsIdx, $colWindowLen)
Assert ($colWindow.Contains('Fill="{Binding ColorBrush}"')) "0.5.6c.1 STEP 4 (collections color dot) missing"

$mcAxBack = Get-Content -LiteralPath $mcAxPath -Raw -Encoding UTF8
Assert ($mcAxBack.Contains('AutoCompleteBox Text="{Binding NewTagName}"')) "0.5.6c.1 STEP 5 (AutoCompleteBox) missing"

$enBack = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8
Assert ($enBack.Contains('Directly tagged: {1}, in subtree (children): {2}')) "0.5.6c.1 STEP 6 (en.json) missing"

Log "  0.5.6c.1 STEP 2-6 verified OK (not re-touched)"

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @('lang/ru.json','CHANGELOG.md')) {
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
# STEP 2: ru.json - line-based replacement of DeleteTagDialog.Message
# ================================================================
Log "STEP 2: ru.json DeleteTagDialog.Message"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

$idxDlg = $ru.IndexOf('"DeleteTagDialog"')
Assert ($idxDlg -gt 0) "ru.json: DeleteTagDialog not found"

$idxMsg = $ru.IndexOf('"Message"', $idxDlg)
Assert ($idxMsg -gt $idxDlg) "ru.json: Message not found after DeleteTagDialog"

$idxLineStart = $ru.LastIndexOf("`n", $idxMsg)
Assert ($idxLineStart -ge 0) "ru.json: Message line start not found"

$idxLineEnd = $ru.IndexOf("`n", $idxMsg)
Assert ($idxLineEnd -gt $idxMsg) "ru.json: Message line end not found"

$lineRaw = $ru.Substring($idxLineStart + 1, $idxLineEnd - $idxLineStart - 1)
Log ("  line preview: " + $lineRaw.Substring(0, [Math]::Min(60, $lineRaw.Length)) + "...")

if ($lineRaw.Contains('{2}')) {
    Log "  already 3-param - skipping (idempotent)"
} else {
    if ($lineRaw -notmatch '^(\s*)"Message"') { throw "ru.json: line is not a Message line - unexpected structure" }
    $leading = $matches[1]

    # Build the new value via char codes (source stays ASCII).
    $valueCodes = @(
        0x0423,0x0434,0x0430,0x043B,0x0438,0x0442,0x044C,0x0020,
        0x0442,0x0435,0x0433,0x0020,
        0x007B,0x0030,0x007D,0x003F,0x0020,
        0x041F,0x0440,0x044F,0x043C,0x043E,0x0020,
        0x0437,0x0430,0x0434,0x0435,0x0439,0x0441,0x0442,0x0432,0x043E,0x0432,0x0430,0x043D,0x043E,0x003A,0x0020,
        0x007B,0x0031,0x007D,0x002C,0x0020,
        0x0432,0x0020,
        0x043F,0x043E,0x0434,0x0434,0x0435,0x0440,0x0435,0x0432,0x0435,0x0020,
        0x043F,0x043E,0x0442,0x043E,0x043C,0x043A,0x043E,0x0432,0x003A,0x0020,
        0x007B,0x0032,0x007D,0x002E
    )
    $newValue = -join ($valueCodes | ForEach-Object { [char]$_ })
    $newLine = $leading + '"Message":  "' + $newValue + '",'

    $ru = $ru.Substring(0, $idxLineStart + 1) + $newLine + $ru.Substring($idxLineEnd)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch {
        throw ("ru.json invalid JSON after patch: " + $_)
    }
}

# ================================================================
# STEP 3: CHANGELOG.md - append all missing markers
# ================================================================
Log "STEP 3: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

$need6c   = -not $cl.Contains('<!-- patch 0.5.6c applied -->')
$need6c1  = -not $cl.Contains('<!-- patch 0.5.6c.1 applied -->')
$need6c1b = -not $cl.Contains('<!-- patch 0.5.6c.1b applied -->')

if (-not $need6c -and -not $need6c1 -and -not $need6c1b) {
    Log "  all markers present - skipping"
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

- STEP 9e detection was too loose (matched lambda reference from STEP 9d). ChangeCollectionColorAsync method was never inserted; post-write verify aborted at STEP 9 and STEP 10-15 never ran.
- Fix: strict detection, method inserted before ChangeTagColorAsync. STEP 10-15 re-executed.
<!-- patch 0.5.6c.1 applied -->
'@
    }
    if ($need6c1b) {
        $parts += @'

## 0.5.6c.1b - Fix for 0.5.6c.1 STEP 7

- 0.5.6c.1 STEP 7 failed: base64 anchor for ru.json DeleteTagDialog.Message decoded to ":  <russian>" (missing the "Message" key name) - 0 matches.
- 0.5.6c.1 STEP 2-6 applied cleanly. Not re-touched by this patch.
- 0.5.6c.1b: replaces the DeleteTagDialog.Message line via line-based ASCII anchors (IndexOf "DeleteTagDialog" then "Message"); new line built via [char] codes so .ps1 source stays pure ASCII.
<!-- patch 0.5.6c.1b applied -->
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