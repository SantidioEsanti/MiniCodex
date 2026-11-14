$ErrorActionPreference = "Stop"
$ver = "0.5.1a3"
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

Log "Starting patch $ver - Single Instance Lock"

$files = @(
    "$root\src\MiniCodex.App\Program.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

$prog = "$root\src\MiniCodex.App\Program.cs"
$content = [IO.File]::ReadAllText($prog)

if ($content -match "MiniCodex_SingleInstance_Mutex") {
    Log "Program.cs already patched. Skipping."
} else {
    Log "Patching Program.cs with Mutex logic..."
    
    # Normalize line endings to LF for reliable string replacement
    $content = $content.Replace("`r`n", "`n")

    # 1. Inject class members (Mutex and P/Invoke)
    $searchClass = "internal static class Program`n{"
    $replaceClass = "internal static class Program`n{`n    private static System.Threading.Mutex? _mutex;`n`n    [System.Runtime.InteropServices.DllImport(`"user32.dll`", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]`n    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);"
    $content = $content.Replace($searchClass, $replaceClass)

    # 2. Inject Mutex acquisition logic
    $searchAcquire = "        catch { }`n"
    $replaceAcquire = "        catch { }`n`n        _mutex = new System.Threading.Mutex(true, `"MiniCodex_SingleInstance_Mutex`", out bool createdNew);`n        if (!createdNew)`n        {`n            Log.Warn(`"[Program.Main] Another instance is already running. Exiting.`");`n            MessageBoxW(IntPtr.Zero, `"MiniCodex is already running. Please check your taskbar.`", `"MiniCodex`", 0x00000040);`n            _mutex.Dispose();`n            _mutex = null;`n            return;`n        }`n"
    $content = $content.Replace($searchAcquire, $replaceAcquire)

    # 3. Inject Mutex release logic in finally block
    $searchFinally = "        finally`n        {`n            Log.SessionEnd();`n        }"
    $replaceFinally = "        finally`n        {`n            Log.SessionEnd();`n            if (_mutex != null)`n            {`n                try { _mutex.ReleaseMutex(); } catch { }`n                _mutex.Dispose();`n            }`n        }"
    $content = $content.Replace($searchFinally, $replaceFinally)

    # Write back (keeping LF is fine for C#)
    [IO.File]::WriteAllText($prog, $content)
    Log "Program.cs updated with Mutex logic."
}

# Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- App: Added single-instance lock (Mutex) to prevent SQLite database race conditions.
- App: Added native MessageBox to warn user if another instance is already running.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."