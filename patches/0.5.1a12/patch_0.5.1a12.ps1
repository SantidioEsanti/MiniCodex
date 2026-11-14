$ErrorActionPreference = "Stop"
$ver = "0.5.1a12"
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

Log "Starting patch $ver - Reset tag filter on Back navigation"

$files = @(
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

$mainVm = "$root\src\MiniCodex.App\ViewModels\MainWindowViewModel.cs"
$content = [IO.File]::ReadAllText($mainVm)

# Add System.Linq if missing
if ($content -notmatch "using System.Linq;") {
    $content = $content -replace 'using System.Windows.Input;', "using System.Windows.Input;`nusing System.Linq;"
}

$oldCode = @"
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
            onBack: () => CurrentPage = Library)
"@

$newCode = @"
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
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

if ($content -match [regex]::Escape($oldCode)) {
    $content = $content -replace [regex]::Escape($oldCode), $newCode
    [IO.File]::WriteAllText($mainVm, $content)
    Log "Updated onBack logic in MainWindowViewModel."
} else {
    Log "WARNING: Could not find onBack logic in MainWindowViewModel."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Reset tag filter to "All models" explicitly when returning from a card page.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."