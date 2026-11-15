# patch_0.5.6a.1b.ps1
# 0.5.6a.1b - Fix for 0.5.6a.1:
#   - Restores AssetService.cs from 0.5.6a.1 backup (was corrupted by unescaped quotes)
#   - Re-applies dedup block using single-quoted here-string
#   - Fixes ru.json using ASCII anchors + \uXXXX escapes (no Cyrillic in this script)
#   - Adds 0.5.6a.1 + 0.5.6a.1b entries to CHANGELOG.md
#   - Adds section 10.6 to HANDOFF.md (patch output format rule)
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6a\patch_0.5.6a.1b.ps1"

$ErrorActionPreference = 'Stop'
$version     = '0.5.6a.1b'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot 'patches\0.5.6a'
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir 'patch_' + $version + '.log'

# Backup from the failed 0.5.6a.1 run (pristine AssetService.cs)
$sourceBackup = Join-Path $projectRoot 'backups\0.5.6a.1_20261115_183015'

New-Item -ItemType Directory -Force -Path $patchDir  | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

Log "=== MiniCodex patch $version ==="

# --- backup current state ---
$filesToBackup = @(
    'src\MiniCodex.Core\Services\AssetService.cs',
    'lang\ru.json',
    'CHANGELOG.md',
    'docs\HANDOFF.md'
)
Log "Backup -> $backupDir"
foreach ($rel in $filesToBackup) {
    $src = Join-Path $projectRoot $rel
    if (Test-Path $src) {
        $dst    = Join-Path $backupDir $rel
        $dstDir = Split-Path $dst -Parent
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Log "  backup: $rel"
    } else {
        throw "Required file missing: $rel"
    }
}

# ================================================================
# STEP 1: Restore AssetService.cs from pristine backup
# ================================================================
Log "STEP 1: Restore AssetService.cs"
$assetSvcPath = Join-Path $projectRoot 'src\MiniCodex.Core\Services\AssetService.cs'
$srcAssetSvc  = Join-Path $sourceBackup 'src\MiniCodex.Core\Services\AssetService.cs'
if (-not (Test-Path $srcAssetSvc)) {
    throw "Pristine backup not found: $srcAssetSvc"
}
Copy-Item -LiteralPath $srcAssetSvc -Destination $assetSvcPath -Force
Log "  restored from $srcAssetSvc"

# ================================================================
# STEP 2: Re-apply dedup block (correct escaping via here-string)
# ================================================================
Log "STEP 2: Apply dedup block"

$svc = Get-Content -LiteralPath $assetSvcPath -Raw -Encoding UTF8

# 2a. using insertion
$oldUsing = 'using MiniCodex.Core.Repositories;'
$newUsing = "using MiniCodex.Core.Logging;`r`nusing MiniCodex.Core.Repositories;"
$cnt = [regex]::Matches($svc, [regex]::Escape($oldUsing)).Count
if ($cnt -ne 1) { throw "using anchor matched $cnt times (expected 1)" }
$svc = $svc.Replace($oldUsing, $newUsing)
Log "  using OK"

# 2b. dedup block replacement (here-string => literal quotes, no expansion)
$dedupOld = '        File.Copy(sourcePath, destPath, overwrite: false);'
$dedupNew = @'
        // Dedup: if an asset with the same original basename already exists for this model,
        // return it instead of importing a duplicate. No schema change required.
        var existing = await _assets.GetByModelAsync(modelId, ct);
        var origBase = Path.GetFileNameWithoutExtension(sourcePath);
        foreach (var a in existing)
        {
            var aName = Path.GetFileNameWithoutExtension(a.AbsolutePath);
            if (string.Equals(aName, origBase, StringComparison.OrdinalIgnoreCase)
                || aName.EndsWith("_" + origBase, StringComparison.OrdinalIgnoreCase))
            {
                Log.Info("[AssetService] dedup hit: " + sourcePath + " -> existing " + a.Id);
                return a;
            }
        }

        File.Copy(sourcePath, destPath, overwrite: false);
'@
# trim trailing newline that here-string does NOT add, but be safe
while ($dedupNew.EndsWith("`r`n")) { $dedupNew = $dedupNew.Substring(0, $dedupNew.Length - 2) }
while ($dedupNew.EndsWith("`n"))   { $dedupNew = $dedupNew.Substring(0, $dedupNew.Length - 1) }

$cnt = [regex]::Matches($svc, [regex]::Escape($dedupOld)).Count
if ($cnt -ne 1) { throw "File.Copy anchor matched $cnt times (expected 1)" }
$svc = $svc.Replace($dedupOld, $dedupNew)
Log "  dedup block OK"

Set-Content -LiteralPath $assetSvcPath -Value $svc -Encoding UTF8 -NoNewline
Log "  AssetService.cs written"

# ================================================================
# STEP 3: ru.json - ASCII-safe insertion via \uXXXX escapes
# ================================================================
Log "STEP 3: Patch ru.json"

