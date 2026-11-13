#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.1a — фикс сборки тестов (недостающий using).
.DESCRIPTION
    Добавляет using MiniCodex.Core.Repositories в ScannerServiceTests.cs.
    Идемпотентен: повторный запуск ничего не делает, если using уже есть.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.1a'
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

# ============ README патча ============
$readme = @'
# Патч 0.2.1a — фикс сборки тестов

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- Добавляет `using MiniCodex.Core.Repositories;` в `src\MiniCodex.Tests\Services\ScannerServiceTests.cs`.
- Причина: поля теста используют `IModelRepository` и `IModelFileRepository` из `MiniCodex.Core.Repositories`, но в файле отсутствовала соответствующая директива `using`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1a\patch_0.2.1a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 17 тестов, все зелёные.
'@

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.2.1a\README.md'

    $targetPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\Services\ScannerServiceTests.cs'
    Backup-File $targetPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($targetPath, [Text.Encoding]::UTF8)

    if ($content -notmatch 'using MiniCodex\.Core\.Repositories;') {
        # Вставляем после using MiniCodex.Core.Services;
        $content = $content -replace '(using MiniCodex\.Core\.Services;)', "`$1`r`nusing MiniCodex.Core.Repositories;"
        Write-Text -Path $targetPath -Content $content
        Write-Log 'updated: src\MiniCodex.Tests\Services\ScannerServiceTests.cs (using MiniCodex.Core.Repositories)'
    } else {
        Write-Log 'ScannerServiceTests.cs: using уже есть, пропускаю.' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.1a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.1a: недостающий using MiniCodex.Core.Repositories в ScannerServiceTests.cs.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.1a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}