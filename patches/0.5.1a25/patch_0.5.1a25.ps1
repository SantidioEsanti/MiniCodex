$ErrorActionPreference = "Stop"
$ver = "0.5.1a25"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Safe restore and exact string replacements"

$files = @(
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs",
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Restore from 0.5.1a24 backup to clear the broken syntax
$latestBackup = (Get-ChildItem "$root\backups" -Filter "0.5.1a24_*" | Sort-Object Name -Descending | Select-Object -First 1).FullName
if ($latestBackup) {
    Copy-Item -LiteralPath "$latestBackup\LibraryView.axaml" -Destination "$root\src\MiniCodex.App\Views\LibraryView.axaml" -Force
    Copy-Item -LiteralPath "$latestBackup\LibraryView.axaml.cs" -Destination "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs" -Force
    Copy-Item -LiteralPath "$latestBackup\LibraryViewModel.cs" -Destination "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs" -Force
    Log "Restored files from $latestBackup"
} else {
    Log "ERROR: Backup 0.5.1a24 not found!"
    exit 1
}

# 2. Update LibraryViewModel.cs (Exact replacements)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# Add Semaphore
$content = $content.Replace(
    "private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);",
    "private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);`r`n    private readonly SemaphoreSlim _loadSemaphore = new SemaphoreSlim(1, 1);"
)

# Wrap ReloadModelsCoreAsync in try/finally
$content = $content.Replace(
    "        if (_models == null || _files == null || _previews == null) return;`r`n        if (_disposed) return;`r`n        var models = await _models.SearchAsync(",
    "        if (_models == null || _files == null || _previews == null) return;`r`n        await _loadSemaphore.WaitAsync(ct);`r`n        try`r`n        {`r`n        var models = await _models.SearchAsync("
)

$content = $content.Replace(
    "        await Dispatcher.UIThread.InvokeAsync(() => {`r`n            Cards.Clear();`r`n            foreach (var c in newCards) Cards.Add(c);`r`n            PreviewsDone = 0;`r`n            PreviewsTotal = models.Count;`r`n            UpdatePreviewsStatus();`r`n            Raise(nameof(IsEmpty));`r`n        });`r`n    }",
    "        await Dispatcher.UIThread.InvokeAsync(() => {`r`n            Cards.Clear();`r`n            foreach (var c in newCards) Cards.Add(c);`r`n            PreviewsDone = 0;`r`n            PreviewsTotal = models.Count;`r`n            UpdatePreviewsStatus();`r`n            Raise(nameof(IsEmpty));`r`n        });`r`n        }`r`n        finally`r`n        {`r`n            _loadSemaphore.Release();`r`n        }`r`n    }"
)

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated safely."

# 3. Update LibraryView.axaml (Exact replacements)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)

$axamlContent = $axamlContent.Replace(
    '<ScrollViewer Grid.Row="1" Background="Transparent">',
    '<ScrollViewer Grid.Row="1" Background="Transparent" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">'
)
$axamlContent = $axamlContent.Replace(
    'SelectedItem="{Binding SelectedTag, Mode=TwoWay}" SelectionChanged="OnTagSelectionChanged"',
    'SelectedItem="{Binding SelectedTag, Mode=TwoWay}"'
)
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated safely."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Restored broken files from 0.5.1a24 and reapplied ScrollViewer and Semaphore fixes using exact string replacements.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."