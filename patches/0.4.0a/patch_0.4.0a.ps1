#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.4.0a — фикс App.Loc (CS1061) + CA1416 в WindowsRegistryProbe.
.DESCRIPTION
    IntegrationAppRowViewModel: хелпер Loc() через MiniCodex.App.App.Loc.
    WindowsRegistryProbe: [SupportedOSPlatform("windows")].
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.0a'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel -> $dst"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# ============ App/ViewModels/IntegrationAppRowViewModel.cs ============
$rowVm = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class IntegrationAppRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public IntegrationApp App { get; }

    public string DisplayName => App.DisplayName;
    public string CurrentPath => App.Path ?? string.Empty;

    public string StatusText
    {
        get
        {
            if (App.IsUserOverride) return Loc("Settings.Integrations.StatusManual", "Manual");
            if (App.IsDetected) return Loc("Settings.Integrations.StatusAuto", "Auto");
            return Loc("Settings.Integrations.StatusMissing", "Not found");
        }
    }

    public string BrowseText => Loc("Settings.Integrations.Browse", "Browse…");
    public string ClearText => Loc("Settings.Integrations.Clear", "Clear");

    public ICommand BrowseCommand { get; }
    public ICommand ClearCommand { get; }

    public IntegrationAppRowViewModel(
        IntegrationApp app,
        Func<IntegrationAppRowViewModel, Task> onBrowse,
        Func<IntegrationAppRowViewModel, Task> onClear)
    {
        App = app;
        BrowseCommand = new RelayCommand(async () => await onBrowse(this));
        ClearCommand = new RelayCommand(async () => await onClear(this));
    }

    public void RefreshLocalized()
    {
        Raise(nameof(StatusText));
        Raise(nameof(BrowseText));
        Raise(nameof(ClearText));
    }

    // Полностью квалифицированное обращение, чтобы не конфликтовать со свойством App.
    private static string Loc(string key, string fallback)
        => MiniCodex.App.App.Loc?.Get(key) ?? fallback;
}
'@

# ============ App/Services/WindowsRegistryProbe.cs ============
$probe = @'
using System.Runtime.Versioning;
using Microsoft.Win32;
using MiniCodex.Core.Services;

namespace MiniCodex.App.Services;

[SupportedOSPlatform("windows")]
public class WindowsRegistryProbe : IIntegrationProbe
{
    private static readonly string[] UninstallRoots =
    {
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    };

    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
    {
        var found = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var def in IntegrationCatalog.All)
        {
            if (ct.IsCancellationRequested) break;

            var path = TryCommonPaths(def) ?? TryRegistry(def);
            if (path != null) found[def.Id] = path;
        }
        return Task.FromResult<IReadOnlyDictionary<string, string>>(found);
    }

    private static string? TryCommonPaths(IntegrationAppDefinition def)
    {
        foreach (var raw in def.CommonPaths)
        {
            var expanded = Environment.ExpandEnvironmentVariables(raw);
            if (File.Exists(expanded)) return expanded;
        }
        return null;
    }

    private static string? TryRegistry(IntegrationAppDefinition def)
    {
        foreach (var hive in new[] { Registry.LocalMachine, Registry.CurrentUser })
        {
            foreach (var rootPath in UninstallRoots)
            {
                try
                {
                    using var root = hive.OpenSubKey(rootPath);
                    if (root == null) continue;
                    foreach (var subKeyName in root.GetSubKeyNames())
                    {
                        using var subKey = root.OpenSubKey(subKeyName);
                        if (subKey == null) continue;
                        var displayName = subKey.GetValue("DisplayName") as string;
                        if (string.IsNullOrEmpty(displayName)) continue;
                        if (!def.RegistryNameHints.Any(h => displayName.Contains(h, StringComparison.OrdinalIgnoreCase)))
                            continue;

                        var installLoc = subKey.GetValue("InstallLocation") as string;
                        if (!string.IsNullOrEmpty(installLoc))
                        {
                            var candidate = Path.Combine(installLoc, def.ExeName);
                            if (File.Exists(candidate)) return candidate;
                        }

                        var icon = subKey.GetValue("DisplayIcon") as string;
                        if (!string.IsNullOrEmpty(icon))
                        {
                            var cleaned = icon.Split(',')[0].Trim().Trim('"');
                            if (cleaned.EndsWith(def.ExeName, StringComparison.OrdinalIgnoreCase) && File.Exists(cleaned))
                                return cleaned;
                        }
                    }
                }
                catch { /* access denied — пропускаем */ }
            }
        }
        return null;
    }
}
'@

# ============ README ============
$readme = @'
# Патч 0.4.0a — фикс сборки App

**Итерация:** 0.4 · **Статус:** реализован

## Причины

1. **CS1061 (`IntegrationApp.Loc`)** — `IntegrationAppRowViewModel` имеет свойство
   `public IntegrationApp App { get; }`, которое shadow'ит класс `MiniCodex.App.App`.
   Вызов `App.Loc?.Get(...)` компилятор трактует как «Loc на IntegrationApp».
2. **CA1416 (8 предупреждений)** — `Microsoft.Win32.Registry` — Windows-only.
   Приложение по контракту Windows-only (HANDOFF), анализатор требует
   `[SupportedOSPlatform("windows")]`.

## Что делает

- `IntegrationAppRowViewModel`: добавлен хелпер `Loc(key, fallback)` через
  `MiniCodex.App.App.Loc` (полная квалификация). Логика не меняется.
- `WindowsRegistryProbe`: `[SupportedOSPlatform("windows")]` на классе +
  `using System.Runtime.Versioning;`. Анализатор доволен, поведение то же.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.4.0a\patch_0.4.0a.ps1"

## DoD

- `dotnet build` — 0 ошибок, 0 предупреждений.
- `dotnet test` — 40/40.
'@

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $rowPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\IntegrationAppRowViewModel.cs'
    $probePath = Join-Path $ProjectRoot 'src\MiniCodex.App\Services\WindowsRegistryProbe.cs'

    Backup-File $rowPath
    Backup-File $probePath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.0a\README.md'

    Write-Text -Path $rowPath -Content $rowVm
    Write-Log 'updated: src\MiniCodex.App\ViewModels\IntegrationAppRowViewModel.cs (Loc через полную квалификацию)'

    Write-Text -Path $probePath -Content $probe
    Write-Log 'updated: src\MiniCodex.App\Services\WindowsRegistryProbe.cs ([SupportedOSPlatform("windows")])'

    # CHANGELOG
    $marker = '<!-- patch 0.4.0a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.4.0a: IntegrationAppRowViewModel — Loc через MiniCodex.App.App.Loc (CS1061).`n- 0.4.0a: WindowsRegistryProbe — [SupportedOSPlatform(`"windows`")] (CA1416).`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.0\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.4.0a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}