# patch_0.5.6b.1b.ps1
# 0.5.6b.1b - Fix for 0.5.6b.1 STEP 10/11
#   0.5.6b.1 STEP 2-9 applied cleanly (ModelCardViewModel.IsSelected,
#   LibraryViewModel multi-select block). STEP 10 failed because en.json
#   uses \r\n, but the anchor here-string had been normalized to \n.
#   Same latent bug in STEP 11 (ru.json) - fixed proactively.
#   This patch:
#     STEP 0  Verify C# changes from 0.5.6b.1 are present (do not re-touch).
#     STEP 1  Backup.
#     STEP 2  en.json: insert GroupTagDialog/GroupRemoveDialog/Group via $nl-aware anchor.
#     STEP 3  ru.json: same, with \uXXXX escapes.
#     STEP 4  CHANGELOG entry for 0.5.6b.1b.
#   Does NOT touch ModelCardViewModel.cs or LibraryViewModel.cs.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6b.1b\patch_0.5.6b.1b.ps1"

Write-Host "=== MiniCodex patch 0.5.6b.1b STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6b.1b'
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

$mcVmPath  = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs'
$libVmPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
$enPath    = Join-Path $projectRoot 'lang\en.json'
$ruPath    = Join-Path $projectRoot 'lang\ru.json'
$clPath    = Join-Path $projectRoot 'CHANGELOG.md'

# ================================================================
# STEP 0: Verify 0.5.6b.1 C#-part applied
# ================================================================
Log "STEP 0: Verify 0.5.6b.1 C#-part"

Assert (Test-Path $mcVmPath) ("Missing: " + $mcVmPath)
Assert (Test-Path $libVmPath) ("Missing: " + $libVmPath)

$mcRaw = Get-Content -LiteralPath $mcVmPath -Raw -Encoding UTF8
Assert ($mcRaw.Contains('public bool IsSelected')) "ModelCardViewModel.IsSelected missing - 0.5.6b.1 partial apply lost. Restore from backups\0.5.6b.1_20261115_200612\src\MiniCodex.App\ViewModels\ModelCardViewModel.cs"

