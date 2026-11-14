$ErrorActionPreference = "Stop"
$ver = "0.5.0a2"
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

Log "Starting patch $ver - Apply Soft Glass tokens to Cards [v2]"

$files = @(
    "$root\src\MiniCodex.App\Views\ModelCardTile.axaml",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Patch ModelCardTile.axaml
$cardAxaml = "$root\src\MiniCodex.App\Views\ModelCardTile.axaml"
$content = [IO.File]::ReadAllText($cardAxaml)

if ($content -match "patch 0.5.0a2 applied") {
    Log "ModelCardTile.axaml already patched. Skipping."
} else {
    Log "Patching ModelCardTile.axaml safely..."
    
    # Find the first <Border tag in the file
    $borderIndex = $content.IndexOf("<Border")
    
    if ($borderIndex -ge 0) {
        # Find the end of the opening tag
        $endTagIndex = $content.IndexOf(">", $borderIndex)
        
        if ($endTagIndex -gt $borderIndex) {
            $tagContent = $content.Substring($borderIndex, $endTagIndex - $borderIndex + 1)
            $newTagContent = $tagContent
            
            # Replace Background if it's hardcoded hex
            $newTagContent = $newTagContent -replace 'Background="#[A-Fa-f0-9]{6,8}"', 'Background="{DynamicResource CardBackgroundBrush}"'
            
            # Replace CornerRadius
            if ($newTagContent -match 'CornerRadius="[^"]+"') {
                $newTagContent = $newTagContent -replace 'CornerRadius="[^"]+"', 'CornerRadius="{DynamicResource CornerRadiusLarge}"'
            } else {
                $newTagContent = $newTagContent -replace '>$', ' CornerRadius="{DynamicResource CornerRadiusLarge}">'
            }
            
            # Add BoxShadow if not present
            if ($newTagContent -notmatch 'BoxShadow=') {
                $newTagContent = $newTagContent -replace '>$', ' BoxShadow="{DynamicResource CardShadow}">'
            }
            
            # Replace in the main content
            $content = $content.Substring(0, $borderIndex) + $newTagContent + $content.Substring($endTagIndex + 1)
            
            # Add patch marker after UserControl opening tag
            $content = $content -replace '(<UserControl[^>]*>)', "`$1`n    <!-- patch 0.5.0a2 applied -->"
            
            [IO.File]::WriteAllText($cardAxaml, $content)
            Log "ModelCardTile.axaml updated successfully."
        } else {
            Log "ERROR: Could not find closing bracket '>' for the first Border tag."
        }
    } else {
        Log "ERROR: Could not find any <Border> tag in ModelCardTile.axaml."
    }
}

# 2. Generate README.md
$readme = "$patchDir\README.md"
$readmeContent = @"
# Patch 0.5.0a2 - Apply Soft Glass tokens to Cards (v2)

## What
Replaces hardcoded visual properties in ModelCardTile.axaml with the dynamic resources introduced in 0.5.0a1. Targets only the first Border element.

## Why
To achieve the soft, floating card look without breaking nested property elements (like Border.Background).

## Files affected
- src/MiniCodex.App/Views/ModelCardTile.axaml
- CHANGELOG.md
"@
[IO.File]::WriteAllText($readme, $readmeContent, [Text.Encoding]::UTF8)
Log "README.md created."

# 3. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch 0.5.0a2 applied") {
    $entry = @"

## 0.5.0a2
- UI: Applied Soft Glass tokens (shadows, radii, background) to ModelCardTile.
<!-- patch 0.5.0a2 applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."