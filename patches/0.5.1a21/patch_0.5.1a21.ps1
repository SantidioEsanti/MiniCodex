$ErrorActionPreference = "Stop"
$ver = "0.5.1a21"
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

Log "Starting patch $ver - Safe replacement of Cards collection"

$files = @(
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

# 1. Restore LibraryViewModel.cs from 0.5.1a20 backup to clear the broken state
$backupPath = "$root\backups\0.5.1a20_20261113_153235\LibraryViewModel.cs"
if (Test-Path $backupPath) {
    Copy-Item -LiteralPath $backupPath -Destination "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs" -Force
    Log "Restored LibraryViewModel.cs from 0.5.1a20 backup."
} else {
    Log "ERROR: Backup not found at $backupPath"
    exit 1
}

$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# 2. Make Cards a settable property
$oldProp = 'public ObservableCollection<ModelCardViewModel> Cards { get; } = new();'
$newProp = @"
private ObservableCollection<ModelCardViewModel> _cards = new();
    public ObservableCollection<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@
if ($content -match [regex]::Escape($oldProp)) {
    $content = $content -replace [regex]::Escape($oldProp), $newProp
    Log "Cards property changed to settable."
} else {
    Log "WARNING: Cards property not found (it may already be settable)."
}

# 3. Fix ReloadModelsCoreAsync
$oldReload = @"
        Cards.Clear();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            Cards.Add(card);
"@
$newReload = @"
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
if ($content -match [regex]::Escape($oldReload)) {
    $content = $content -replace [regex]::Escape($oldReload), $newReload
    Log "ReloadModelsCoreAsync loop replaced."
} else {
    Log "ERROR: ReloadModelsCoreAsync loop not found."
}

# Add assignment after loop in ReloadModelsCoreAsync
$oldEndReload = @"
        UpdatePreviewsStatus();
        Raise(nameof(IsEmpty));
    }

    public async Task ScanAsync
"@
$newEndReload = @"
        Cards = new ObservableCollection<ModelCardViewModel>(newCards);
        UpdatePreviewsStatus();
    }

    public async Task ScanAsync
"@
if ($content -match [regex]::Escape($oldEndReload)) {
    $content = $content -replace [regex]::Escape($oldEndReload), $newEndReload
    Log "ReloadModelsCoreAsync end replaced."
} else {
    Log "ERROR: ReloadModelsCoreAsync end not found."
}

# 4. Fix ForceShowAllAsync
$oldForce = @"
            Cards.Clear();
            Log.Info("[ForceShowAll-v18] after Clear Cards.Count=" + Cards.Count);

            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                Cards.Add(card);
            }
            Log.Info("[ForceShowAll-v18] after Add Cards.Count=" + Cards.Count);
"@
$newForce = @"
            var newCards = new List<ModelCardViewModel>();
            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                newCards.Add(card);
            }
            Cards = new ObservableCollection<ModelCardViewModel>(newCards);
            Log.Info("[ForceShowAll-v18] after Add Cards.Count=" + Cards.Count);
"@
if ($content -match [regex]::Escape($oldForce)) {
    $content = $content -replace [regex]::Escape($oldForce), $newForce
    Log "ForceShowAllAsync loop replaced."
} else {
    Log "ERROR: ForceShowAllAsync loop not found."
}

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated safely."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Safely replaced Cards collection to force UI redraw. Restored from backup to avoid corrupted code.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."