$libRaw = Get-Content -LiteralPath $libVmPath -Raw -Encoding UTF8
Assert ($libRaw.Contains('public ObservableCollection<ModelCardViewModel> SelectedCards')) "LibraryViewModel.SelectedCards missing"
Assert ($libRaw.Contains('public void OnCardClicked(ModelCardViewModel card, bool isCtrl, bool isShift)')) "OnCardClicked missing"
Assert ($libRaw.Contains('public void ClearSelection()')) "ClearSelection missing"
Assert ($libRaw.Contains('public void SelectAllVisible()')) "SelectAllVisible missing"
Log "  0.5.6b.1 C#-part verified OK (not re-touched by this patch)"

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
foreach ($rel in @(
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
# STEP 2: en.json (nl-aware)
# ================================================================
Log "STEP 2: en.json"

$en = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8

if ($en.Contains('"GroupTagDialog"')) {
    Log "  en.json already has GroupTagDialog - skipping (idempotent)"
} else {
    $nl = if ($en.Contains("`r`n")) { "`r`n" } else { "`n" }
    Log ("  detected newline: " + $(if ($nl -eq "`r`n") { "CRLF" } else { "LF" }))

    # ASCII anchor built with detected $nl. Matches the closing of ColorPickerDialog
    # followed by the Library-block closer and the Card-block opener.
    $enOld = "                    }" + $nl `
           + "                }," + $nl `
           + '    "Card":  {'

    $cnt = [regex]::Matches($en, [regex]::Escape($enOld)).Count
    Assert ($cnt -eq 1) ("en.json: ColorPickerDialog anchor matched $cnt times")

    # Block (own $nl already applied at write time via -join). Use array join.
    $blockLines = @(
        '                    },'
        '                    "GroupTagDialog":  {'
        '                        "Title":  "Add tag to selection",'
        '                        "Placeholder":  "Tag name",'
        '                        "Add":  "Add",'
        '                        "Cancel":  "Cancel"'
        '                    },'
        '                    "GroupRemoveDialog":  {'
        '                        "Title":  "Remove models?",'
        '                        "Message":  "Remove {0} models from library? This cannot be undone.",'
        '                        "Remove":  "Remove",'
        '                        "Cancel":  "Cancel"'
        '                    },'
        '                    "Group":  {'
        '                        "AddTag":  "Add tag to selected",'
        '                        "Remove":  "Remove selected",'
        '                        "CopyPaths":  "Copy paths of selected",'
        '                        "FindDuplicates":  "Find duplicates in selection",'
        '                        "SelectionCount":  "Selected: {0}",'
        '                        "CopiedFormat":  "Copied {0} paths",'
        '                        "TagAppliedFormat":  "Applied tag to {0} models",'
        '                        "NoDuplicates":  "No duplicates found in selection"'
        '                    }'
        '                },'
        '    "Card":  {'
    )
    $enNew = ($blockLines -join $nl)

    $en = $en.Replace($enOld, $enNew)
    Set-Content -LiteralPath $enPath -Value $en -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $enPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  en.json written and parses OK"
    } catch {
        throw ("en.json invalid JSON after patch: " + $_)
    }
}

# ================================================================
# STEP 3: ru.json (nl-aware, \uXXXX escapes)
# ================================================================
Log "STEP 3: ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

if ($ru.Contains('"GroupTagDialog"')) {
    Log "  ru.json already has GroupTagDialog - skipping (idempotent)"
} else {
    $nl = if ($ru.Contains("`r`n")) { "`r`n" } else { "`n" }
    Log ("  detected newline: " + $(if ($nl -eq "`r`n") { "CRLF" } else { "LF" }))

    $ruOld = "                    }" + $nl `
           + "                }," + $nl `
           + '    "Card":  {'

    $cnt = [regex]::Matches($ru, [regex]::Escape($ruOld)).Count
    Assert ($cnt -eq 1) ("ru.json: ColorPickerDialog anchor matched $cnt times")

    # Cyrillic values as \uXXXX escapes (ASCII-only in source).
    $blockLines = @(
        '                    },'
        '                    "GroupTagDialog":  {'
        '                        "Title":  "\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C \u0442\u0435\u0433 \u043A \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u043D\u044B\u043C",'
        '                        "Placeholder":  "\u0418\u043C\u044F \u0442\u0435\u0433\u0430",'
        '                        "Add":  "\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C",'
        '                        "Cancel":  "\u041E\u0442\u043C\u0435\u043D\u0430"'
        '                    },'
        '                    "GroupRemoveDialog":  {'
        '                        "Title":  "\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u043C\u043E\u0434\u0435\u043B\u0438?",'
        '                        "Message":  "\u0423\u0434\u0430\u043B\u0438\u0442\u044C {0} \u043C\u043E\u0434\u0435\u043B\u0435\u0439 \u0438\u0437 \u0431\u0438\u0431\u043B\u0438\u043E\u0442\u0435\u043A\u0438? \u042D\u0442\u043E \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0435 \u043D\u0435\u043B\u044C\u0437\u044F \u043E\u0442\u043C\u0435\u043D\u0438\u0442\u044C.",'
        '                        "Remove":  "\u0423\u0434\u0430\u043B\u0438\u0442\u044C",'
        '                        "Cancel":  "\u041E\u0442\u043C\u0435\u043D\u0430"'
        '                    },'
        '                    "Group":  {'
        '                        "AddTag":  "\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C \u0442\u0435\u0433 \u043A \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u043D\u044B\u043C",'
        '                        "Remove":  "\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u043D\u044B\u0435",'
        '                        "CopyPaths":  "\u041A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043F\u0443\u0442\u0438 \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u043D\u044B\u0445",'
        '                        "FindDuplicates":  "\u041D\u0430\u0439\u0442\u0438 \u0434\u0443\u0431\u043B\u0438\u043A\u0430\u0442\u044B \u0432 \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u043D\u044B\u0445",'
        '                        "SelectionCount":  "\u0412\u044B\u0434\u0435\u043B\u0435\u043D\u043E: {0}",'
        '                        "CopiedFormat":  "\u0421\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u043D\u043E \u043F\u0443\u0442\u0435\u0439: {0}",'
        '                        "TagAppliedFormat":  "\u0422\u0435\u0433 \u043F\u0440\u0438\u043C\u0435\u043D\u0451\u043D \u043A {0} \u043C\u043E\u0434\u0435\u043B\u044F\u043C",'
        '                        "NoDuplicates":  "\u0412 \u0432\u044B\u0434\u0435\u043B\u0435\u043D\u0438\u0438 \u043D\u0435\u0442 \u0434\u0443\u0431\u043B\u0438\u043A\u0430\u0442\u043E\u0432"'
        '                    }'
        '                },'
        '    "Card":  {'
    )

    $blockJoined = ($blockLines -join $nl)

    # Decode \uXXXX -> real chars (MatchEvaluator). Our anchors are ASCII-only,
    # so even if PS read the .ps1 as CP1251, only the decoded result becomes Cyrillic.
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    $ruNew = [regex]::Replace($blockJoined, '\\u([0-9A-Fa-f]{4})', $evaluator)

    $ru = $ru.Replace($ruOld, $ruNew)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch {
        throw ("ru.json invalid JSON after patch: " + $_)
    }
}

# ================================================================
# STEP 4: CHANGELOG.md
# ================================================================
Log "STEP 4: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

$needA1  = -not $cl.Contains('<!-- patch 0.5.6b.1 applied -->')
$needA1b = -not $cl.Contains('<!-- patch 0.5.6b.1b applied -->')

if (-not $needA1 -and -not $needA1b) {
    Log "  CHANGELOG.md already has 0.5.6b.1 and 0.5.6b.1b markers - skipping"
} else {
    $parts = @()
    if ($needA1) {
        $parts += @'

## 0.5.6b.1 - Multi-select (backend + ViewModel)

- ModelCardViewModel: IsSelected bool property with Raise.
- LibraryViewModel: SelectedCards (ObservableCollection), GroupTagCandidates; SelectedCount/HasSelection/IsMultiSelection; OnCardClicked(card, ctrl, shift) public entry point; ClearSelection/SelectAllVisible; RefreshSelectionCollections.
- LibraryViewModel group commands: GroupAddTagCommand (free-text tag name + candidates), GroupRemoveCommand (confirm), GroupCopyPathsCommand (clipboard, one per line), GroupFindDuplicatesCommand (in-place filter by file_hash intersection within selection).
- LibraryViewModel dialog state: ShowGroupTagDialog / GroupTagName / ShowGroupRemoveConfirm / GroupRemoveMessage + 4 confirm/cancel commands.
- Selection reset on ReloadModelsCoreAsync.
- Deferred to 0.5.6c: GroupAddToCollection (requires manual-collection type).
<!-- patch 0.5.6b.1 applied -->
'@
    }
    if ($needA1b) {
        $parts += @'

## 0.5.6b.1b - Fix for 0.5.6b.1 STEP 10/11

- 0.5.6b.1 STEP 2-9 (C# ViewModel changes) applied cleanly. STEP 10 (lang/en.json) failed: anchor was normalized to LF while the file uses CRLF, so 0 matches.
- 0.5.6b.1b applies only the lang + CHANGELOG parts using a newline-aware anchor ($nl detected from the file).
- ModelCardViewModel.cs and LibraryViewModel.cs NOT touched by 0.5.6b.1b (verified in STEP 0).
<!-- patch 0.5.6b.1b applied -->
'@
    }
    Add-Content -LiteralPath $clPath -Value ($parts -join "`r`n") -Encoding UTF8
    Log "  CHANGELOG.md appended (missing markers only)"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then 0.5.6b.2 (XAML rubber band + Ctrl/Shift wiring)" -ForegroundColor Cyan