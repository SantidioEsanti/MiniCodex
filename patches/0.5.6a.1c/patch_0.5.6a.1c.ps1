# patch_0.5.6a.1c.ps1
# 0.5.6a.1c - Fix for 0.5.6a.1 / 0.5.6a.1b
#   - 0.5.6a.1 partially applied: AssetService.cs corrupted (unescaped quotes),
#     ru.json/CHANGELOG/HANDOFF not touched.
#   - 0.5.6a.1b produced zero log output (patch file was likely empty at run time).
#   - This patch:
#       STEP 0  Diagnose current state; verify 0.5.6a.1 partial-apply markers.
#       STEP 1  Backup current files.
#       STEP 2  Rebuild AssetService.cs from pristine 0.5.6a.1 backup + dedup via
#               single-quoted here-string (no \"); post-write verify.
#       STEP 3  Patch ru.json via ASCII anchors + \uXXXX escapes; verify via ConvertFrom-Json.
#       STEP 4  Append CHANGELOG.md entries for 0.5.6a.1 / 0.5.6a.1b / 0.5.6a.1c (idempotent).
#       STEP 5  Add HANDOFF.md sections 10.6 (patch output format, dir=version),
#               10.7 (\" escaping), 10.8 (Cyrillic in .ps1 without BOM).
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.6a.1c\patch_0.5.6a.1c.ps1"

Write-Host "=== MiniCodex patch 0.5.6a.1c STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.6a.1c'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot ('patches\' + $version)
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir ('patch_' + $version + '.log')

$sourceBackup = Join-Path $projectRoot 'backups\0.5.6a.1_20261115_183015'

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
Log ("Log: " + $logPath)

# Paths used below
$assetSvcPath = Join-Path $projectRoot 'src\MiniCodex.Core\Services\AssetService.cs'
$pristinePath = Join-Path $sourceBackup 'src\MiniCodex.Core\Services\AssetService.cs'
$ruPath       = Join-Path $projectRoot 'lang\ru.json'
$enPath       = Join-Path $projectRoot 'lang\en.json'
$clPath       = Join-Path $projectRoot 'CHANGELOG.md'
$hoPath       = Join-Path $projectRoot 'docs\HANDOFF.md'
$assetRowPath = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\AssetRowViewModel.cs'
$pageVmPath   = Join-Path $projectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'

# ================================================================
# STEP 0: Diagnose + verify partial 0.5.6a.1 state
# ================================================================
Log "STEP 0: Diagnose current state"

$prevLog = Join-Path $projectRoot 'patches\0.5.6a\patch_0.5.6a.1b.log'
if (Test-Path $prevLog) {
    Log ("  prev 0.5.6a.1b log: " + (Get-Item -LiteralPath $prevLog).Length + " bytes")
} else {
    Log "  prev 0.5.6a.1b log: NOT FOUND (0.5.6a.1b did not run)"
}

if (Test-Path $assetSvcPath) {
    $cur = Get-Content -LiteralPath $assetSvcPath -Raw -Encoding UTF8
    $hasBad = [bool]($cur -match '\\"')
    Log ("  current AssetService.cs: " + $cur.Length + " chars, has-dedup=" + $cur.Contains('[AssetService] dedup hit') + ", has-backslash-quote=" + $hasBad)
} else {
    Log "  current AssetService.cs: MISSING"
}

Assert (Test-Path $pristinePath) ("Pristine backup missing: " + $pristinePath)

# Verify 0.5.6a.1 ViewModel changes made it in.
Assert (Test-Path $assetRowPath) "AssetRowViewModel.cs missing"
$arRaw = Get-Content -LiteralPath $assetRowPath -Raw -Encoding UTF8
Assert ($arRaw.Contains('public bool IsImage')) "AssetRowViewModel.cs is missing 0.5.6a.1 changes (IsImage). Restore from backups\0.5.6a.1_20261115_183015\src\MiniCodex.App\ViewModels\AssetRowViewModel.cs"
Assert ($arRaw.Contains('LoadFullBitmapAsync')) "AssetRowViewModel.cs missing LoadFullBitmapAsync"

