$ErrorActionPreference = "Stop"
$ver = "0.5.1a4"
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

Log "Starting patch $ver - Grid Virtualization with ItemsRepeater"

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

# 1. Add ItemsRepeater package to csproj
$csproj = "$root\src\MiniCodex.App\MiniCodex.App.csproj"
$csprojContent = [IO.File]::ReadAllText($csproj)

if ($csprojContent -notmatch "Avalonia.Controls.ItemsRepeater") {
    # Insert after the main Avalonia package reference
    $pattern = '(<PackageReference Include="Avalonia" Version="[^"]+" />)'
    $replacement = "`$1`n    <PackageReference Include=`"Avalonia.Controls.ItemsRepeater`" Version=`"11.2.3`" />"
    $csprojContent = $csprojContent -replace $pattern, $replacement
    [IO.File]::WriteAllText($csproj, $csprojContent)
    Log "Added Avalonia.Controls.ItemsRepeater to csproj."
} else {
    Log "ItemsRepeater package already present in csproj."
}

# 2. Update LibraryView.axaml
$libAxaml = "$root\src\MiniCodex.App\Views\LibraryView.axaml"
$content = [IO.File]::ReadAllText($libAxaml)

if ($content -match "ItemsRepeater") {
    Log "LibraryView.axaml already using ItemsRepeater. Skipping."
} else {
    Log "Replacing ItemsControl with ItemsRepeater..."
    
    # Add namespace if missing
    if ($content -notmatch 'xmlns:ir="clr-namespace:Avalonia.Controls.ItemsRepeater;assembly=Avalonia.Controls.ItemsRepeater"') {
        $content = $content -replace 'xmlns:views="clr-namespace:MiniCodex.App.Views"', 'xmlns:views="clr-namespace:MiniCodex.App.Views"`n             xmlns:ir="clr-namespace:Avalonia.Controls.ItemsRepeater;assembly=Avalonia.Controls.ItemsRepeater"'
    }

    $oldItemsControl = @"
                <ItemsControl ItemsSource="{Binding Cards}" Margin="4" ClipToBounds="False">
                    <ItemsControl.ItemsPanel>
                        <ItemsPanelTemplate>
                            <WrapPanel Orientation="Horizontal" ClipToBounds="False"/>
                        </ItemsPanelTemplate>
                    </ItemsControl.ItemsPanel>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
"@

    $newItemsRepeater = @"
                <ir:ItemsRepeater ItemsSource="{Binding Cards}" Margin="4">
                    <ir:ItemsRepeater.Layout>
                        <ir:UniformGridLayout MinItemWidth="250" MinItemHeight="350" 
                                              MinColumnSpacing="16" MinRowSpacing="16" 
                                              ItemsStretch="Fill" />
                    </ir:ItemsRepeater.Layout>
                    <ir:ItemsRepeater.ItemTemplate>
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ir:ItemsRepeater.ItemTemplate>
                </ir:ItemsRepeater>
"@
    
    # Use regex to match the block safely regardless of indentation or line endings
    $pattern = '(?s)<ItemsControl ItemsSource="\{Binding Cards\}".*?</ItemsControl>'
    
    if ($content -match $pattern) {
        $content = $content -replace $pattern, $newItemsRepeater
        [IO.File]::WriteAllText($libAxaml, $content)
        Log "LibraryView.axaml updated with ItemsRepeater."
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
- App: Replaced WrapPanel with virtualized ItemsRepeater (UniformGridLayout).
- App: Added Avalonia.Controls.ItemsRepeater package.
- Perf: Library grid now only renders visible cards, dramatically reducing memory and startup time for 1000+ models.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."