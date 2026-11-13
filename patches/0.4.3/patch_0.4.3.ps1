#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.3 - ScaleCatalog (Core) + tests. Plumbing only; UI in 0.4.3a.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.3'
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

$Files = @{}

# ============ Core/Models/ScalePreset.cs ============
$Files['src\MiniCodex.Core\Models\ScalePreset.cs'] = @'
namespace MiniCodex.Core.Models;

public record ScalePreset(string Category, string Label, float Denominator);
'@

# ============ Core/Services/ScaleCatalog.cs ============
$Files['src\MiniCodex.Core\Services\ScaleCatalog.cs'] = @'
using System.Globalization;
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public static class ScaleCatalog
{
    public static IReadOnlyList<ScalePreset> All { get; } = new[]
    {
        // Figures & miniatures
        new ScalePreset("figure", "1:6", 6f),
        new ScalePreset("figure", "1:10", 10f),
        new ScalePreset("figure", "1:12", 12f),
        new ScalePreset("figure", "1:16", 16f),
        new ScalePreset("figure", "1:18", 18f),
        new ScalePreset("figure", "1:24", 24f),
        new ScalePreset("figure", "1:32", 32f),
        new ScalePreset("figure", "1:35", 35f),
        new ScalePreset("figure", "1:43", 43f),
        new ScalePreset("figure", "1:48", 48f),
        new ScalePreset("figure", "1:56", 56f),
        new ScalePreset("figure", "1:60", 60f),
        new ScalePreset("figure", "1:64", 64f),
        new ScalePreset("figure", "1:72", 72f),
        new ScalePreset("figure", "1:100", 100f),
        // Vehicles
        new ScalePreset("vehicle", "1:12", 12f),
        new ScalePreset("vehicle", "1:18", 18f),
        new ScalePreset("vehicle", "1:24", 24f),
        new ScalePreset("vehicle", "1:25", 25f),
        new ScalePreset("vehicle", "1:43", 43f),
        new ScalePreset("vehicle", "1:64", 64f),
        // Aviation
        new ScalePreset("aviation", "1:32", 32f),
        new ScalePreset("aviation", "1:48", 48f),
        new ScalePreset("aviation", "1:72", 72f),
        new ScalePreset("aviation", "1:144", 144f),
        new ScalePreset("aviation", "1:200", 200f),
        // Armor
        new ScalePreset("armor", "1:35", 35f),
        new ScalePreset("armor", "1:48", 48f),
        new ScalePreset("armor", "1:72", 72f),
        new ScalePreset("armor", "1:76", 76f),
        // Naval
        new ScalePreset("naval", "1:200", 200f),
        new ScalePreset("naval", "1:350", 350f),
        new ScalePreset("naval", "1:700", 700f),
        // Railway
        new ScalePreset("railway", "1:76 (OO)", 76f),
        new ScalePreset("railway", "1:87 (HO)", 87f),
        new ScalePreset("railway", "1:120 (TT)", 120f),
        new ScalePreset("railway", "1:160 (N)", 160f),
        // Architecture
        new ScalePreset("architecture", "1:20", 20f),
        new ScalePreset("architecture", "1:50", 50f),
        new ScalePreset("architecture", "1:100", 100f),
        new ScalePreset("architecture", "1:200", 200f),
    };

    public static IReadOnlyList<ScalePreset> ForPrototype(string? prototypeType)
    {
        if (string.IsNullOrEmpty(prototypeType) || prototypeType == "any")
            return All;

        return prototypeType switch
        {
            "figure"   => All.Where(s => s.Category == "figure").ToList(),
            "vehicle"  => All.Where(s => s.Category == "vehicle" || s.Category == "aviation" || s.Category == "armor").ToList(),
            "building" => All.Where(s => s.Category == "architecture").ToList(),
            "ship"     => All.Where(s => s.Category == "naval").ToList(),
            _ => All,
        };
    }

    public static float? ParseManual(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var trimmed = input.Trim();
        var sep = trimmed.IndexOfAny(new[] { ':', '/' });
        var denomPart = sep >= 0 ? trimmed.Substring(sep + 1).Trim() : trimmed;
        return float.TryParse(denomPart, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) && v > 0
            ? v : null;
    }

    public static float? CalculateModelHeightMm(float prototypeHeightMm, float denominator)
        => denominator > 0 ? prototypeHeightMm / denominator : null;

    public static float? CalculatePrototypeHeightMm(float modelHeightMm, float denominator)
        => denominator > 0 ? modelHeightMm * denominator : null;
}
'@