$ruPath = Join-Path $projectRoot 'lang\ru.json'
$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

if ($ru.Contains('"Asset":  {') -or $ru.Contains('"Asset": {')) {
    Log "  ru.json already has Card.Asset block - skipping (idempotent)"
} else {
    # Validate anchors
    $cntAt = [regex]::Matches($ru, '"AssetType"').Count
    if ($cntAt -ne 1) { throw "ru.json: expected exactly 1 'AssetType', found $cntAt" }

    $idxAt = $ru.IndexOf('"AssetType"')
    $idxSt = $ru.IndexOf('"Status"', $idxAt)
    if ($idxSt -lt 0) { throw "ru.json: 'Status' after 'AssetType' not found" }
    $idxClose = $ru.LastIndexOf('},', $idxSt)
    if ($idxClose -le $idxAt) { throw "ru.json: closing '},' of AssetType not found" }
    Log "  anchors OK: AssetType@$idxAt Status@$idxSt close@$idxClose"

    # ASCII-only template with JSON \uXXXX escapes.
    # These are the same escapes JSON itself understands; we just decode them
    # to real Cyrillic before insertion (index-based, so no Cyrillic matching).
    $ruBlockTemplate = @'

                 "Asset":  {
                     "Context":  {
                         "Open":  "\u041E\u0442\u043A\u0440\u044B\u0442\u044C \u043D\u0430 \u0432\u0435\u0441\u044C \u044D\u043A\u0440\u0430\u043D",
                         "OpenExternal":  "\u041E\u0442\u043A\u0440\u044B\u0442\u044C \u0432 \u0441\u0438\u0441\u0442\u0435\u043C\u043D\u043E\u043C \u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0449\u0438\u043A\u0435",
                         "OpenInExplorer":  "\u041E\u0442\u043A\u0440\u044B\u0442\u044C \u0432 \u041F\u0440\u043E\u0432\u043E\u0434\u043D\u0438\u043A\u0435",
                         "CopyPath":  "\u041A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043F\u0443\u0442\u044C",
                         "Replace":  "\u0417\u0430\u043C\u0435\u043D\u0438\u0442\u044C...",
                         "Remove":  "\u0423\u0431\u0440\u0430\u0442\u044C"
                     },
                     "FullScreen":  {
                         "Close":  "\u0417\u0430\u043A\u0440\u044B\u0442\u044C",
                         "Counter":  "{0} / {1}"
                     },
                     "OtherHeader":  "\u041F\u0440\u043E\u0447\u0438\u0435",
                     "DropOther":  "\u041F\u0435\u0440\u0435\u0442\u0430\u0449\u0438\u0442\u0435 \u043F\u0440\u043E\u0447\u0438\u0435 \u0444\u0430\u0439\u043B\u044B \u0441\u044E\u0434\u0430",
                     "ConfirmRemove":  {
                         "Title":  "\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0430\u0441\u0441\u0435\u0442?",
                         "Message":  "\u0423\u0431\u0440\u0430\u0442\u044C {0}? \u0424\u0430\u0439\u043B \u043E\u0441\u0442\u0430\u043D\u0435\u0442\u0441\u044F \u043D\u0430 \u0434\u0438\u0441\u043A\u0435; \u0443\u0434\u0430\u043B\u044F\u0435\u0442\u0441\u044F \u0442\u043E\u043B\u044C\u043A\u043E \u043F\u0440\u0438\u0432\u044F\u0437\u043A\u0430.",
                         "Remove":  "\u0423\u0431\u0440\u0430\u0442\u044C",
                         "Cancel":  "\u041E\u0442\u043C\u0435\u043D\u0430"
                     },
                     "Error":  {
                         "OpenFailed":  "\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u043E\u0442\u043A\u0440\u044B\u0442\u044C \u0444\u0430\u0439\u043B",
                         "CopyFailed":  "\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u0441\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043F\u0443\u0442\u044C"
                     },
                     "Status":  {
                         "Replaced":  "\u0410\u0441\u0441\u0435\u0442 \u0437\u0430\u043C\u0435\u043D\u0451\u043D",
                         "Removed":  "\u0410\u0441\u0441\u0435\u0442 \u0443\u0431\u0440\u0430\u043D",
                         "Copied":  "\u041F\u0443\u0442\u044C \u0441\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u043D"
                     }
                 },
'@

    # Decode \uXXXX -> real chars
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    $ruBlock = [regex]::Replace($ruBlockTemplate, '\\u([0-9A-Fa-f]{4})', $evaluator)
    Log "  block decoded (length = $($ruBlock.Length))"

    # Insert after closing "}," of AssetType
    $ru = $ru.Substring(0, $idxClose + 2) + $ruBlock + $ru.Substring($idxClose + 2)

    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline
    Log "  ru.json written"
}

# ================================================================
# STEP 4: CHANGELOG.md - append both 0.5.6a.1 and 0.5.6a.1b entries
# ================================================================
Log "STEP 4: CHANGELOG.md"

