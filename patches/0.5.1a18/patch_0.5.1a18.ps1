$ErrorActionPreference = "Stop"
$ver = "0.5.1a18"
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

Log "Starting patch $ver - Force direct reload with verbose logging"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\src\MiniCodex.App\ViewModels\MainWindowViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Add ForceShowAllAsync to LibraryViewModel
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

$forceMethod = @"
    public async Task ForceShowAllAsync()
    {
        try
        {
            Log.Info("[ForceShowAll-v18] start");
            _searchQuery = string.Empty;
            Raise(nameof(SearchQuery));
            _selectedTag = Tags.FirstOrDefault(t => string.IsNullOrEmpty(t.Id));
            Raise(nameof(SelectedTag));
            Log.Info("[ForceShowAll-v18] SelectedTag.Id='" + (_selectedTag?.Id ?? "null") + "' Tags.Count=" + Tags.Count);

            if (_models == null || _files == null || _previews == null)
            {
                Log.Warn("[ForceShowAll-v18] services null");
                return;
            }

            var models = await _models.SearchAsync(null, null, CancellationToken.None);
            Log.Info("[ForceShowAll-v18] models.Count=" + models.Count);

            Cards.Clear();
            Log.Info("[ForceShowAll-v18] after Clear Cards.Count=" + Cards.Count);

            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                Cards.Add(card);
            }
            Log.Info("[ForceShowAll-v18] after Add Cards.Count=" + Cards.Count);

            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
            Raise(nameof(IsEmpty));
        }
        catch (Exception ex)
        {
            Log.Exception("[ForceShowAll-v18] failed", ex);
        }
    }
}
"@

if ($content -notmatch "ForceShowAllAsync") {
    $lastBrace = $content.LastIndexOf("}")
    if ($lastBrace -ge 0) {
        $content = $content.Substring(0, $lastBrace) + $forceMethod
        [IO.File]::WriteAllText($libVm, $content)
        Log "Added ForceShowAllAsync to LibraryViewModel."
    }
}

# 2. Update MainWindowViewModel to use ForceShowAllAsync
$mainVm = "$root\src\MiniCodex.App\ViewModels\MainWindowViewModel.cs"
$mainContent = [IO.File]::ReadAllText($mainVm)

# Update ShowLibraryCommand
$oldShowLibPattern = '(?s)ShowLibraryCommand = new RelayCommand\(\(\) =>\s*\{[^}]*CurrentPage = Library;\s*\}\);'
$newShowLib = @"
ShowLibraryCommand = new RelayCommand(() =>
        {
            Log.Info("[MainVM-v18] ShowLibraryCommand fired");
            _ = Library.ForceShowAllAsync();
            CurrentPage = Library;
        });
"@
$mainContent = $mainContent -replace $oldShowLibPattern, $newShowLib

# Update onBack
$oldOnBackPattern = '(?s)onBack:\s*\(\)\s*=>\s*\{.*?CurrentPage = Library;.*?\}\)'
$newOnBack = @"
onBack: () =>
            {
                Log.Info("[MainVM-v18] onBack fired");
                _ = Library.ForceShowAllAsync();
                CurrentPage = Library;
            })
"@
$mainContent = $mainContent -replace $oldOnBackPattern, $newOnBack

[IO.File]::WriteAllText($mainVm, $mainContent)
Log "Updated MainWindowViewModel navigation methods."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Debug: Added ForceShowAllAsync with verbose logging to diagnose filter sticking.
- UI: onBack and ShowLibraryCommand now call ForceShowAllAsync directly.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."