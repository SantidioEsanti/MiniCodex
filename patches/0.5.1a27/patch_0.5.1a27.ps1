$ErrorActionPreference = "Stop"
$ver = "0.5.1a27"
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

Log "Starting patch $ver - Final fix for Cards collection and UI updates"

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

$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

# 1. Restore Cards to a simple get-only ObservableCollection
$oldProp = '(?s)private ObservableCollection<ModelCardViewModel> _cards = new\(\);.*?public ObservableCollection<ModelCardViewModel> Cards\s*\{\s*get => _cards;\s*private set\s*\{.*?\}\s*\}'
$newProp = 'public ObservableCollection<ModelCardViewModel> Cards { get; } = new();'
$content = $content -replace $oldProp, $newProp
$content = $content -replace 'private IReadOnlyList<ModelCardViewModel> _cards = new List<ModelCardViewModel>\(\);.*?public IReadOnlyList<ModelCardViewModel> Cards\s*\{\s*get => _cards;\s*private set\s*\{.*?\}\s*\}', $newProp

# 2. Clean up ForceShowAllAsync
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
}
"@
$content = $content -replace $oldForce, $newForce

# 3. Fix ReloadModelsCoreAsync completely
$oldReload = '(?s)private async Task ReloadModelsCoreAsync\(CancellationToken ct\).*?\}\s*public async Task ScanAsync'
$newReload = @"
    private async Task ReloadModelsCoreAsync(CancellationToken ct)
    {
        if (_models == null || _files == null || _previews == null) return;
        await _loadSemaphore.WaitAsync(ct);
        try
        {
            var models = await _models.SearchAsync(
                string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
                FilterTagIds, ct);

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

                _ = Task.Run(async () =>
                {
                    if (lifetimeToken.IsCancellationRequested) return;
                    await _previewSemaphore.WaitAsync(lifetimeToken).ConfigureAwait(false);
                    try
                    {
                        if (lifetimeToken.IsCancellationRequested) return;
                        await card.LoadDetailsAsync(_files, _previews, lifetimeToken).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException) { }
                    catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadDetails failed", ex); }
                    finally
                    {
                        _previewSemaphore.Release();
                        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                        {
                            PreviewsDone++;
                            UpdatePreviewsStatus();
                        });
                    }
                }, lifetimeToken);
            }

            UpdatePreviewsStatus();
            Raise(nameof(IsEmpty));
        }
        catch (Exception ex)
        {
            Log.Exception("[LibraryViewModel] ReloadModelsCoreAsync failed", ex);
        }
        finally
        {
            _loadSemaphore.Release();
        }
    }

    public async Task ScanAsync
"@
$content = $content -replace $oldReload, $newReload

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs completely fixed."

# 4. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Restored `Cards` to a standard get-only `ObservableCollection`.
- Fix: Removed complex `Dispatcher.InvokeAsync` and collection replacement logic from `ReloadModelsCoreAsync`. Cards are now populated directly, ensuring UI reacts instantly.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."