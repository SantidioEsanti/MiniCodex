# Changelog

## [0.1.2] - 2026-11-14

### Added
- **Smart Collections**: Save current search + tag filter as a named collection in the sidebar. 
- **Tag Management**: Right-click tag menu with Rename, Delete, and Clear Color. 
- **Tag Colors**: 8 preset palette swatches + custom HEX color picker dialog with live preview. 
- **Keyboard UX**: Enter (Save) and Esc (Cancel) now work in all modal dialogs. 
- **MeshNormalSmoother**: Spatial deduplication for 3D-scanned STLs (fixes layer lines). 
- **Duplicate Detection**: Find models with identical SHA-256 file hashes (toolbar button). 
- **Single-Instance Lock**: Named Mutex prevents multiple instances from corrupting SQLite. 

### Fixed
- **UI Stability**: Reverted to ItemsControl + WrapPanel (Avalonia 11.1.5 ItemsRepeater was causing invisible cards). 
- **Context Menus**: Right-click on tags now works on the full row, not just the text. 
- **Localization**: Fixed indents and missing keys in `en.json` / `ru.json`. 

### Changed
- Redesigned UI using "Soft Glass" concept (rounded corners, soft shadows, gradients). 

---

\# Changelog



Р В¤Р С•РЎР‚Р СР В°РЎвЂљ РІР‚вЂќ \[Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

Р вЂ™Р ВµРЎР‚РЎРѓР С‘Р С•Р Р…Р С‘РЎР‚Р С•Р Р†Р В°Р Р…Р С‘Р Вµ РІР‚вЂќ \[SemVer](https://semver.org/lang/ru/), pre-release Р Т‘Р С• v1.0.0.



\## \[Unreleased]



\### Added

\- Р вЂР В°Р В·Р С•Р Р†Р В°РЎРЏ РЎРѓРЎвЂљРЎР‚РЎС“Р С”РЎвЂљРЎС“РЎР‚Р В° РЎР‚Р ВµР С—Р С•Р В·Р С‘РЎвЂљР С•РЎР‚Р С‘РЎРЏ (docs, lang, patches, src, .github).

\- `docs/ROADMAP.md` РІР‚вЂќ Р Т‘Р С•РЎР‚Р С•Р В¶Р Р…Р В°РЎРЏ Р С”Р В°РЎР‚РЎвЂљР В° MVP (Р С—Р В°РЎвЂљРЎвЂЎР С‘ 0.1.0РІР‚вЂњ0.4.4).



\## \[0.1.0] РІР‚вЂќ Р С—Р В»Р В°Р Р…Р С‘РЎР‚РЎС“Р ВµРЎвЂљРЎРѓРЎРЏ



\### Added

\- Р ВР Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р В°РЎвЂ Р С‘РЎРЏ РЎР‚Р ВµР С—Р С•Р В·Р С‘РЎвЂљР С•РЎР‚Р С‘РЎРЏ, РЎРѓР С”Р ВµР В»Р ВµРЎвЂљ Avalonia-Р С—РЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘РЎРЏ, РЎвЂљР ВµР СРЎвЂ№, Р В»Р С•Р С”Р В°Р В»Р С‘Р В·Р В°РЎвЂ Р С‘РЎРЏ.

\- SQLite-РЎРѓРЎвЂ¦Р ВµР СР В° Р С‘ РЎР‚Р ВµР С—Р С•Р В·Р С‘РЎвЂљР С•РЎР‚Р С‘Р С‘.

\- Portable-РЎР‚Р ВµР В¶Р С‘Р С Р С‘ Р С”Р В°РЎР‚Р С”Р В°РЎРѓ РЎРЊР С”РЎР‚Р В°Р Р…Р В° Р’В«Р СњР В°РЎРѓРЎвЂљРЎР‚Р С•Р в„–Р С”Р С‘Р’В».


## 0.5.0a1
- UI: Added design tokens for Soft Glass theme (backgrounds, shadows, corner radii).
<!-- patch 0.5.0a1 applied -->
## 0.5.0a2
- UI: Applied Soft Glass tokens (shadows, radii, background) to ModelCardTile.
<!-- patch 0.5.0a2 applied -->
## 0.5.0a3
- UI: Applied Soft Glass tokens to sidebars and toolbars. Added App background.
<!-- patch 0.5.0a3 applied -->
## 0.5.0a4
- UI: Added global styles for Buttons, TextBoxes, ComboBoxes, and ListBoxItems.
<!-- patch 0.5.0a4 applied -->
## 0.5.0a6
- UI: Fixed theme dictionary crashes by sanitizing and properly placing theme-aware design tokens.
<!-- patch 0.5.0a6 applied -->
## 0.5.0a7
- UI: Fixed unreadable button text in Dark theme by adding theme-aware hover and pressed states.
<!-- patch 0.5.0a7 applied -->
## 0.5.0a8
- UI: Added gradient background for Light/Dark themes.
- UI: Fixed Button text readability in Dark theme and for checked states.
<!-- patch 0.5.0a8 applied -->
## 0.5.0a11
- UI: Safely applied warm sunlight gradient and tinted shadows using line-by-line replacement.
<!-- patch 0.5.0a11 applied -->
## 0.5.0a12
- UI: Reversed gradient direction to top-right to bottom-left.
- UI: Deepened lavender color in Light theme and adjusted Dark theme to graphite-purple.
<!-- patch 0.5.0a12 applied -->
## 0.5.0a13
- UI: Fixed background overrides by setting inner containers to Transparent.
- UI: Enhanced gradient depth and contrast for both Light and Dark themes.
<!-- patch 0.5.0a13 applied -->
## 0.5.0a14
- UI: Fixed ScrollViewer blocking the window background gradient.
- UI: Deepened lavender (Light) and graphite (Dark) gradient colors.
<!-- patch 0.5.0a14 applied -->
## 0.5.0a15
- UI: Moved shadows into ThemeDictionaries for theme-specific depth.
- UI: Reverted Light theme gradient to soft lavender.
- UI: Lightened dark theme card background and added deep black shadows.
<!-- patch 0.5.0a15 applied -->
## 0.5.0a16
- UI: Ensured elements with BoxShadow have CornerRadius and ClipToBounds to prevent rectangular "tile" shadows.
<!-- patch 0.5.0a16 applied -->
## 0.5.0a17
- UI: Removed ClipToBounds from shadowed elements to restore visibility.
- UI: Increased shadow blur radius for softer, more natural depth.
<!-- patch 0.5.0a17 applied -->
## 0.5.0a18
- UI: Added Margin to ModelCardTile and disabled ClipToBounds on ItemsControl/WrapPanel so shadows are no longer cut off.
<!-- patch 0.5.0a18 applied -->
## 0.5.1a1
- Render: Added spatial deduplication (MeshNormalSmoother) for high-poly models (>500K tris) to fix layer-line artifacts on 3D-scanned STL files.
- Tests: Added unit tests for MeshNormalSmoother.
<!-- patch 0.5.1a1 applied -->
## 0.5.1a2
- Docs: Updated HANDOFF.md with Soft Glass UI and Spatial Deduplication details.
<!-- patch 0.5.1a2 applied -->
## 0.5.1a3
- App: Added single-instance lock (Mutex) to prevent SQLite database race conditions.
- App: Added native MessageBox to warn user if another instance is already running.
<!-- patch 0.5.1a3 applied -->
## 0.5.1a4
- App: Replaced WrapPanel with virtualized ItemsRepeater (UniformGridLayout).
- App: Added Avalonia.Controls.ItemsRepeater package.
- Perf: Library grid now only renders visible cards, dramatically reducing memory and startup time for 1000+ models.
<!-- patch 0.5.1a4 applied -->
## 0.5.1a5
- App: Fixed ItemsRepeater package version to 11.1.5 and corrected XAML namespace.
- Perf: Library grid now uses virtualized ItemsRepeater with UniformGridLayout.
<!-- patch 0.5.1a5 applied -->
## 0.5.1a6
- UI: Replaced flat ListBox with TreeView for tag hierarchy.
- UI: Added TagNodeViewModel and recursive tree building in LibraryViewModel.
- Note: Filtering by parent tag passes comma-separated IDs to SearchAsync. ModelRepository may need updating to handle this.
<!-- patch 0.5.1a6 applied -->
## 0.5.1a7
- UI: Fixed ItemsRepeater bug by replacing the Cards collection instead of Clear/Add.
- UI: Added Equals/GetHashCode to TagNodeViewModel to keep TreeView selection stable.
<!-- patch 0.5.1a7 applied -->
## 0.5.1a8
- Data: Updated ModelRepository.SearchAsync to support comma-separated tag IDs (IN clause).
- UI: Changed Cards collection to IReadOnlyList to fix ItemsRepeater rendering on replacement.
- UI: Set TreeView.SelectedItem to TwoWay binding.
<!-- patch 0.5.1a8 applied -->
## 0.5.1a9
- Fix: Resolved compilation error (CS7036) caused by Cards.Remove on IReadOnlyList.
<!-- patch 0.5.1a9 applied -->
## 0.5.1a10
- Fix: Reset tag filter to "All Models" when navigating back to the library to prevent stuck filtering.
<!-- patch 0.5.1a10 applied -->
## 0.5.1a11
- UI: Reset tag selection to "All models" when LibraryView is re-attached (fixes stuck tag filter after returning from a card).
<!-- patch 0.5.1a11 applied -->
## 0.5.1a12
- UI: Reset tag filter to "All models" explicitly when returning from a card page.
<!-- patch 0.5.1a12 applied -->
## 0.5.1a13
- UI: Added ResetFilter to LibraryViewModel to forcibly clear tag and search filters.
- UI: Ensured both "Back" button and top menu "Library" button trigger a full filter reset.
<!-- patch 0.5.1a13 applied -->
## 0.5.1a14
- Perf: Reverted ItemsRepeater to ItemsControl + WrapPanel due to critical UI update bugs in Avalonia 11.1.5. 
- Fix: Restored stable ObservableCollection and Clear/Add for Cards to ensure filtering and navigation work correctly.
<!-- patch 0.5.1a14 applied -->
## 0.5.1a15
- Fix: Resolved compilation errors (CS0200/CS0103) by removing leftover Cards assignments from virtualization revert.
<!-- patch 0.5.1a15 applied -->
## 0.5.1a16
- UI: Added explicit TreeView.SelectionChanged handler to force ViewModel update.
- UI: Hard-reset _selectedTag and _searchQuery in ResetFilter to bypass binding issues.
- Debug: Added logging of SearchQuery and FilterTagIds before executing search.
<!-- patch 0.5.1a16 applied -->
## 0.5.1a17
- Fix: Resolved C# compilation errors (CS1056/CS1002) caused by literal backtick-n characters in LibraryViewModel.cs.
<!-- patch 0.5.1a17 applied -->
## 0.5.1a18
- Debug: Added ForceShowAllAsync with verbose logging to diagnose filter sticking.
- UI: onBack and ShowLibraryCommand now call ForceShowAllAsync directly.
<!-- patch 0.5.1a18 applied -->
## 0.5.1a19
- Fix: Added missing using directive for Log in MainWindowViewModel.
<!-- patch 0.5.1a19 applied -->
## 0.5.1a20
- UI: Replaced Cards collection entirely on reload to force ItemsControl to redraw.
- UI: Ensured LibraryView uses stable ItemsControl.
<!-- patch 0.5.1a20 applied -->
## 0.5.1a21
- Fix: Safely replaced Cards collection to force UI redraw. Restored from backup to avoid corrupted code.
<!-- patch 0.5.1a21 applied -->
## 0.5.1a22
- Fix: Prevented premature disposal of LibraryViewModel when navigating to a card. This was causing the library to appear empty or stuck on the previous tag filter.
<!-- patch 0.5.1a22 applied -->
## 0.5.1a23
- Fix: Removed ClipToBounds from ItemsControl/WrapPanel to restore layout inside ScrollViewer.
- Fix: Ensured Cards collection is updated on the UI thread to prevent rendering glitches.
<!-- patch 0.5.1a23 applied -->
## 0.5.1a24
- Fix: Serialized library loading with SemaphoreSlim to prevent concurrent reloads from overwriting Cards.
- Fix: Disabled horizontal scrolling in LibraryView to allow WrapPanel to measure correctly.
- Fix: Removed redundant OnTagSelectionChanged handler.
<!-- patch 0.5.1a24 applied -->
## 0.5.1a25
- Fix: Restored broken files from 0.5.1a24 and reapplied ScrollViewer and Semaphore fixes using exact string replacements.
<!-- patch 0.5.1a25 applied -->
## 0.5.1a26
- Fix: Forced entire Cards collection replacement to guarantee UI redraw on initial load.
- Fix: Added exception logging for preview bitmap loading.
<!-- patch 0.5.1a26 applied -->
## 0.5.1a27
- Fix: Restored Cards to a standard get-only ObservableCollection.
- Fix: Removed complex Dispatcher.InvokeAsync and collection replacement logic from ReloadModelsCoreAsync. Cards are now populated directly, ensuring UI reacts instantly.
<!-- patch 0.5.1a27 applied -->
## 0.5.1a28
- UI: Reduced card margins (8,8,8,28 -> 6,6,6,20) and shadow blur to increase grid density while keeping soft shadows visible.
<!-- patch 0.5.1a28 applied -->
## 0.5.1a29
- UI: Replaced Unicode status icons with native vector StreamGeometry (Clock, 3D Printer, Brush).
<!-- patch 0.5.1a29 applied -->
## 0.5.1a30
- Fix: Properly injected StreamGeometry icons into the root ResourceDictionary to fix AVLN3000.
- Clean: Removed unused _disposed field from LibraryViewModel to clear CS0169 warning.
<!-- patch 0.5.1a30 applied -->
## 0.5.1a31
- Fix: Icons injected strictly after ThemeDictionaries, resolving AVLN3000.
<!-- patch 0.5.1a31 applied -->
## 0.5.1a32
- Fix: Fully restored App.axaml from 0.5.1a28 working state and cleanly injected StreamGeometry icons.
<!-- patch 0.5.1a32 applied -->
## 0.5.1a33
- Data: Added ile_hash column to ModelFile and Migration_0004.
- Scanner: Compute SHA-256 hash for added or updated files.
- Repository: Save and load file hashes.
<!-- patch 0.5.1a33 applied -->
## 0.5.1a34
- Fix: Prevented IndexOutOfRangeException in ModelFileRepository.Map when file_hash column is missing.
<!-- patch 0.5.1a34 applied -->
## 0.5.1a35
- Data: Registered Migration_0004_ModelFile_Hash to enable ile_hash column creation.
<!-- patch 0.5.1a35 applied -->
## 0.5.1a38
- Feature: Implemented duplicate detection based on file hash.
- UI: Added "Find duplicates" button to library toolbar.
<!-- patch 0.5.1a38 applied -->
## 0.5.1a39
- Docs: Updated HANDOFF.md with post-release v0.1.1 state (UI Soft Glass, architecture fixes, duplicate detection, known issues).
<!-- patch 0.5.1a39 applied -->
## 0.5.2a - Smart Collections (backend plumbing)

- Added SmartCollectionFilter DTO (MiniCodex.Core.Models).
- Added ICollectionService / CollectionService (save/get/delete smart collections, JSON filter serialization).
- Added ITagService.SetColorAsync + implementation in TagService.
- Registered CollectionService in AppServices.
- New tests: CollectionServiceTests (5).

<!-- patch 0.5.2a applied -->

## 0.5.2b - Smart Collections + Tag color (ViewModels)

- CollectionRow (MiniCodex.App.ViewModels) wraps Collection + deserialized SmartCollectionFilter.
- TagNodeViewModel: Color, ColorBrush, HasColor, Palette (8 swatches), SetColorCommand, ClearColorCommand, OnColorChange callback.
- LibraryViewModel: Collections collection, SelectedCollection, SaveCurrentFilterAsCollectionCommand, DeleteCollectionCommand, ApplyCollectionAsync, ChangeTagColorAsync, LoadCollectionsAsync.
- LibraryViewModel ctor gains 7th optional ICollectionService parameter.
- MainWindowViewModel passes AppServices.CollectionService.

<!-- patch 0.5.2b applied -->

## 0.5.2c - Smart Collections + Tag color (UI)

- LibraryView.axaml: Collections section (header + delete button + ListBox) under the tag tree; per-tag color dot + context menu with 8 swatches + Clear in TreeDataTemplate; "Save filter" button in toolbar.
- TagNodeViewModel: added ClearColorLabel.
- lang/en.json + lang/ru.json: 5 new keys (CollectionsHeader, SaveFilterButton, SaveFilterEmpty, DeleteCollection, ClearColor).

<!-- patch 0.5.2c applied -->

## 0.5.2d - Save Filter dialog + HANDOFF sync

- LibraryViewModel: ShowSaveFilterDialog, NewCollectionName, SaveFilterDialog{Title,Placeholder,SaveText,CancelText}, OpenSaveFilterDialog, ConfirmSaveFilterAsync, CancelSaveFilter, ConfirmSaveFilterCommand, CancelSaveFilterCommand. SaveCurrentFilterAsCollectionCommand now opens the dialog instead of saving with placeholder name.
- LibraryView.axaml: modal overlay dialog (name + Save/Cancel) matching the ShowScanWarning style.
- lang/en.json + lang/ru.json: SaveFilterDialog block (4 keys each).
- HANDOFF.md: added lesson 11 (String.Split pitfall), added section 19 (0.5.2 series state).

<!-- patch 0.5.2d applied -->

## 0.5.3a - Tag rename/delete (backend)

- ITagService: added RenameAsync, DeleteAsync.
- TagService: implemented RenameAsync (trim, no-op on empty name/id), DeleteAsync (removes ModelTag associations first, then tag).
- IModelTagRepository: added RemoveAllForTagAsync.
- ModelTagRepository: implemented RemoveAllForTagAsync (DELETE FROM ModelTag WHERE tag_id = $t).
- New tests: TagCrudTests (5) - rename update, empty name/id no-op, delete with association cleanup, empty id no-op.

<!-- patch 0.5.3a applied -->

## 0.5.3a.1 - test-only fix

- TagCrudTests.DeleteAsync_RemovesTagAndAssociations: seed real Model rows via ModelRepository.UpsertAsync before ModelTag.AddAsync. Root cause: SqliteConnectionFactory.OpenAsync issues PRAGMA foreign_keys = ON, so inserting ModelTag for a non-existent model id violated the FK on ModelTag.model_id -> Model.id. Production code unchanged.

<!-- patch 0.5.3a.1 applied -->

## 0.5.3b - Tag rename/delete UI

- TagNodeViewModel: OnRename/OnDelete callbacks, RenameCommand/DeleteCommand (CanExecute=false for Id==""), RenameLabel/DeleteLabel, RefreshLocalized() (fixes stale ClearColorLabel/RenameLabel/DeleteLabel after language switch).
- LibraryViewModel: 6 new fields (dialog state + targets), 9 computed properties, 4 commands (Confirm/Cancel x Rename/Delete), 4 private methods (Open/Confirm x Rename/Delete), wire OnRename/OnDelete in LoadTagsAsync, RefreshLocalized for all TagNodeViewModel nodes. After delete: if SelectedTag was null, falls back to first (All models).
- LibraryView.axaml: 2 MenuItem (Rename, Delete) in TreeDataTemplate ContextMenu; 2 overlay dialogs (Rename styled like SaveFilter, Delete with red confirm button like ScanWarning).
- lang/en.json + lang/ru.json: 10 keys (TagContextMenu.Rename/Delete, RenameTagDialog.{Title,Placeholder,Save,Cancel}, DeleteTagDialog.{Title,Message,Delete,Cancel}). Indent normalized on 5 keys from 0.5.2c (36/40 -> 20/24).

<!-- patch 0.5.3b applied -->

## 0.5.3b.1 - Tag UI polish

- LibraryView.axaml: ContextMenu moved from TextBlock to root Grid + added HorizontalContentAlignment=Stretch style for TreeViewItem. Now right-click works anywhere on the tag row.
- LibraryView.axaml: color swatches use Border (16x16, CornerRadius=8) instead of hex code strings.

<!-- patch 0.5.3b.1 applied -->

## 0.5.3b.2 - Fix TreeViewItem style

- LibraryView.axaml: TreeViewItem does not have HorizontalContentAlignment in Avalonia 11. Replaced with Style Selector="TreeViewItem /template/ ContentPresenter#PART_HeaderPresenter" and both HorizontalAlignment and HorizontalContentAlignment set to Stretch.
- This makes the whole tag row stretch, so ContextMenu opens on right-click anywhere on the highlighted row.

<!-- patch 0.5.3b.2 applied -->

## 0.5.3b.3 - Enter/Esc in dialogs

- LibraryView.axaml: added IsDefault="True" / IsCancel="True" to all four dialog buttons (ScanWarning, SaveFilter, RenameTag, DeleteTag).
- Enter (Key.Return) triggers the default action (Save/Confirm/Continue).
- Esc (Key.Escape) triggers the cancel action.

<!-- patch 0.5.3b.3 applied -->

## 0.5.3b.4 - KeyBindings for Rename Tag dialog

- LibraryView.axaml: added Panel.KeyBindings with Gesture="Enter" -> ConfirmRenameTagCommand and Gesture="Escape" -> CancelRenameTagCommand.
- Rationale: Button.IsDefault/IsCancel in Avalonia stops working when focus is inside a TextBox. KeyBindings are handled at the root level and work regardless of focused control.

<!-- patch 0.5.3b.4 applied -->

## 0.5.3c - Custom Hex Color Picker

- TagNodeViewModel: CustomColorCommand, CustomColorLabel, OnCustomColor callback.
- LibraryViewModel: ShowColorPickerDialog, NewTagColor, ColorPreviewBrush, 4 computed strings, 2 commands, 3 methods (Open/Confirm/Cancel), wire in LoadTagsAsync.
- LibraryView.axaml: Custom Color... menu item, ColorPicker overlay (TextBox + preview), KeyBindings for Enter/Esc.
- lang: TagContextMenu.CustomColor, ColorPickerDialog.* keys.

<!-- patch 0.5.3c applied -->
