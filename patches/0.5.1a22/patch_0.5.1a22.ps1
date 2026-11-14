$ErrorActionPreference = "Stop"
$ver = "0.5.1a22"
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

Log "Starting patch $ver - Prevent LibraryViewModel from being disposed on navigation"

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

# 1. Replace DisposeAsync with a no-op
$oldDispose = @"
    public ValueTask DisposeAsync()
    {
        if (_disposed) return ValueTask.CompletedTask;
        _disposed = true;
        try { _lifetimeCts.Cancel(); } catch { }
        try { _lifetimeCts.Dispose(); } catch { }
        try { _previewSemaphore.Dispose(); } catch { }
        Log.Info("[LibraryViewModel] disposed (pending preview tasks cancelled)");
        return ValueTask.CompletedTask;
    }
"@
$newDispose = @"
    public ValueTask DisposeAsync()
    {
        // Ignored: LibraryViewModel is a singleton owned by MainWindowViewModel.
        // It must survive navigation to/from model cards.
        Log.Info("[LibraryViewModel] DisposeAsync called, but ignored to keep singleton alive.");
        return ValueTask.CompletedTask;
    }
"@
if ($content -match [regex]::Escape($oldDispose)) {
    $content = $content -replace [regex]::Escape($oldDispose), $newDispose
    Log "Replaced DisposeAsync with no-op."
} else {
    Log "WARNING: DisposeAsync block not found."
}

# 2. Remove _disposed checks from ReloadModelsCoreAsync
$content = $content -replace 'if \(_disposed\) return;', '// if (_disposed) return; // Removed for singleton pattern'

[IO.File]::WriteAllText($libVm, $content)
Log "LibraryViewModel.cs updated."

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Fix: Prevented premature disposal of LibraryViewModel when navigating to a card. This was causing the library to appear empty or stuck on the previous tag filter.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."