$ErrorActionPreference = "Stop"
$ver = "0.5.1a13"
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

Log "Starting patch $ver - Force filter reset on library navigation"

$files = @(
    "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs",
    "$root\src\MiniCodex.App\ViewModels\MainWindowViewModel.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Add ResetFilter to LibraryViewModel
$libVm = "$root\src\MiniCodex.App\ViewModels\LibraryViewModel.cs"
$content = [IO.File]::ReadAllText($libVm)

$resetMethod = @"
    public void ResetFilter()
    {
        SearchQuery = string.Empty;
        var allTag = Tags.FirstOrDefault(t => string.IsNullOrEmpty(t.Id));
        _selectedTag = allTag;
        Raise(nameof(SelectedTag));
        _ = ReloadModelsAsync(CancellationToken.None);
    }
"@

if ($content -notmatch "public void ResetFilter\(\)") {
    $lastBrace = $content.LastIndexOf("}")
    if ($lastBrace -ge 0) {
        $content = $content.Substring(0, $lastBrace) + $resetMethod + "`n}"
        [IO.File]::WriteAllText($libVm, $content)
        Log "Added ResetFilter to LibraryViewModel."
    }
} else {
    Log "ResetFilter already exists."
}

# 2. Update MainWindowViewModel
$mainVm = "$root\src\MiniCodex.App\ViewModels\MainWindowViewModel.cs"
$mainContent = [IO.File]::ReadAllText($mainVm)

# Update ShowLibraryCommand
$oldShowLib = 'ShowLibraryCommand = new RelayCommand\(\(\) => CurrentPage = Library\);'
$newShowLib = @"
        ShowLibraryCommand = new RelayCommand(() =>
        {
            Library.ResetFilter();
            CurrentPage = Library;
        });
"@
if ($mainContent -match $oldShowLib) {
    $mainContent = $mainContent -replace $oldShowLib, $newShowLib
    Log "Updated ShowLibraryCommand."
}

# Update onBack
$oldOnBack = @"
            onBack: () =>
            {
                // Reset filter to "All models" before showing library
                var allTag = Library.Tags.FirstOrDefault(t => string.IsNullOrEmpty(t.Id));
                if (allTag != null && Library.SelectedTag != allTag)
                {
                    Library.SelectedTag = allTag;
                }
                CurrentPage = Library;
            })
"@
$newOnBack = @"
            onBack: () =>
            {
                Library.ResetFilter();
                CurrentPage = Library;
            })
"@
if ($mainContent -match [regex]::Escape($oldOnBack)) {
    $mainContent = $mainContent -replace [regex]::Escape($oldOnBack), $newOnBack
    Log "Updated onBack logic."
} else {
    # If the old onBack wasn't found (maybe formatting changed), try a looser regex
    $loosePattern = '(?s)onBack:\s*\(\)\s*=>\s*\{.*?CurrentPage = Library;.*?\}\)'
    if ($mainContent -match $loosePattern) {
        $mainContent = $mainContent -replace $loosePattern, $newOnBack
        Log "Updated onBack logic (loose match)."
    } else {
        Log "WARNING: Could not find onBack logic."
    }
}

[IO.File]::WriteAllText($mainVm, $mainContent)

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Added `ResetFilter` to LibraryViewModel to forcibly clear tag and search filters.
- UI: Ensured both "Back" button and top menu "Library" button trigger a full filter reset.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."