Assert (Test-Path $pageVmPath) "ModelCardPageViewModel.cs missing"
$pvRaw = Get-Content -LiteralPath $pageVmPath -Raw -Encoding UTF8
Assert ($pvRaw.Contains('OtherAssets')) "ModelCardPageViewModel.cs missing OtherAssets (0.5.6a.1 partial apply lost). Restore from backups\0.5.6a.1_20261115_183015\src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs"
Assert ($pvRaw.Contains('FullScreenBitmap')) "ModelCardPageViewModel.cs missing FullScreenBitmap"

$enRaw = Get-Content -LiteralPath $enPath -Raw -Encoding UTF8
Assert ($enRaw.Contains('"Asset":  {')) "en.json missing Card.Asset block (0.5.6a.1 partial apply lost)"

Log "  partial 0.5.6a.1 markers verified OK"

# ================================================================
# STEP 1: Backup current
# ================================================================
Log "STEP 1: Backup current"
$filesToBackup = @(
    'src\MiniCodex.Core\Services\AssetService.cs',
    'lang\ru.json',
    'CHANGELOG.md',
    'docs\HANDOFF.md'
)
foreach ($rel in $filesToBackup) {
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
# STEP 2: Rebuild AssetService.cs from pristine + dedup
# ================================================================
Log "STEP 2: Rebuild AssetService.cs"

$svc = Get-Content -LiteralPath $pristinePath -Raw -Encoding UTF8

Assert (-not $svc.Contains('[AssetService] dedup hit')) "pristine backup already patched"
Assert ($svc.Contains('File.Copy(sourcePath, destPath, overwrite: false);')) "pristine backup missing File.Copy anchor"
Assert (-not [bool]($svc -match '\\"')) "pristine backup already has backslash-quote"

# 2a. using insertion
$oldUsing = 'using MiniCodex.Core.Repositories;'
if (-not $svc.Contains('using MiniCodex.Core.Logging;')) {
    $cnt = [regex]::Matches($svc, [regex]::Escape($oldUsing)).Count
    Assert ($cnt -eq 1) ("using anchor matched $cnt times")
    $svc = $svc.Replace($oldUsing, "using MiniCodex.Core.Logging;`r`nusing MiniCodex.Core.Repositories;")
    Log "  using added"
} else {
    Log "  using already present"
}

# 2b. dedup block via single-quoted here-string (literal, no escape interpretation)
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
while ($dedupNew.EndsWith("`r`n")) { $dedupNew = $dedupNew.Substring(0, $dedupNew.Length - 2) }
while ($dedupNew.EndsWith("`n"))   { $dedupNew = $dedupNew.Substring(0, $dedupNew.Length - 1) }

$cnt = [regex]::Matches($svc, [regex]::Escape($dedupOld)).Count
Assert ($cnt -eq 1) ("File.Copy anchor matched $cnt times")
$svc = $svc.Replace($dedupOld, $dedupNew)
Log "  dedup block applied"

# 2c. in-memory sanity
Assert (-not [bool]($svc -match '\\"')) "in-memory result contains backslash-quote"
Assert ($svc.Contains('Log.Info("[AssetService] dedup hit: ')) "in-memory result missing dedup Log line"
Assert ($svc.Contains('using MiniCodex.Core.Logging;')) "in-memory result missing Logging using"

Set-Content -LiteralPath $assetSvcPath -Value $svc -Encoding UTF8 -NoNewline
Log ("  AssetService.cs written (" + $svc.Length + " chars)")

# 2d. post-write verification
$back = Get-Content -LiteralPath $assetSvcPath -Raw -Encoding UTF8
Assert ($back.Length -eq $svc.Length) "post-write length mismatch"
Assert (-not [bool]($back -match '\\"')) "post-write: backslash-quote present"
Assert ($back.Contains('Log.Info("[AssetService] dedup hit: ')) "post-write: dedup missing"
$fcCount = [regex]::Matches($back, [regex]::Escape('File.Copy(sourcePath, destPath, overwrite: false);')).Count
Assert ($fcCount -eq 1) ("post-write File.Copy count = $fcCount (expected 1)")
Log "  post-write verify OK"

# ================================================================
# STEP 3: ru.json (idempotent, ASCII anchors + \uXXXX)
# ================================================================
Log "STEP 3: Patch ru.json"

$ru = Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8

if ($ru.Contains('"Asset":  {') -or $ru.Contains('"Asset": {')) {
    Log "  ru.json already has Card.Asset block - skipping"
} else {
    $cntAt = [regex]::Matches($ru, '"AssetType"').Count
    Assert ($cntAt -eq 1) ("ru.json: expected 1 'AssetType', found $cntAt")

    $idxAt    = $ru.IndexOf('"AssetType"')
    $idxSt    = $ru.IndexOf('"Status"', $idxAt)
    Assert ($idxSt -gt $idxAt) "ru.json: 'Status' not found after 'AssetType'"
    $idxClose = $ru.LastIndexOf('},', $idxSt)
    Assert ($idxClose -gt $idxAt) "ru.json: closing '},' of AssetType not found"
    Log ("  anchors: AssetType@" + $idxAt + " Status@" + $idxSt + " close@" + $idxClose)

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

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    $ruBlock = [regex]::Replace($ruBlockTemplate, '\\u([0-9A-Fa-f]{4})', $evaluator)
    Log ("  block decoded (" + $ruBlock.Length + " chars)")

    $ru = $ru.Substring(0, $idxClose + 2) + $ruBlock + $ru.Substring($idxClose + 2)
    Set-Content -LiteralPath $ruPath -Value $ru -Encoding UTF8 -NoNewline

    try {
        Get-Content -LiteralPath $ruPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Log "  ru.json written and parses OK"
    } catch {
        throw ("ru.json is now invalid JSON: " + $_)
    }
}

# ================================================================
# STEP 4: CHANGELOG.md (idempotent, one combined append)
# ================================================================
Log "STEP 4: CHANGELOG.md"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8

$hasA1  = $cl.Contains('<!-- patch 0.5.6a.1 applied -->')
$hasA1b = $cl.Contains('<!-- patch 0.5.6a.1b applied -->')
$hasA1c = $cl.Contains('<!-- patch 0.5.6a.1c applied -->')

if ($hasA1 -and $hasA1b -and $hasA1c) {
    Log "  CHANGELOG.md already has all three markers - skipping"
} else {
    $parts = @()

    if (-not $hasA1) {
        $parts += @'


## 0.5.6a.1 - Associated files (backend + ViewModels)

- AssetRowViewModel: callbacks for open/open-external/open-in-explorer/copy-path/replace; IsImage/IsDocument/IsProfile/AssetIconGlyph/FileSizeText/PathText; FullBitmap + LoadFullBitmapAsync(cap); ClearFullBitmap.
- ModelCardPageViewModel: OtherAssets + HasOtherAssets; fullscreen state + navigation; OpenExternalAsync/OpenInExplorerAsync/CopyPathAsync; remove-confirm dialog; ReplaceRequested + ReplaceAssetAsync.
- AssetService.ImportAsync: dedup by original basename (idempotent, no schema change).
- lang/en.json: Card.Asset.* block.
- XAML wiring deferred to 0.5.6a.2.
<!-- patch 0.5.6a.1 applied -->
'@
    }

    if (-not $hasA1b) {
        $parts += @'

## 0.5.6a.1b - Fix attempt for 0.5.6a.1 (did not apply)

- Intended to fix AssetService.cs and ru.json; not applied (patch file was empty at run time, zero log output).
<!-- patch 0.5.6a.1b applied -->
'@
    }

    if (-not $hasA1c) {
        $parts += @'

## 0.5.6a.1c - Fix for 0.5.6a.1 / 0.5.6a.1b

- AssetService.cs rebuilt from pristine 0.5.6a.1 backup; dedup block applied via single-quoted here-string (no \"). Post-write verification passed (no backslash-quote, dedup Log line present, File.Copy count == 1).
- lang/ru.json: Card.Asset block inserted using ASCII anchors (AssetType / Status / },) + \uXXXX escapes decoded via MatchEvaluator. Verified with ConvertFrom-Json.
- docs/HANDOFF.md: added sections 10.6 (patch output format; patch dir MUST equal version string), 10.7 (\" escaping lesson), 10.8 (Cyrillic in .ps1 without BOM).
<!-- patch 0.5.6a.1c applied -->
'@
    }

    Add-Content -LiteralPath $clPath -Value ($parts -join "`r`n") -Encoding UTF8
    Log "  CHANGELOG.md appended (missing markers only)"
}

# ================================================================
# STEP 5: HANDOFF.md - add 10.6 / 10.7 / 10.8
# ================================================================
Log "STEP 5: HANDOFF.md"

$ho = Get-Content -LiteralPath $hoPath -Raw -Encoding UTF8

if ($ho.Contains('### 10.6 Patch output format')) {
    Log "  section 10.6 already present - skipping"
} else {
    $hoAnchor = 'Script on error prints restore command.'
    $cnt = [regex]::Matches($ho, [regex]::Escape($hoAnchor)).Count
    Assert ($cnt -eq 1) ("HANDOFF.md: anchor matched $cnt times (expected 1)")

    $hoNew = @'
Script on error prints restore command.

### 10.6 Patch output format (after every patch text)

After each patch script, the assistant MUST print, in this exact order:

1. Create patch dir + file. The patch directory MUST match the full version string exactly - never the parent version.
   Correct:
New-Item -ItemType Directory -Force -Path "D:\AI\MiniCodex\patches{version}"
New-Item -ItemType File -Path "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1" -force

text
Wrong (do not do this): putting patch_0.5.6a.1c.ps1 into patches\0.5.6a\ instead of patches\0.5.6a.1c\.

2. Run the patch:
powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1"

text

3. If a build/test run is needed:
dotnet run --project "D:\AI\MiniCodex\src\MiniCodex.App\MiniCodex.App.csproj"

text

The entire .ps1 content MUST be emitted inside a single fenced text code block (no markdown inside), so the user can copy-paste it verbatim.

Rationale: keeps friction at zero; avoids path typos; one block = one paste.

### 10.7 Escaping in replacement strings (learned 2026-11-15)

Never put `\"` inside a double-quoted PowerShell string. PS 5.1 treats backslash as a literal character; the `"` closes the string; the call is parsed into multiple positional args; Replace-Exact receives garbage in $old/$new/$tag. Symptom: log line `replace-exact OK: <garbage>` where $tag was never passed.

Rule: any replacement payload containing `"` (C# string literals, JSON, etc.) MUST use a single-quoted here-string `@'...'@` and literal `.Replace($old, $new)`.

### 10.8 Cyrillic in .ps1 (re-learned 2026-11-15)

Beyond BOM/ASCII-only: do NOT embed Cyrillic literals as Replace-Exact anchors. Get-Content -Encoding UTF8 on the target returns correct UTF-8 strings, but PS 5.1 without BOM parses the .ps1 source as CP1251, so the anchor inside the here-string is mojibake and never matches (matched 0 times).

Safe pattern:
- ASCII-only anchors (`"AssetType"`, `"Status"`, `},`) located via IndexOf / LastIndexOf.
- Cyrillic payload via \uXXXX escapes + [regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', $MatchEvaluator) - .ps1 stays ASCII, inserted text is real Cyrillic.
- After writing .json, ALWAYS verify with Get-Content -Raw | ConvertFrom-Json.

### 10.9 Silent-failure symptom (learned 2026-11-15)

If running a patch via powershell -File produces ZERO output (not even the "=== MiniCodex patch X ===" banner), the .ps1 file was empty at run time. Always verify file size > 2 KB before running:
(Get-Item "D:\AI\MiniCodex\patches{version}\patch_{version}.ps1").Length

text
If size is 0, re-paste the script content from chat into the file, then run.
'@
    $ho = $ho.Replace($hoAnchor, $hoNew)
    Set-Content -LiteralPath $hoPath -Value $ho -Encoding UTF8 -NoNewline
    Log "  HANDOFF.md updated (10.6 / 10.7 / 10.8 / 10.9)"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: dotnet build; then 0.5.6a.2 (ModelCardView.axaml + code-behind)" -ForegroundColor Cyan