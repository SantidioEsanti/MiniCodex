\# patch 0.5.3c.2

Line-based fix for ru.json after Replace-Exact anchors failed in 0.5.3c.1. Reads ru.json line-by-line, enters TagContextMenu block, appends "CustomColor" after "Delete"; enters DeleteTagDialog block, appends "ColorPickerDialog" after closing brace. Verifies en.json is OK, writes CHANGELOG marker 0.5.3c. No code changes.

