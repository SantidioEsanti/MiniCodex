$ErrorActionPreference = "Stop"
$ver = "0.5.1a7"
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

Log "Starting patch $ver - Fix ItemsRepeater refresh and TreeView equality"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\src\MiniCodex.App\ViewModels\TagNodeViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Add Equality to TagNodeViewModel (for TreeView selection stability)
$nodeVmPath = "$root\src\MiniCodex.App\ViewModels\TagNodeViewModel.cs"
$nodeContent = [IO.File]::ReadAllText($nodeVmPath)
if ($nodeContent -notmatch "public override bool Equals") {
    $eqCode = @"

    public override bool Equals(object? obj) => obj is TagNodeViewModel other && Id == other.Id;
    public override int GetHashCode() => Id.GetHashCode();
}
"@
    # Replace the last closing brace with equality methods + closing brace
    $nodeContent = $nodeContent -replace '\}\s*$', $eqCode
    [IO.File]::WriteAllText($nodeVmPath, $nodeContent)
    Log "Added Equals/GetHashCode to TagNodeViewModel."
}

# 2. Update LibraryViewModel.cs (Replace Cards collection instead of Clear/Add)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

if ($content -match "private ObservableCollection<ModelCardViewModel> _cards") {
    Log "LibraryViewModel.cs already patched. Skipping."
} else {
    Log "Patching LibraryViewModel.cs..."
    
    # Change Cards to a mutable property
    $content = $content -replace 'public ObservableCollection<ModelCardViewModel> Cards \{ get; \} = new\(\);', @"
    private ObservableCollection<ModelCardViewModel> _cards = new();
    public ObservableCollection<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@

    # Update ReloadModelsCoreAsync to build a new collection
    $oldReload = '(?s)Cards\.Clear\(\);.*?foreach \(var m in models\)'
    $newReload = @"
var newCards = new List<ModelCardViewModel>();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
"@
    $content = $content -replace $oldReload, $newReload
    
    # Change Cards.Add(card) to newCards.Add(card)
    $content = $content -replace 'Cards\.Add\(card\);', 'newCards.Add(card);'

    # After the foreach loop, assign the new collection
    $oldEndLoop = '(?s)\}\s*UpdatePreviewsStatus\(\);\s*Raise\(nameof\(IsEmpty\)\);\s*\}'
    $newEndLoop = @"
        }
        
        // Replace the collection entirely to force ItemsRepeater to re-layout
        Cards = new ObservableCollection<ModelCardViewModel>(newCards);
        UpdatePreviewsStatus();
    }
"@
    $content = $content -replace $oldEndLoop, $newEndLoop

    [IO.File]::WriteAllText($libVm, $content)
    Log "LibraryViewModel.cs updated (Cards collection replacement)."
}

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Fixed ItemsRepeater bug by replacing the Cards collection instead of Clear/Add.
- UI: Added Equals/GetHashCode to TagNodeViewModel to keep TreeView selection stable.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."