#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.3c — фикс направления света в превью.
.DESCRIPTION
    Меняет lightDir с (-0.3, -0.5, 1) на (-0.4, 0.6, 1) — свет сверху-слева.
    Bump RendererVersion -> инвалидация кэша превью.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.3c'
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

# ============ Скрипт делает 2 точечные замены через regex ============

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    # README
    $readme = @'
# Патч 0.2.3c — направление света в превью

**Итерация:** 0.2 · **Статус:** реализован

## Причина

В `SkiaPreviewRenderer` вектор света `(-0.3f, -0.5f, 1f)` указывал вниз. В системе
координат рендерера `+Y = вверх`, поэтому отрицательный Y давал подсветку снизу.

## Что делает

- `lightDir = (-0.4, 0.6, 1)` — нормализованный: свет сверху-слева-спереди.
- `RendererVersion = "0.2.3c"` → кэш превью инвалидируется, все PNG перегенерируются
  при первом показе карточек.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3c\patch_0.2.3c.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- Визуально: верхняя часть модели светлее, нижняя — темнее; тени «под подбородком»,
  под оружием, под складками плаща — снизу.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.2.3c\README.md'

    # --- 1. SkiaPreviewRenderer.cs: lightDir ---
    $rendererPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    Backup-File $rendererPath
    $content = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    $newContent = $content -replace 'new Vector3\(-0\.3f, -0\.5f, 1f\)', 'new Vector3(-0.4f, 0.6f, 1f)'
    if ($newContent -ne $content) {
        Write-Text -Path $rendererPath -Content $newContent
        Write-Log 'updated: src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs (lightDir → (-0.4, 0.6, 1))'
    } elseif ($content -match 'new Vector3\(-0\.4f, 0\.6f, 1f\)') {
        Write-Log 'SkiaPreviewRenderer.cs: lightDir уже обновлён, пропускаю.' 'WARN'
    } else {
        Write-Log 'SkiaPreviewRenderer.cs: не найден старый lightDir, проверьте вручную!' 'WARN'
    }

    # --- 2. PreviewGenerator.cs: RendererVersion ---
    $genPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    Backup-File $genPath
    $genContent = [IO.File]::ReadAllText($genPath, [Text.Encoding]::UTF8)
    $newGenContent = $genContent -replace 'RendererVersion = "0\.2\.3b"', 'RendererVersion = "0.2.3c"'
    if ($newGenContent -ne $genContent) {
        Write-Text -Path $genPath -Content $newGenContent
        Write-Log 'updated: src\MiniCodex.Core\Services\PreviewGenerator.cs (RendererVersion = 0.2.3c)'
    } elseif ($genContent -match 'RendererVersion = "0\.2\.3c"') {
        Write-Log 'PreviewGenerator.cs: RendererVersion уже 0.2.3c, пропускаю.' 'WARN'
    } else {
        Write-Log 'PreviewGenerator.cs: не найден RendererVersion 0.2.3b, проверьте вручную!' 'WARN'
    }

    # --- CHANGELOG ---
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')
    $marker = '<!-- patch 0.2.3c applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.3c: направление света в превью — сверху-слева вместо снизу.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.3b\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.3c.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}