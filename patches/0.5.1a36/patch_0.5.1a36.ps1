$ErrorActionPreference = "Stop"
$ver = "0.5.1a36"
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

Log "Starting patch $ver - Duplicate Detection UI and Logic"

$files = @(
    "$root\src\MiniCodex.Core\Repositories\IRepositories.cs",
    "$root\src\MiniCodex.Data\Repositories\ModelRepository.cs",
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

# 1. Update IRepositories.cs
$repoInt = "$root\src\MiniCodex.Core\Repositories\IRepositories.cs"
$intContent = [IO.File]::ReadAllText($repoInt)
$intContent = $intContent.Replace(
    "Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default);",
    "Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default);`r`n    Task<IReadOnlyList<string>> GetDuplicateModelIdsAsync(CancellationToken ct = default);"
)
[IO.File]::WriteAllText($repoInt, $intContent)
Log "IRepositories.cs updated."

# 2. Update ModelRepository.cs
$repoPath = "$root\src\MiniCodex.Data\Repositories\ModelRepository.cs"
$repoContent = [IO.File]::ReadAllText($repoPath)
$newMethod = @"

    public async Task<IReadOnlyList<string>> GetDuplicateModelIdsAsync(CancellationToken ct = default)
    {
        var result = new List<string>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            SELECT m.id 
            FROM Model m 
            JOIN ModelFile mf ON mf.model_id = m.id 
            WHERE mf.file_hash IN (
                SELECT file_hash 
                FROM ModelFile 
                WHERE file_hash IS NOT NULL AND file_hash != ''
                GROUP BY file_hash 
                HAVING COUNT(*) > 1
            )
            GROUP BY m.id;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(r.GetString(0));
        return result;
    }

    public async Task UpdateStatusDifficultyAsync"@
$repoContent = $repoContent.Replace("    public async Task UpdateStatusDifficultyAsync", $newMethod)
[IO.File]::WriteAllText($repoPath, $repoContent)
Log "ModelRepository.cs updated with GetDuplicateModelIdsAsync."

# 3. Update LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$vmContent = [IO.File]::ReadAllText($libVm)

# Add properties and command
$props = @"
    private bool _showDuplicatesOnly;
    public bool ShowDuplicatesOnly
    {
        get => _showDuplicatesOnly;
        set
        {
            if (_showDuplicatesOnly == value) return;
            _showDuplicatesOnly = value;
            Raise();
            Raise(nameof(DuplicatesButtonText));
            _ = ReloadModelsAsync(CancellationToken.None);
        }
    }

    public string DuplicatesButtonText => ShowDuplicatesOnly ? (App.Loc?.Get("Library.ShowAll") ?? "Show all") : (App.Loc?.Get("Library.FindDuplicates") ?? "Find duplicates");

    public ICommand ToggleDuplicatesCommand { get; }
"@
$vmContent = $vmContent.Replace("public ICommand RequestFocusSearchCommand { get; }", $props + "`r`n    public ICommand RequestFocusSearchCommand { get; }")

# Initialize command in constructor
$vmContent = $vmContent.Replace(
    "RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));",
    "RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));`r`n        ToggleDuplicatesCommand = new RelayCommand(() => ShowDuplicatesOnly = !ShowDuplicatesOnly);"
)

# Modify ReloadModelsCoreAsync
$oldReloadLogic = @"
            var models = await _models.SearchAsync(
                string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
                FilterTagIds, ct);

            Cards.Clear();
"@
$newReloadLogic = @"
            var models = await _models.SearchAsync(
                string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
                FilterTagIds, ct);

            if (ShowDuplicatesOnly)
            {
                var dupIds = await _models.GetDuplicateModelIdsAsync(ct);
                var dupSet = new HashSet<string>(dupIds);
                models = models.Where(m => dupSet.Contains(m.Id)).ToList();
            }

            Cards.Clear();
"@
$vmContent = $vmContent.Replace($oldReloadLogic, $newReloadLogic)

# Update ResetFilter to reset duplicates
$vmContent = $vmContent.Replace(
    "public void ResetFilter()`r`n{`r`n    _searchQuery = string.Empty;",
    "public void ResetFilter()`r`n{`r`n    _showDuplicatesOnly = false;`r`n    Raise(nameof(DuplicatesButtonText));`r`n    _searchQuery = string.Empty;"
)

[IO.File]::WriteAllText($libVm, $vmContent)
Log "LibraryViewModel.cs updated with duplicate logic."

# 4. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)
$axamlContent = $axamlContent.Replace(
    '<Button Content="{Binding ScanButtonText}" Click="OnScanClick"/>',
    '<Button Content="{Binding ScanButtonText}" Click="OnScanClick"/>`r`n                    <Button Content="{Binding DuplicatesButtonText}" Command="{Binding ToggleDuplicatesCommand}"/>'
)
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated with ToggleDuplicates button."

# 5. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Feature: Implemented duplicate detection based on file hash.
- UI: Added "Find duplicates" button to library toolbar.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."