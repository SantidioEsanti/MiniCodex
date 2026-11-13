#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.1.0a — добавление иконки приложения.
.DESCRIPTION
    Внедряет иконку в csproj и MainWindow.axaml.
    Идемпотентен: повторный запуск не дублирует теги. Делает бэкап.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.1.0a'
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

# --- 1. Чтение README -------------------------------------------------------
$readme = @'
# Патч 0.1.0a — Добавление иконки приложения

**Итерация:** 0.1 (Фундамент)
**Статус:** реализован

## Что делает

- Добавляет `<ApplicationIcon>Assets\icon.ico</ApplicationIcon>` в `MiniCodex.App.csproj`.
- Добавляет `<AvaloniaResource Include="Assets\**" />` в `MiniCodex.App.csproj`, чтобы файлы иконок попадали в сборку.
- Добавляет атрибут `Icon="/Assets/icon.ico"` в тег `<Window>` в `MainWindow.axaml`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.0a\patch_0.1.0a.ps1"

## Откат

Скопировать файлы из `backups\0.1.0a_{timestamp}\` обратно в `D:\AI\MiniCodex\`.
'@

$readmePath = Join-Path $PatchDir 'README.md'
[IO.File]::WriteAllText($readmePath, $readme, [Text.UTF8Encoding]::new($false))
Write-Log 'created: patches\0.1.0a\README.md'

# --- Основной сценарий -------------------------------------------------------
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    # Бэкапим целевые файлы
    $csprojPath  = Join-Path $ProjectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
    $axamlPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\MainWindow.axaml'
    $changelog   = Join-Path $ProjectRoot 'CHANGELOG.md'
    
    Backup-File $csprojPath
    Backup-File $axamlPath
    Backup-File $changelog

    # --- Модификация csproj ---
    $csproj = [IO.File]::ReadAllText($csprojPath, [Text.Encoding]::UTF8)
    $updatedCsproj = $false

    if ($csproj -notmatch '<ApplicationIcon>') {
        $csproj = $csproj -replace '(<TargetFramework>net8\.0</TargetFramework>)', "`$1`r`n    <ApplicationIcon>Assets\icon.ico</ApplicationIcon>"
        $updatedCsproj = $true
        Write-Log 'csproj: добавлен <ApplicationIcon>'
    }

    if ($csproj -notmatch '<AvaloniaResource Include="Assets\\\*\*"') {
        $csproj = $csproj -replace '</Project>', "  <ItemGroup>`r`n    <AvaloniaResource Include=`"Assets\**`" />`r`n  </ItemGroup>`r`n</Project>"
        $updatedCsproj = $true
        Write-Log 'csproj: добавлен <AvaloniaResource Include="Assets\**" />'
    }

    if ($updatedCsproj) {
        [IO.File]::WriteAllText($csprojPath, $csproj, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.App\MiniCodex.App.csproj'
    } else {
        Write-Log 'csproj: иконка уже подключена, пропускаю.' 'WARN'
    }

    # --- Модификация MainWindow.axaml ---
    $axaml = [IO.File]::ReadAllText($axamlPath, [Text.Encoding]::UTF8)
    if ($axaml -notmatch 'Icon="/Assets/icon.ico"') {
        $axaml = $axaml -replace '(Title="\{Binding Title\}")', '$1 Icon="/Assets/icon.ico"'
        [IO.File]::WriteAllText($axamlPath, $axaml, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: src\MiniCodex.App\Views\MainWindow.axaml (добавлен Icon)'
    } else {
        Write-Log 'axaml: Icon уже установлен, пропускаю.' 'WARN'
    }

    # --- CHANGELOG ---
    $marker = '<!-- patch 0.1.0a applied -->'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.1.0a] - 2026-11-10`n`n### Added`n- Иконка приложения (Assets/icon.ico, Assets/Icon.png).`n- Атрибут Icon в MainWindow.`n"
            $cl = $cl -replace '(?m)^(## \[0\.1\.0\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.1.0a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    Write-Log "Восстановление: скопируйте файлы из '$BackupDir' обратно в '$ProjectRoot'." 'ERROR'
    exit 1
}