\# patch 0.5.3b

Tag rename/delete UI. TagNodeViewModel gains OnRename/OnDelete callbacks, RenameCommand/DeleteCommand, RenameLabel/DeleteLabel, RefreshLocalized(). LibraryViewModel gains rename/delete dialog state, 4 commands, wire in LoadTagsAsync. LibraryView.axaml: 2 MenuItem in ContextMenu + 2 modal overlays. lang: +10 keys, indents normalized. Requires 0.5.3a/0.5.3a.1.

