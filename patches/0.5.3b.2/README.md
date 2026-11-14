\# patch 0.5.3b.2

Fix TreeViewItem style for ContextMenu hit area. In Avalonia 11, TreeViewItem does not have HorizontalContentAlignment. Use Style Selector="TreeViewItem /template/ ContentPresenter#PART\_HeaderPresenter" with HorizontalAlignment and HorizontalContentAlignment set to Stretch. Requires 0.5.3b.1 applied.

