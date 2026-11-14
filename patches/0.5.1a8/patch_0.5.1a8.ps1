$ErrorActionPreference = "Stop"
$ver = "0.5.1a8"
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

Log "Starting patch $ver - Fix ModelRepository tag filter and Cards update"

$files = @(
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

# 1. Update ModelRepository.cs
$repoPath = "$root\src\MiniCodex.Data\Repositories\ModelRepository.cs"
$repoContent = [IO.File]::ReadAllText($repoPath)

$oldSql = @"
        if (!string.IsNullOrEmpty(tagId))
        {
            sb.Append("AND mt.tag_id = `$tagId ");
            cmd.Parameters.AddWithValue("`$tagId", tagId);
        }
"@
$newSql = @"
        if (!string.IsNullOrEmpty(tagId))
        {
            var tags = tagId.Split(',', StringSplitOptions.RemoveEmptyEntries);
            if (tags.Length > 0)
            {
                sb.Append("AND mt.tag_id IN (");
                for (int i = 0; i < tags.Length; i++)
                {
                    var p = `$"`$tag{i}";
                    if (i > 0) sb.Append(", ");
                    sb.Append(p);
                    cmd.Parameters.AddWithValue(p, tags[i]);
                }
                sb.Append(") ");
            }
        }
"@
$repoContent = $repoContent -replace [regex]::Escape($oldSql), $newSql
[IO.File]::WriteAllText($repoPath, $repoContent)
Log "ModelRepository.cs updated for multi-tag filtering."

# 2. Update LibraryViewModel.cs (Cards property)
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

$oldCards = @"
    private ObservableCollection<ModelCardViewModel> _cards = new();
    public ObservableCollection<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@
$newCards = @"
    private IReadOnlyList<ModelCardViewModel> _cards = new List<ModelCardViewModel>();
    public IReadOnlyList<ModelCardViewModel> Cards
    {
        get => _cards;
        private set { _cards = value; Raise(); Raise(nameof(IsEmpty)); }
    }
"@
$content = $content -replace [regex]::Escape($oldCards), $newCards

$content = $content -replace 'Cards = new ObservableCollection<ModelCardViewModel>\(newCards\);', 'Cards = newCards;'
[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated to use IReadOnlyList for Cards."

# 3. Update LibraryView.axaml (TwoWay binding)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)

$axamlContent = $axamlContent -replace 'SelectedItem="\{Binding SelectedTag\}"', 'SelectedItem="{Binding SelectedTag, Mode=TwoWay}"'
[IO.File]::WriteAllText($libAxaml, $axamlContent)
Log "LibraryView.axaml updated with TwoWay binding."

# 4. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Data: Updated ModelRepository.SearchAsync to support comma-separated tag IDs (IN clause).
- UI: Changed Cards collection to IReadOnlyList to fix ItemsRepeater rendering on replacement.
- UI: Set TreeView.SelectedItem to TwoWay binding.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."