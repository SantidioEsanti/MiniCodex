$ErrorActionPreference = "Stop"
$ver = "0.5.1a6"
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

Log "Starting patch $ver - Tag Hierarchy in UI"

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

# 1. Create TagNodeViewModel.cs
$nodeVmPath = "$root\src\MiniCodex.App\ViewModels\TagNodeViewModel.cs"
$nodeVmCode = @"
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace MiniCodex.App.ViewModels;

public class TagNodeViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? ParentId { get; set; }
    
    private int _usageCount;
    public int UsageCount
    {
        get => _usageCount;
        set { _usageCount = value; Raise(); }
    }

    public ObservableCollection<TagNodeViewModel> Children { get; } = new();

    private bool _isExpanded = true;
    public bool IsExpanded
    {
        get => _isExpanded;
        set { _isExpanded = value; Raise(); }
    }
}
"@
[IO.File]::WriteAllText($nodeVmPath, $nodeVmCode, [Text.Encoding]::UTF8)
Log "Created TagNodeViewModel.cs"

# 2. Update LibraryViewModel.cs
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

if ($content -match "TagNodeViewModel") {
    Log "LibraryViewModel.cs already patched. Skipping."
} else {
    Log "Patching LibraryViewModel.cs..."
    
    $content = $content -replace 'public ObservableCollection<TagWithUsage> Tags \{ get; \} = new\(\);', 'public ObservableCollection<TagNodeViewModel> Tags { get; } = new();'
    $content = $content -replace 'private TagWithUsage\? _selectedTag;', 'private TagNodeViewModel? _selectedTag;'
    $content = $content -replace 'public TagWithUsage\? SelectedTag', 'public TagNodeViewModel? SelectedTag'
    
    # Replace FilterTagId with FilterTagIds and add GetDescendantIds
    $oldFilter = 'private string\? FilterTagId => string\.IsNullOrEmpty\(SelectedTag\?\.Id\) \? null : SelectedTag!\.Id;'
    $newFilter = @"
    private string? FilterTagIds => string.IsNullOrEmpty(SelectedTag?.Id) ? null : GetDescendantIds(SelectedTag);

    private string GetDescendantIds(TagNodeViewModel node)
    {
        var ids = new List<string> { node.Id };
        foreach (var child in node.Children)
        {
            ids.AddRange(GetDescendantIds(child).Split(',', StringSplitOptions.RemoveEmptyEntries));
        }
        return string.Join(",", ids);
    }
"@
    $content = $content -replace $oldFilter, $newFilter

    # Update SearchAsync call
    $content = $content -replace 'FilterTagId, ct\);', 'FilterTagIds, ct);'

    # Replace LoadTagsAsync method body
    $oldLoadTags = '(?s)private async Task LoadTagsAsync\(CancellationToken ct\).*?finally \{ _suppressTagReload = false; \}\s*\}'
    $newLoadTags = @"
    private async Task LoadTagsAsync(CancellationToken ct)
    {
        if (_tagService == null || _models == null) return;
        try
        {
            _suppressTagReload = true;
            Tags.Clear();
            var allModels = await _models.GetAllAsync(ct);
            var tagUsages = await _tagService.GetAllWithUsageAsync(ct);
            var allLabel = App.Loc?.Get("Library.AllModels") ?? "All models";
            
            var rootAll = new TagNodeViewModel { Id = "", Name = allLabel, UsageCount = allModels.Count };
            Tags.Add(rootAll);

            var dict = new Dictionary<string, TagNodeViewModel>();
            foreach (var t in tagUsages)
            {
                dict[t.Id] = new TagNodeViewModel { Id = t.Id, Name = t.Name, ParentId = t.ParentId, UsageCount = t.UsageCount };
            }

            foreach (var t in tagUsages)
            {
                if (!string.IsNullOrEmpty(t.ParentId) && dict.TryGetValue(t.ParentId, out var parent))
                {
                    parent.Children.Add(dict[t.Id]);
                }
                else
                {
                    Tags.Add(dict[t.Id]);
                }
            }

            void SumUsage(TagNodeViewModel node)
            {
                int sum = node.UsageCount;
                foreach (var child in node.Children)
                {
                    SumUsage(child);
                    sum += child.UsageCount;
                }
                node.UsageCount = sum;
            }
            foreach (var t in Tags)
            {
                if (t.Id != "") SumUsage(t);
            }

            var currentId = _selectedTag?.Id;
            _selectedTag = currentId != null
                ? Tags.FirstOrDefault(t => t.Id == currentId)
                : Tags.FirstOrDefault();
            Raise(nameof(SelectedTag));
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadTags failed", ex); }
        finally { _suppressTagReload = false; }
    }
"@
    $content = $content -replace $oldLoadTags, $newLoadTags

    [IO.File]::WriteAllText($libVm, $content)
    Log "LibraryViewModel.cs updated."
}

# 3. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$axamlContent = [IO.File]::ReadAllText($libAxaml)

if ($axamlContent -match "TreeView") {
    Log "LibraryView.axaml already using TreeView. Skipping."
} else {
    Log "Replacing ListBox with TreeView in LibraryView.axaml..."
    
    $oldListBox = '(?s)<ListBox Grid\.Row="1" ItemsSource="\{Binding Tags\}" SelectedItem="\{Binding SelectedTag\}">.*?</ListBox>'
    $newTreeView = @"
<TreeView Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag}" Background="Transparent" BorderThickness="0">
                        <TreeView.ItemTemplate>
                            <TreeDataTemplate ItemsSource="{Binding Children}">
                                <Grid ColumnDefinitions="*,Auto">
                                    <TextBlock Text="{Binding Name}" TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Grid.Column="1" Text="{Binding UsageCount}"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               FontSize="11" Margin="6,0,0,0"/>
                                </Grid>
                            </TreeDataTemplate>
                        </TreeView.ItemTemplate>
                    </TreeView>
"@
    $axamlContent = $axamlContent -replace $oldListBox, $newTreeView
    [IO.File]::WriteAllText($libAxaml, $axamlContent)
    Log "LibraryView.axaml updated."
}

# 4. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Replaced flat ListBox with TreeView for tag hierarchy.
- UI: Added TagNodeViewModel and recursive tree building in LibraryViewModel.
- Note: Filtering by parent tag passes comma-separated IDs to SearchAsync. ModelRepository may need updating to handle this.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."