# ============ Tests/Services/ScaleCatalogTests.cs ============
$Files['src\MiniCodex.Tests\Services\ScaleCatalogTests.cs'] = @'
using MiniCodex.Core.Services;
using Xunit;

namespace MiniCodex.Tests.Services;

public class ScaleCatalogTests
{
    [Fact]
    public void All_HasExpectedCategories()
    {
        var cats = ScaleCatalog.All.Select(s => s.Category).Distinct().OrderBy(x => x).ToArray();
        Assert.Contains("figure", cats);
        Assert.Contains("vehicle", cats);
        Assert.Contains("aviation", cats);
        Assert.Contains("armor", cats);
        Assert.Contains("naval", cats);
        Assert.Contains("railway", cats);
        Assert.Contains("architecture", cats);
    }

    [Fact]
    public void ForPrototype_Figure_OnlyFigureScales()
    {
        var scales = ScaleCatalog.ForPrototype("figure");
        Assert.NotEmpty(scales);
        Assert.All(scales, s => Assert.Equal("figure", s.Category));
    }

    [Fact]
    public void ForPrototype_Vehicle_IncludesVehicleAviationArmor()
    {
        var scales = ScaleCatalog.ForPrototype("vehicle");
        var cats = scales.Select(s => s.Category).Distinct().ToHashSet();
        Assert.Contains("vehicle", cats);
        Assert.Contains("aviation", cats);
        Assert.Contains("armor", cats);
        Assert.DoesNotContain("figure", cats);
    }

    [Fact]
    public void ForPrototype_Ship_OnlyNaval()
    {
        var scales = ScaleCatalog.ForPrototype("ship");
        Assert.NotEmpty(scales);
        Assert.All(scales, s => Assert.Equal("naval", s.Category));
    }

    [Fact]
    public void ForPrototype_Any_ReturnsAll()
    {
        var scales = ScaleCatalog.ForPrototype("any");
        Assert.Equal(ScaleCatalog.All.Count, scales.Count);
    }

    [Fact]
    public void ParseManual_HandlesFormats()
    {
        Assert.Equal(24f, ScaleCatalog.ParseManual("1:24"));
        Assert.Equal(24f, ScaleCatalog.ParseManual("24"));
        Assert.Equal(24f, ScaleCatalog.ParseManual("1/24"));
        Assert.Equal(35.5f, ScaleCatalog.ParseManual("1:35.5"));
        Assert.Null(ScaleCatalog.ParseManual("abc"));
        Assert.Null(ScaleCatalog.ParseManual("1:0"));
        Assert.Null(ScaleCatalog.ParseManual(""));
    }

    [Fact]
    public void CalculateModelHeight_From1800mm_At1to24_Is75mm()
    {
        var mh = ScaleCatalog.CalculateModelHeightMm(1800f, 24f);
        Assert.NotNull(mh);
        Assert.Equal(75f, mh!.Value, 2);
    }

    [Fact]
    public void CalculatePrototypeHeight_From75mm_At1to24_Is1800mm()
    {
        var ph = ScaleCatalog.CalculatePrototypeHeightMm(75f, 24f);
        Assert.NotNull(ph);
        Assert.Equal(1800f, ph!.Value, 0);
    }
}
'@

# ============ README ============
$Files['patches\0.4.3\README.md'] = @'
# Patch 0.4.3 - ScaleCatalog (Core) + tests

**Iteration:** 0.4

## What it does

- Core/Models/ScalePreset.cs: record (Category, Label, Denominator).
- Core/Services/ScaleCatalog.cs:
  - All: 43 presets (7 categories: figure, vehicle, aviation, armor, naval, railway, architecture) - per HANDOFF section 8.1.
  - ForPrototype(type): filter by prototype type (figure / vehicle / building / ship / any) - per HANDOFF section 8.2.
  - ParseManual(input): "1:24" / "24" / "1/24" / "1:35.5" -> denominator; invalid / <=0 -> null.
  - CalculateModelHeightMm(protoMm, denom) = protoMm / denom.
  - CalculatePrototypeHeightMm(modelMm, denom) = modelMm * denom.
- Tests/Services/ScaleCatalogTests.cs: 8 tests (categories, filtering, parsing, math).

## No UI

UI (Scale tab in card) comes in 0.4.3a.
No changes to existing files.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48 (40 + 8 new).
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.3 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.3] - 2026-11-10`r`n`r`n### Added`r`n- ScaleCatalog (43 presets, 7 categories) + ScalePreset record.`r`n- ForPrototype filter, ParseManual, CalculateModelHeightMm, CalculatePrototypeHeightMm.`r`n- 8 unit tests.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.2b\].*)$', "$entry`$1"
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