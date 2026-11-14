$ErrorActionPreference = "Stop"
$ver = "0.5.1a20"
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

Log "Starting patch $ver - Force UI redraw by replacing Cards collection"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Update LibraryView.axaml (Ensure ItemsControl, not ItemsRepeater)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)

if ($axamlContent -match "ItemsRepeater") {
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
    Log "Replaced ItemsRepeater with ItemsControl in LibraryView.axaml."
} else {
    Log "LibraryView.axaml already has ItemsControl."
}

# 2. Update LibraryViewModel.cs (Replace collection instead of Clear/Add)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# Change Cards to a settable property
$oldProp = 'public ObservableCollection<ModelCardViewModel> Cards \{ get; \} = new\(\);'
$newProp = @"
private ObservableCollection<ModelCardViewModel> _cards = new();
    public ObservableCollection<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@
$content = $content -replace $oldProp, $newProp

# Fix ReloadModelsCoreAsync
$oldReload = @"
        Cards.Clear();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
"@
$newReload = @"
        var newCards = new List<ModelCardViewModel>();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
"@
$content = $content -replace [regex]::Escape($oldReload), $newReload

$content = $content -replace 'Cards\.Add\(card\);', 'newCards.Add(card);'

$oldEndLoop = @"
        UpdatePreviewsStatus();
        Raise(nameof(IsEmpty));
    }

    public async Task ScanAsync
"@
$newEndLoop = @"
        Cards = new ObservableCollection<ModelCardViewModel>(newCards);
        UpdatePreviewsStatus();
    }

    public async Task ScanAsync
"@
$content = $content -replace [regex]::Escape($oldEndLoop), $newEndLoop

# Fix ForceShowAllAsync
$oldForceLoop = @"
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
"@
$newForceLoop = @"
            var newCards = new List<ModelCardViewModel>();
            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor);
                newCards.Add(card);
            }
            Cards = new ObservableCollection<ModelCardViewModel>(newCards);
            Log.Info("[ForceShowAll-v18] new collection assigned. Count=" + Cards.Count);

            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
"@
$content = $content -replace [regex]::Escape($oldForceLoop), $newForceLoop

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated to replace collection."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Replaced Cards collection entirely on reload to force ItemsControl to redraw.
- UI: Ensured LibraryView uses stable ItemsControl.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."