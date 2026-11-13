# Patch 0.4.3f - Associations: 2 columns (Reference / Photo)

**Iteration:** 0.4

## What it does

- VM:
  - Removed AssetTypeChoices, SelectedAssetType, AssetFilterChoices, SelectedAssetFilter, FilteredAssets.
  - Added ReferenceAssets, PhotoAssets (ObservableCollections).
  - RebuildFilteredAssets -> RebuildAssetColumns: split by type (reference/null -> Reference, photo -> Photo).
  - ImportAssetsAsync(paths, assetType): explicit type from drop zone / Add button.
  - ReferenceColumnHeader / PhotoColumnHeader from Card.AssetType.*.
  - DropReferenceHintText / DropPhotoHintText from Card.Assoc.DropReference / DropPhoto.
- ModelCardView.axaml: Associations TabItem fully rewritten - two equal columns.
  - Each column: header + drop zone + "Add" button + gallery of cards.
  - Toolbar at top: Auto-link + status text.
  - Removed type/filter ComboBoxes (no longer relevant).
- ModelCardView.axaml.cs: full rewrite.
  - OnDragOver, OnDropReference, OnDropPhoto.
  - OnAddReferenceClick, OnAddPhotoClick with file picker.

## Limitation (MVP)

- Assets with type render/document/profile are stored in DB but NOT displayed.
- Fix in 0.4.3f.1: add "Others" section if needed.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Open card -> Associations tab -> 2 columns visible.
- Drag PNG onto Reference column -> asset created with type=reference.
- Drag PNG onto Photo column -> asset created with type=photo.
- Add button in each column -> file picker -> imports with the column's type.
- Auto-link still works, populates Reference.
- Remove (x) button on each card removes from DB, file on disk stays.