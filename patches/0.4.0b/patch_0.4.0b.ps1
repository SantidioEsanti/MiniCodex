#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.4.0c — добавление Anycubic Slicer и Slicer Next.
.DESCRIPTION
    Точечная вставка в IntegrationCatalog.cs (в отличие от 0.4.0b).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.0c'
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

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $catalogPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\IntegrationCatalog.cs'
    Backup-File $catalogPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8)
    
    if ($content -notmatch 'anycubic-slicer') {
        $anycubic = @'
        // ---------- Anycubic ----------
        new IntegrationAppDefinition(
            "anycubic-slicer", "Anycubic Slicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\AnycubicSlicer\Anycubic-Slicer.exe",
                @"C:\Program Files\Anycubic\Anycubic-Slicer.exe",
                @"%LOCALAPPDATA%\Programs\AnycubicSlicer\Anycubic-Slicer.exe",
            },
            "Anycubic-Slicer.exe",
            new[] { "Anycubic Slicer" }),

        new IntegrationAppDefinition(
            "anycubic-slicer-next", "Anycubic Slicer Next", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\AnycubicSlicerNext\AnycubicSlicerNext.exe",
                @"%LOCALAPPDATA%\Programs\AnycubicSlicerNext\AnycubicSlicerNext.exe",
            },
            "AnycubicSlicerNext.exe",
            new[] { "Anycubic Slicer Next", "AnycubicSlicerNext" }),

        // ---------- Editors ----------
        '@
        
        # Вставляем блок Anycubic перед блоком Editors
        $newContent = $content -replace '(?m)^(\s*// ---------- Editors ----------)', $anycubic
        [IO.File]::WriteAllText($catalogPath, $newContent, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.Core\Services\IntegrationCatalog.cs (Anycubic)'
    } else {
        Write-Log 'IntegrationCatalog.cs: Anycubic уже есть, пропускаю.' 'WARN'
    }

    $readme = @'
# Патч 0.4.0c — Anycubic Slicer

**Итерация:** 0.4 · **Статус:** реализован

## Причина
Патч 0.4.0b не применился (скрипт был пустым). Текущий патч добавляет
Anycubic Slicer и Anycubic Slicer Next в каталог интеграций.

## Запуск
powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.4.0c\patch_0.4.0c.ps1"
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme

    # CHANGELOG
    $marker = '<!-- patch 0.4.0c applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Added`n- 0.4.0c: Anycubic Slicer и Anycubic Slicer Next.`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.0b\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.4.0c.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}