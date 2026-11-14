$ErrorActionPreference = "Stop"
$ver = "0.5.1a11"
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

Log "Starting patch $ver - Reset tag on view attach"

$files = @(
    "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$csPath = "$root\src\MiniCodex.App\Views\LibraryView.axaml.cs"
$csContent = [IO.File]::ReadAllText($csPath)

if ($csContent -match "OnAttachedToVisualTree") {
    Log "LibraryView.axaml.cs already has OnAttachedToVisualTree. Skipping."
} else {
    $method = @"

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is MiniCodex.App.ViewModels.LibraryViewModel vm)
        {
            var allTag = System.Linq.Enumerable.FirstOrDefault(vm.Tags, t => string.IsNullOrEmpty(t.Id));
            if (allTag != null && vm.SelectedTag != allTag)
            {
                vm.SelectedTag = allTag;
            }
        }
    }
}
"@
    $lastBrace = $csContent.LastIndexOf("}")
    if ($lastBrace -ge 0) {
        $csContent = $csContent.Substring(0, $lastBrace) + $method
        [IO.File]::WriteAllText($csPath, $csContent)
        Log "Added OnAttachedToVisualTree to LibraryView.axaml.cs."
    } else {
        Log "ERROR: Could not find closing brace in LibraryView.axaml.cs"
    }
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- UI: Reset tag selection to "All models" when LibraryView is re-attached (fixes stuck tag filter after returning from a card).
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."