$clPath = Join-Path $projectRoot 'CHANGELOG.md'
$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

$hasA1  = $cl.Contains('<!-- patch 0.5.6a.1 applied -->')
$hasA1b = $cl.Contains('<!-- patch 0.5.6a.1b applied -->')

if (-not $hasA1 -and -not $hasA1b) {
    $clEntry = @'


## 0.5.6a.1 - Associated files (backend + ViewModels)

- AssetRowViewModel: callbacks for open/open-external/open-in-explorer/copy-path/replace; IsImage/IsDocument/IsProfile/AssetIconGlyph/FileSizeText/PathText; FullBitmap + LoadFullBitmapAsync(cap) via Bitmap.DecodeToWidth; ClearFullBitmap.
- ModelCardPageViewModel: OtherAssets + HasOtherAssets (render/document/profile visible); fullscreen state + navigation; OpenExternalAsync/OpenInExplorerAsync/CopyPathAsync; remove-confirm dialog; ReplaceRequested + ReplaceAssetAsync.
- AssetService.ImportAsync: dedup by original basename (idempotent, no schema change).
- lang/en.json + lang/ru.json: Card.Asset.* block.
- XAML wiring deferred to 0.5.6a.2.
<!-- patch 0.5.6a.1 applied -->

## 0.5.6a.1b - Fix for 0.5.6a.1

- Fixed AssetService.cs: prior run corrupted dedup block (unescaped quotes in double-quoted PS string). Restored from 0.5.6a.1 backup, re-applied via single-quoted here-string.
- Fixed ru.json: prior anchor used Cyrillic; PS 5.1 read .ps1 as CP1251. Now uses ASCII IndexOf anchors + \uXXXX escapes decoded via MatchEvaluator.
- HANDOFF.md: added section 10.6 (patch output format rule).
<!-- patch 0.5.6a.1b applied -->
'@
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG.md appended"
} else {
    Log "  CHANGELOG.md already has markers - skipping (idempotent)"
}

# ================================================================
# STEP 5: HANDOFF.md - add section 10.6 (patch output format)
# ================================================================
Log "STEP 5: HANDOFF.md"

$handoffPath = Join-Path $projectRoot 'docs\HANDOFF.md'
$ho = Get-Content -LiteralPath $handoffPath -Raw -Encoding UTF8

if ($ho.Contains('### 10.6 Patch output format')) {
    Log "  section 10.6 already present - skipping (idempotent)"
} else {
    $hoAnchor = 'Script on error prints restore command.'
    $cnt = [regex]::Matches($ho, [regex]::Escape($hoAnchor)).Count
    if ($cnt -ne 1) { throw "HANDOFF.md: 10.5 anchor matched $cnt times (expected 1)" }

    $hoNew = @'
Script on error prints restore command.

### 10.6 Patch output format (after every patch text)

After each patch script, the assistant MUST print, in this exact order:

1. Create the patch file:
New-Item -ItemType File -Path "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1" -force

text
2. Run the patch:
powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1"

text
3. If a build/test run is needed:
dotnet run --project "D:\AI\MiniCodex\src\MiniCodex.App\MiniCodex.App.csproj"

text

Rationale: keeps copy-paste friction at zero and avoids path typos.

### 10.7 Escaping in replacement strings (learned 2026-11-15)

Never put `\"` inside a double-quoted PowerShell string - PS 5.1 treats backslash as a literal character, `"` closes the string, and the call is parsed into multiple arguments. Use `@'...'@` (single-quoted here-string) for any replacement text containing `"` or C# string literals. Symptom: `replace-exact OK: <garbage>` in the log with a `$tag` that was never passed.

### 10.8 Cyrillic in .ps1 (re-learned 2026-11-15)

Beyond BOM/ASCII-only: even if the .ps1 is byte-clean ASCII, do NOT embed Cyrillic literals as `Replace-Exact` anchors. `Get-Content -Encoding UTF8` on the target file returns correct UTF-8 strings, but PS 5.1 without BOM parses the .ps1 source as CP1251, so the anchor text inside the here-string is mojibake and never matches. Safe patterns:
- ASCII-only anchors (`"AssetType"`, `"Status"`, `},`), then IndexOf / LastIndexOf.
- Cyrillic payload via `\uXXXX` escapes + `[regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', $MatchEvaluator)` - the .ps1 stays ASCII, the inserted text is real Cyrillic.
'@
 $ho = $ho.Replace($hoAnchor, $hoNew)
 Set-Content -LiteralPath $handoffPath -Value $ho -Encoding UTF8 -NoNewline
 Log "  HANDOFF.md updated (sections 10.6, 10.7, 10.8)"
}

Log "=== Patch $version applied ==="
Log "Backup: $backupDir"
Write-Host ""
Write-Host "Done. Backup: $backupDir" -ForegroundColor Green
Write-Host "Next: run build, then 0.5.6a.2 (ModelCardView.axaml + code-behind)" -ForegroundColor Cyan