$ErrorActionPreference = "Stop"
$ver = "0.5.1a24"
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

Log "Starting patch $ver - Serialize loading and fix ScrollViewer layout"

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

# 1. Update LibraryView.axaml (ScrollViewer settings, remove SelectionChanged)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)
$axamlContent = $axamlContent -replace '<TreeView x:Name="TagTreeView" Grid.Row="1".*?>', '<TreeView x:Name="TagTreeView" Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag, Mode=TwoWay}" Background="Transparent" BorderThickness="0">'
$axamlContent = $axamlContent -replace '<ScrollViewer Grid.Row="1" Background="Transparent">', '<ScrollViewer Grid.Row="1" Background="Transparent" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">'
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated."

# 2. Update LibraryView.axaml.cs (Remove OnTagSelectionChanged)
$csPath = "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs"
$csContent = [IO.File]::ReadAllText($csPath)
$oldMethod = '(?s)private void OnTagSelectionChanged\(.*?\}\s*\}'
$csContent = $csContent -replace $oldMethod, ''
[IO.File]::WriteAllText($csPath, $csContent)
Log "Removed OnTagSelectionChanged from LibraryView.axaml.cs."

# 3. Update LibraryViewModel.cs (Add Semaphore)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

$content = $content -replace 'private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim\(1, 1\);', "private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);`n    private readonly SemaphoreSlim _loadSemaphore = new SemaphoreSlim(1, 1);"

$content = $content -replace '(?s)private async Task ReloadModelsCoreAsync\(CancellationToken ct\).*?var models = await _models\.SearchAsync\(', @"
    private async Task ReloadModelsCoreAsync(CancellationToken ct)
    {
        if (_models == null || _files == null || _previews == null) return;
        await _loadSemaphore.WaitAsync(ct);
        try
        {
        var models = await _models.SearchAsync(
"@

$content = $content -replace '(?s)await Dispatcher\.UIThread\.InvokeAsync\(\(\) => \{\s*Cards\.Clear\(\);\s*foreach \(var c in newCards\) Cards\.Add\(c\);\s*PreviewsDone = 0;\s*PreviewsTotal = models\.Count;\s*UpdatePreviewsStatus\(\);\s*Raise\(nameof\(IsEmpty\)\);\s*\}\);\s*\}', @"
        await Dispatcher.UIThread.InvokeAsync(() => {
            Cards.Clear();
            foreach (var c in newCards) Cards.Add(c);
            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            UpdatePreviewsStatus();
            Raise(nameof(IsEmpty));
        });
        }
        finally
        {
            _loadSemaphore.Release();
        }
    }
"@

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated with Semaphore."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Serialized library loading with SemaphoreSlim to prevent concurrent reloads from overwriting Cards.
- Fix: Disabled horizontal scrolling in LibraryView to allow WrapPanel to measure correctly.
- Fix: Removed redundant OnTagSelectionChanged handler.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."