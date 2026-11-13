#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.0a — фикс stub-рендерера в тестах под новую сигнатуру Render.
.DESCRIPTION
    StubRenderer в PreviewGeneratorTests реализует IPreviewRenderer.
    Интерфейс получил float zoom = 1.0f (патч 0.3.0) — stub тоже должен.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.0a'
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

    $readme = @'
# Патч 0.3.0a — фикс stub-рендерера в тестах

**Итерация:** 0.3 · **Статус:** реализован

## Причина

`IPreviewRenderer.Render` получил 6-й параметр `float zoom = 1.0f` в патче 0.3.0.
Stub-реализация в `PreviewGeneratorTests.cs` осталась с 5 аргументами → CS0535.

## Что делает

- `StubRenderer.Render` теперь `(MeshGeometry, int, int, float, float, float zoom = 1.0f)`.
- Логика stub не меняется (по-прежнему возвращает PNG-сигнатуру + счётчик).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0a\patch_0.3.0a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.3.0a\README.md'

    $targetPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs'
    Backup-File $targetPath

    $content = [IO.File]::ReadAllText($targetPath, [Text.Encoding]::UTF8)

    if ($content -notmatch 'float zoom\s*=\s*1\.0f') {
        # Заменяем сигнатуру stub-метода
        $content = $content -replace
            'public byte\[\] Render\(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees\)',
            'public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f)'
        Write-Text -Path $targetPath -Content $content
        Write-Log 'updated: src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs (StubRenderer.Render +zoom)'
    } else {
        Write-Log 'PreviewGeneratorTests.cs: zoom уже есть, пропускаю.' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.3.0a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.3.0a: StubRenderer в PreviewGeneratorTests соответствует новой сигнатуре IPreviewRenderer.Render (с zoom).`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.0\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.0a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}