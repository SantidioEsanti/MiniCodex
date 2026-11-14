$ErrorActionPreference = "Stop"
$ver = "0.5.1a23"
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

Log "Starting patch $ver - Fix WrapPanel layout and UI thread updates"

$files = @(
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
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

# 1. Fix LibraryView.axaml (Remove ClipToBounds from ItemsControl and WrapPanel)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)
$axamlContent = $axamlContent -replace 'ClipToBounds="False"', ''
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated (removed ClipToBounds)."

# 2. Fix LibraryViewModel.cs (Update Cards in UI thread, use Clear/Add)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# Add Avalonia.Threading using
if ($content -notmatch "using Avalonia.Threading;") {
    $content = $content -replace 'using MiniCodex.Core.Logging;', "using MiniCodex.Core.Logging;`nusing Avalonia.Threading;"
}

# Fix ForceShowAllAsync
$oldForce = @"
            var newCards = new List<ModelCardViewModel>();
            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                newCards.Add(card);
            }
            Cards = new ObservableCollection<ModelCardViewModel>(newCards);
            Log.Info("[ForceShowAll-v18] after Add Cards.Count=" + Cards.Count);

            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
"@
$newForce = @"
            var newCards = new List<ModelCardViewModel>();
            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                newCards.Add(card);
            }
            
            await Dispatcher.UIThread.InvokeAsync(() => {
                Cards.Clear();
                foreach (var c in newCards) Cards.Add(c);
                PreviewsDone = 0;
                PreviewsTotal = models.Count;
                UpdatePreviewsStatus();
                Raise(nameof(IsEmpty));
            });
            Log.Info("[ForceShowAll-v18] after Add Cards.Count=" + Cards.Count);
"@
$content = $content -replace [regex]::Escape($oldForce), $newForce

# Fix ReloadModelsCoreAsync
$oldReload = @"
        var newCards = new List<ModelCardViewModel>();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            newCards.Add(card);
"@
$newReload = @"
        var newCards = new List<ModelCardViewModel>();
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            newCards.Add(card);
"@
$content = $content -replace [regex]::Escape($oldReload), $newReload

$oldEndReload = @"
        Cards = new ObservableCollection<ModelCardViewModel>(newCards);
        UpdatePreviewsStatus();
    }

    public async Task ScanAsync
"@
$newEndReload = @"
        await Dispatcher.UIThread.InvokeAsync(() => {
            Cards.Clear();
            foreach (var c in newCards) Cards.Add(c);
            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
            Raise(nameof(IsEmpty));
        });
    }

    public async Task ScanAsync
"@
$content = $content -replace [regex]::Escape($oldEndReload), $newEndReload

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated (UI thread updates)."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Removed ClipToBounds from ItemsControl/WrapPanel to restore layout inside ScrollViewer.
- Fix: Ensured Cards collection is updated on the UI thread to prevent rendering glitches.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."