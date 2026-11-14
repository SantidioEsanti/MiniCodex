$ErrorActionPreference = "Stop"
$ver = "0.5.1a14"
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

Log "Starting patch $ver - Revert virtualization, restore stable ItemsControl"

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

# 1. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)

if ($axamlContent -match "ItemsRepeater") {
    Log "Reverting ItemsRepeater to ItemsControl + WrapPanel..."
    
    $oldRepeater = '(?s)<ItemsRepeater ItemsSource="\{Binding Cards\}".*?</ItemsRepeater>'
    $newItemsControl = @"
<ItemsControl ItemsSource="{Binding Cards}" Margin="4">
                    <ItemsControl.ItemsPanel>
                        <ItemsPanelTemplate>
                            <WrapPanel Orientation="Horizontal" />
                        </ItemsPanelTemplate>
                    </ItemsControl.ItemsPanel>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
"@
    $axamlContent = $axamlContent -replace $oldRepeater, $newItemsControl
    [IO.File]::WriteAllText($libAxaml, $axamlContent)
    Log "LibraryView.axaml updated to ItemsControl."
}

# 2. Update LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# Revert Cards to ObservableCollection
$oldCardsProp = @"
    private IReadOnlyList<ModelCardViewModel> _cards = new List<ModelCardViewModel>();
    public IReadOnlyList<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@
$newCardsProp = @"
    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
"@
$content = $content -replace [regex]::Escape($oldCardsProp), $newCardsProp

# Revert ReloadModelsCoreAsync to use Clear/Add
$oldReload = @"
var newCards = new List<ModelCardViewModel>();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
"@
$newReload = @"
Cards.Clear();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
"@
$content = $content -replace [regex]::Escape($oldReload), $newReload

$content = $content -replace 'newCards\.Add\(card\);', 'Cards.Add(card);'

$oldEndLoop = @"
        // Replace the collection entirely to force ItemsRepeater to re-layout
        Cards = new ObservableCollection<ModelCardViewModel>(newCards);
        UpdatePreviewsStatus();
    }
"@
$newEndLoop = @"
        UpdatePreviewsStatus();
        Raise(nameof(IsEmpty));
    }
"@
$content = $content -replace [regex]::Escape($oldEndLoop), $newEndLoop

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs reverted to ObservableCollection and Clear/Add."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Perf: Reverted ItemsRepeater to ItemsControl + WrapPanel due to critical UI update bugs in Avalonia 11.1.5. 
- Fix: Restored stable ObservableCollection and Clear/Add for Cards to ensure filtering and navigation work correctly.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."