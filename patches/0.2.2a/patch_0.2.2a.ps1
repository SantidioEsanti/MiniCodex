#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.2a — фикс теста Render_DifferentAngles_ProduceDifferentPngs.
.DESCRIPTION
    Заменяет yaw 90° на 37° (не кратный 90°) в тесте рендерера.
    Причина: куб имеет 90° симметрию вокруг Y, поэтому 0° и 90° дают
    байт-в-байт идентичные PNG. Рендерер корректен, тест — нет.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.2a'
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

$readme = @'
# Патч 0.2.2a — фикс теста симметрии куба

**Итерация:** 0.2 · **Статус:** реализован

## Причина

Тест `Render_DifferentAngles_ProduceDifferentPngs` сравнивал yaw 0° и 90° на кубе.
Куб имеет 90° симметрию вокруг Y — при повороте на 90° грани переставляются, и с
фиксированным светом итоговое изображение **байт-в-байт идентично**. Рендерер
корректен, тест содержал неверное предположение.

## Что делает

- Заменяет `90f` на `37f` в вызове второго `Render` (yaw). 37° не кратен 90° → картинка другая.
- Добавляет комментарий-объяснение в тест.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.2a\patch_0.2.2a.ps1"

## DoD

- `dotnet test` — 24 теста, 0 сбоев.
'@

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.2.2a\README.md'

    $targetPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\Render\PreviewRendererTests.cs'
    Backup-File $targetPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $content = [IO.File]::ReadAllText($targetPath, [Text.Encoding]::UTF8)

    # Заменяем блок Render_DifferentAngles_ProduceDifferentPngs
    $oldBlock = '    [Fact]' + [Environment]::NewLine +
                '    public void Render_DifferentAngles_ProduceDifferentPngs()' + [Environment]::NewLine +
                '    {' + [Environment]::NewLine +
                '        var renderer = new SkiaPreviewRenderer();' + [Environment]::NewLine +
                '        var a = renderer.Render(Cube(), 64, 64, 0f, 15f);' + [Environment]::NewLine +
                '        var b = renderer.Render(Cube(), 64, 64, 90f, 15f);' + [Environment]::NewLine +
                '        Assert.NotEqual(a, b);' + [Environment]::NewLine +
                '    }'

    $newBlock = '    [Fact]' + [Environment]::NewLine +
                '    public void Render_DifferentAngles_ProduceDifferentPngs()' + [Environment]::NewLine +
                '    {' + [Environment]::NewLine +
                '        // Куб имеет 90° симметрию вокруг Y — при фиксированном свете yaw 0° и 90°' + [Environment]::NewLine +
                '        // дают байт-в-байт идентичный PNG. Берём 37° (не кратный 90°),' + [Environment]::NewLine +
                '        // чтобы проверить, что yaw вообще влияет на рендер.' + [Environment]::NewLine +
                '        var renderer = new SkiaPreviewRenderer();' + [Environment]::NewLine +
                '        var a = renderer.Render(Cube(), 64, 64, 0f, 15f);' + [Environment]::NewLine +
                '        var b = renderer.Render(Cube(), 64, 64, 37f, 15f);' + [Environment]::NewLine +
                '        Assert.NotEqual(a, b);' + [Environment]::NewLine +
                '    }'

    # Нормализуем line endings для сравнения
    $normalized = $content -replace "`r`n", "`n"
    $oldNorm = $oldBlock -replace "`r`n", "`n"
    $newNorm = $newBlock -replace "`r`n", "`n"

    if ($normalized.Contains($oldNorm)) {
        $newContent = $normalized.Replace($oldNorm, $newNorm)
        Write-Text -Path $targetPath -Content $newContent
        Write-Log 'updated: src\MiniCodex.Tests\Render\PreviewRendererTests.cs (yaw 90f → 37f)'
    }
    elseif ($normalized -match 'renderer\.Render\(Cube\(\), 64, 64, 37f, 15f\)') {
        Write-Log 'PreviewRendererTests.cs: уже содержит 37f, пропускаю.' 'WARN'
    }
    else {
        # Fallback: точечная замена в конкретном контексте
        $content2 = [IO.File]::ReadAllText($targetPath, [Text.Encoding]::UTF8)
        $content2 = $content2 -replace 'var b = renderer\.Render\(Cube\(\), 64, 64, 90f, 15f\);',
                                       'var b = renderer.Render(Cube(), 64, 64, 37f, 15f);'
        Write-Text -Path $targetPath -Content $content2
        Write-Log 'updated: PreviewRendererTests.cs (fallback regex)'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.2a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.2a: тест Render_DifferentAngles_ProduceDifferentPngs использует yaw 37° вместо 90° (куб имеет 90°-симметрию).`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.2\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.2a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}