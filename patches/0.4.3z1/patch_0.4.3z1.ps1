#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3z1 - Cleanup warnings + clip images to rounded corners.
.DESCRIPTION
    1. ThreeDViewer: remove unused _suppressPropSync field and its try/finally.
    2. AppServices: guard WindowsRegistryProbe with OperatingSystem.IsWindows() (CA1416).
    3. ModelCardView.axaml: wrap Image in inner Border (CornerRadius 6, ClipToBounds) so it clips to rounded corners.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3z1'
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
    Write-Log "Backup: $rel"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $viewerPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'
    $appSvcPath = Join-Path $ProjectRoot 'src\MiniCodex.App\AppServices.cs'
    $xamlPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'

    Backup-File $viewerPath
    Backup-File $appSvcPath
    Backup-File $xamlPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # --- 1. ThreeDViewer: remove _suppressPropSync ---
    $viewer = [IO.File]::ReadAllText($viewerPath, [Text.Encoding]::UTF8)
    if ($viewer -match '_suppressPropSync') {
        $viewer = $viewer -replace '    private bool _suppressPropSync;\r?\n', ''
        $viewer = $viewer -replace '(\r?\n)(\s*)_suppressPropSync = true;\r?\n\s*try\r?\n\s*\{\r?\n\s*SetCurrentValue\(YawProperty, _yaw\);\r?\n\s*SetCurrentValue\(PitchProperty, _pitch\);\r?\n\s*\}\r?\n\s*finally \{ _suppressPropSync = false; \}', '$1$2SetCurrentValue(YawProperty, _yaw);$1$2SetCurrentValue(PitchProperty, _pitch);'
        [IO.File]::WriteAllText($viewerPath, $viewer, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ThreeDViewer.axaml.cs (removed _suppressPropSync)'
    } else {
        Write-Log 'ThreeDViewer.axaml.cs: _suppressPropSync not found, skipping.' 'WARN'
    }

    # --- 2. AppServices: guard WindowsRegistryProbe ---
    $appSvc = [IO.File]::ReadAllText($appSvcPath, [Text.Encoding]::UTF8)
    if ($appSvc -match 'new WindowsRegistryProbe\(\)' -and ($appSvc -notmatch 'OperatingSystem\.IsWindows\(\)')) {
        $oldLine = '        var probe = new WindowsRegistryProbe();' + "`r`n" +
                   '        IntegrationService = new IntegrationService(probe, Settings);'
        $newLine = '        if (OperatingSystem.IsWindows())' + "`r`n" +
                   '        {' + "`r`n" +
                   '            var probe = new WindowsRegistryProbe();' + "`r`n" +
                   '            IntegrationService = new IntegrationService(probe, Settings);' + "`r`n" +
                   '        }' + "`r`n" +
                   '        else' + "`r`n" +
                   '        {' + "`r`n" +
                   '            IntegrationService = new IntegrationService(new NoopIntegrationProbe(), Settings);' + "`r`n" +
                   '        }'
        if ($appSvc.Contains($oldLine)) {
            $appSvc = $appSvc.Replace($oldLine, $newLine)
            # Add NoopIntegrationProbe class at end (before closing brace of namespace)
            if ($appSvc -notmatch 'class NoopIntegrationProbe') {
                $probeClass = "`r`n" + 'internal sealed class NoopIntegrationProbe : IIntegrationProbe' + "`r`n" +
                              '{' + "`r`n" +
                              '    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)' + "`r`n" +
                              '        => Task.FromResult<IReadOnlyDictionary<string, string>>(new Dictionary<string, string>());' + "`r`n" +
                              '}' + "`r`n"
                $lastBrace = $appSvc.LastIndexOf('}')
                $appSvc = $appSvc.Substring(0, $lastBrace) + $probeClass + $appSvc.Substring($lastBrace)
            }
            [IO.File]::WriteAllText($appSvcPath, $appSvc, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: AppServices.cs (OS guard for WindowsRegistryProbe + NoopIntegrationProbe)'
        } else {
            Write-Log 'AppServices.cs: exact probe block not found, checking manually.' 'WARN'
        }
    } elseif ($appSvc -match 'OperatingSystem\.IsWindows\(\)') {
        Write-Log 'AppServices.cs: already guarded, skipping.' 'WARN'
    }

    # --- 3. XAML: wrap Image in inner Border with rounded corners ---
    $xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
    $oldImgRef = '<Image Source="{Binding Thumbnail}" Stretch="Uniform"/>'
    $newImgRef = '<Border CornerRadius="6" ClipToBounds="True">' + "`r`n" +
                 '                                                                            <Image Source="{Binding Thumbnail}" Stretch="Uniform"/>' + "`r`n" +
                 '                                                                        </Border>'
    if ($xaml.Contains($oldImgRef) -and ($xaml -notmatch 'CornerRadius="6" ClipToBounds="True">\s*<Image')) {
        $xaml = $xaml.Replace($oldImgRef, $newImgRef)
        [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ModelCardView.axaml (images clipped to rounded corners)'
    } elseif ($xaml -match 'CornerRadius="6" ClipToBounds="True">\s*\r?\n\s*<Image') {
        Write-Log 'ModelCardView.axaml: image clip already in place, skipping.' 'WARN'
    } else {
        Write-Log 'ModelCardView.axaml: Image tag not found for clip wrap, checking manually.' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.3z1 - Cleanup warnings + image clip

**Iteration:** 0.4

## What it does

1. ThreeDViewer.axaml.cs: removed unused _suppressPropSync field + try/finally.
2. AppServices.cs: OS guard for WindowsRegistryProbe (CA1416).
   Added NoopIntegrationProbe for non-Windows.
3. ModelCardView.axaml: Image inside item tile wrapped in inner Border (CornerRadius 6, ClipToBounds)
   so thumbnails clip to rounded corners of the outer tile.

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Reference / Photo tiles have rounded image corners.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.3z1\README.md'

    # CHANGELOG
    $marker = '<!-- patch 0.4.3z1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3z1] - 2026-11-12`r`n`r`n### Changed`r`n- Cleanup: removed unused _suppressPropSync.`r`n- Cleanup: OS guard for WindowsRegistryProbe + NoopIntegrationProbe.`r`n- Image thumbnails clipped to rounded corners.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.3g\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}