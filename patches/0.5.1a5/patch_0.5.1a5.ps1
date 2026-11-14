$ErrorActionPreference = "Stop"
$ver = "0.5.1a5"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Grid Virtualization (fixed version and XAML)"

$files = @(
    "$root\src\MiniCodex.App\MiniCodex.App.csproj",
    "$root\src\MiniCodex.App\Views\LibraryView.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Add ItemsRepeater package (version 11.1.5)
$csproj = "$root\src\MiniCodex.App\MiniCodex.App.csproj"
$csprojContent = [IO.File]::ReadAllText($csproj)

if ($csprojContent -notmatch "Avalonia.Controls.ItemsRepeater") {
    $pattern = '(<PackageReference Include="Avalonia" Version="[^"]+" />)'
    $replacement = "`$1`n    <PackageReference Include=`"Avalonia.Controls.ItemsRepeater`" Version=`"11.1.5`" />"
    $csprojContent = $csprojContent -replace $pattern, $replacement
    [IO.File]::WriteAllText($csproj, $csprojContent)
    Log "Added Avalonia.Controls.ItemsRepeater 11.1.5 to csproj."
} else {
    Log "ItemsRepeater package already present."
}

# 2. Update LibraryView.axaml (replace ItemsControl with ItemsRepeater, no prefix)
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$content = [IO.File]::ReadAllText($libAxaml)

if ($content -match "ItemsRepeater") {
    Log "LibraryView.axaml already contains ItemsRepeater. Skipping replacement."
} else {
    Log "Replacing ItemsControl with ItemsRepeater..."

    $newItemsRepeater = @"
                <ItemsRepeater ItemsSource="{Binding Cards}" Margin="4">
                    <ItemsRepeater.Layout>
                        <UniformGridLayout MinItemWidth="250" MinItemHeight="350" 
                                           MinColumnSpacing="16" MinRowSpacing="16" 
                                           ItemsStretch="Fill" />
                    </ItemsRepeater.Layout>
                    <ItemsRepeater.ItemTemplate>
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ItemsRepeater.ItemTemplate>
                </ItemsRepeater>
"@

    $pattern = '(?s)<ItemsControl ItemsSource="\{Binding Cards\}".*?</ItemsControl>'

    if ($content -match $pattern) {
        $content = $content -replace $pattern, $newItemsRepeater
        [IO.File]::WriteAllText($libAxaml, $content)
        Log "LibraryView.axaml updated with ItemsRepeater (no prefix)."
    } else {
        Log "ERROR: Could not find ItemsControl block in LibraryView.axaml"
    }
}

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- App: Fixed ItemsRepeater package version to 11.1.5 and corrected XAML namespace.
- Perf: Library grid now uses virtualized ItemsRepeater with UniformGridLayout.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."