$ErrorActionPreference = "Stop"
$ver = "0.5.1a26"
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

Log "Starting patch $ver - Force collection replacement and fix initial load"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\src\MiniCodex.App\ViewModels\ModelCardViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Update LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# Make Cards settable
$content = $content.Replace(
    "public ObservableCollection<ModelCardViewModel> Cards { get; } = new();",
    "private ObservableCollection<ModelCardViewModel> _cards = new();`r`n    public ObservableCollection<ModelCardViewModel> Cards { get => _cards; private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); } }"
)

# Fix ForceShowAllAsync to use ReloadModelsCoreAsync
$oldForce = '(?s)public async Task ForceShowAllAsync\(\).*?\}\s*\}'
$newForce = @"
public async Task ForceShowAllAsync()
{
    _searchQuery = string.Empty;
    Raise(nameof(SearchQuery));
    _selectedTag = Tags.FirstOrDefault(t => string.IsNullOrEmpty(t.Id));
    Raise(nameof(SelectedTag));
    await ReloadModelsCoreAsync(CancellationToken.None);
}
"@
$content = $content -replace $oldForce, $newForce

# Fix ReloadModelsCoreAsync UI update
$oldUpdate = '(?s)await Dispatcher\.UIThread\.InvokeAsync\(\(\) => \{\s*Cards\.Clear\(\);.*?Raise\(nameof\(IsEmpty\)\);\s*\}\);'
$newUpdate = @"
await Dispatcher.UIThread.InvokeAsync(() => {
            Cards = new ObservableCollection<ModelCardViewModel>(newCards);
            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
            Raise(nameof(IsEmpty));
        });
"@
$content = $content -replace $oldUpdate, $newUpdate

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated."

# 2. Update ModelCardViewModel.cs (Add error logging)
$cardVm = "$root\src\MiniCodex.App\ViewModels\ModelCardViewModel.cs"
$cardContent = [IO.File]::ReadAllText($cardVm)
$cardContent = $cardContent.Replace(
    "catch { }`r`n                });`r`n            }",
    "catch (Exception ex) { MiniCodex.Core.Logging.Log.Exception(`"[ModelCard] Failed to load preview: `" + path, ex); }`r`n                });`r`n            }"
)
[IO.File]::WriteAllText($cardVm, $cardContent)
Log "ModelCardViewModel.cs updated with error logging."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Forced entire Cards collection replacement to guarantee UI redraw on initial load.
- Fix: Added exception logging for preview bitmap loading.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."