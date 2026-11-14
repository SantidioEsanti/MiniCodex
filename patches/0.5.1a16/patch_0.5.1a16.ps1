$ErrorActionPreference = "Stop"
$ver = "0.5.1a16"
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

Log "Starting patch $ver - Force TagTreeView selection sync and filter reset"

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

# 1. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)
$axamlContent = $axamlContent -replace '<TreeView Grid.Row="1"', '<TreeView x:Name="TagTreeView" Grid.Row="1"'
$axamlContent = $axamlContent -replace 'SelectedItem="\{Binding SelectedTag, Mode=TwoWay\}"', 'SelectedItem="{Binding SelectedTag, Mode=TwoWay}" SelectionChanged="OnTagSelectionChanged"'
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated with x:Name and SelectionChanged."

# 2. Update LibraryView.axaml.cs
$csPath = "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs"
$csContent = [IO.File]::ReadAllText($csPath)

if ($csContent -notmatch "OnTagSelectionChanged") {
    $method = @"

    private void OnTagSelectionChanged(object? sender, Avalonia.Controls.SelectionChangedEventArgs e)
    {
        if (sender is Avalonia.Controls.TreeView tv && tv.SelectedItem is MiniCodex.App.ViewModels.TagNodeViewModel node)
        {
            if (DataContext is MiniCodex.App.ViewModels.LibraryViewModel vm && vm.SelectedTag != node)
            {
                vm.SelectedTag = node;
            }
        }
    }
}
"@
    $lastBrace = $csContent.LastIndexOf("}")
    if ($lastBrace -ge 0) {
        $csContent = $csContent.Substring(0, $lastBrace) + $method
        [IO.File]::WriteAllText($csPath, $csContent)
        Log "LibraryView.axaml.cs updated with OnTagSelectionChanged."
    }
}

# 3. Update LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

$oldReset = '(?s)public void ResetFilter\(\).*?\}'
$newReset = @"
public void ResetFilter()
{
    _searchQuery = string.Empty;
    Raise(nameof(SearchQuery));
    _selectedTag = null;
    Raise(nameof(SelectedTag));
    _ = ReloadModelsAsync(CancellationToken.None);
}
"@
$content = $content -replace $oldReset, $newReset

# Add logging to track the SQL query parameters (using concatenation to avoid PS parser errors)
$oldSearch = 'var models = await _models\.SearchAsync\('
$newSearch = 'Log.Info("[LibraryViewModel] SearchQuery=''" + SearchQuery + "'' FilterTagIds=''" + FilterTagIds + "''");`n        var models = await _models.SearchAsync('
$content = $content -replace $oldSearch, $newSearch

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated with forced reset and logging."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Added explicit TreeView.SelectionChanged handler to force ViewModel update.
- UI: Hard-reset _selectedTag and _searchQuery in ResetFilter to bypass binding issues.
- Debug: Added logging of SearchQuery and FilterTagIds before executing search.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."