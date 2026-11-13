#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.0b.1 — фикс XAML: xmlns:vm на корневом элементе.
.DESCRIPTION
    В 0.3.0b xmlns:vm был объявлен внутри RadioButton — компилятор Avalonia
    не допускает xmlns не на корне. Переписываем ModelCardView.axaml корректно.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.0b.1'
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

# ============ ModelCardView.axaml (полная замена) ============
# xmlns:vm перенесён на <UserControl>, внутри RadioButton — без xmlns.
# ComboBox для radio — без $parent[UserControl] хака: используем обычный биндинг через DataContext.
$axaml = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
        </StackPanel>

        <Grid Grid.Row="1" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0" MeshFilePath="{Binding MeshFilePath}" Margin="0,0,8,0"/>

            <TabControl Grid.Column="1" SelectedIndex="{Binding SelectedTabIndex}">
                <TabItem Header="{Binding TabInfoHeader}">
                    <ScrollViewer>
                        <StackPanel Margin="8" Spacing="6">
                            <TextBlock Text="{Binding LabelTitle}"/>
                            <TextBox Text="{Binding Title}"/>
                            <TextBlock Text="{Binding LabelAuthor}"/>
                            <TextBox Text="{Binding Author}"/>
                            <TextBlock Text="{Binding LabelSourceUrl}"/>
                            <TextBox Text="{Binding SourceUrl}"/>
                            <TextBlock Text="{Binding LabelStatus}"/>
                            <TextBox Text="{Binding Status}"/>
                            <TextBlock Text="{Binding LabelDifficulty}"/>
                            <TextBox Text="{Binding Difficulty}"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="{Binding TabFilesHeader}">
                    <ListBox ItemsSource="{Binding FileRows}">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid ColumnDefinitions="Auto,*,Auto,Auto,Auto" Margin="4">
                                    <RadioButton Grid.Column="0"
                                                 IsChecked="{Binding IsPrimary, Mode=OneWay}"
                                                 Command="{Binding $parent[ListBox].((vm:ModelCardPageViewModel)DataContext).SetPrimaryCommand}"
                                                 CommandParameter="{Binding}"
                                                 GroupName="PrimaryFile"/>
                                    <TextBlock Grid.Column="1" Text="{Binding DisplayName}"
                                               VerticalAlignment="Center" Margin="6,0"/>
                                    <TextBlock Grid.Column="2" Text="{Binding RoleText}"
                                               VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="3" Text="{Binding SizeText}"
                                               VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="4" Text="{Binding PolygonsText}"
                                               VerticalAlignment="Center" Width="80"/>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </TabItem>

                <TabItem Header="{Binding TabAssociationsHeader}">
                    <TextBlock Text="{Binding AssociationsPlaceholder}"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="{Binding TabTagsHeader}">
                    <TextBlock Text="{Binding TagsPlaceholder}"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="{Binding TabNotesHeader}">
                    <TextBox Text="{Binding Notes}" AcceptsReturn="True"
                             TextWrapping="Wrap" VerticalContentAlignment="Top"
                             Margin="8" MinHeight="200"/>
                </TabItem>
            </TabControl>
        </Grid>
    </Grid>
</UserControl>
'@

$readme = @'
# Патч 0.3.0b.1 — фикс XAML карточки модели

**Итерация:** 0.3 · **Статус:** реализован

## Причина

В 0.3.0b `xmlns:vm` был объявлен внутри `<RadioButton>` в `ModelCardView.axaml`.
Компилятор Avalonia требует, чтобы все `xmlns`-декларации были только на корневом
элементе (`AXN0002`). Вторичная ошибка — `InitializeComponent не существует` —
следствие: XAML не скомпилировался, поэтому generated-класс `ModelCardView.g.cs` не создался.

## Что делает

- `xmlns:vm` перенесён на корневой `<UserControl>`.
- Добавлен `x:DataType="vm:ModelCardPageViewModel"` — для compiled bindings.
- `$parent[UserControl]` заменён на `$parent[ListBox]` в Command-binding
  (надёжнее и явнее — RadioButton находится внутри ListBox.ItemTemplate).
- Логика не менялась.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0b.1\patch_0.3.0b.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- UI карточки работает как в 0.3.0b: drag вправо = модель вправо, язык переключается.
'@

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $targetPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    Backup-File $targetPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.3.0b.1\README.md'

    Write-Text -Path $targetPath -Content $axaml
    Write-Log 'updated: src\MiniCodex.App\Views\ModelCardView.axaml (xmlns:vm на корне, x:DataType, ListBox parent)'

    # CHANGELOG
    $marker = '<!-- patch 0.3.0b.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.3.0b.1: ModelCardView.axaml — xmlns:vm перенесён на корневой элемент (AXN0002).`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.0b\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.0b.1.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}