\# patch 0.5.3a

Tag rename/delete backend. ITagService += RenameAsync/DeleteAsync. TagService implements both (empty-input no-ops). IModelTagRepository += RemoveAllForTagAsync. ModelTagRepository implements it. New tests TagCrudTests (5). No UI, no ViewModel, no lang changes. Requires 0.5.2a (SetColorAsync) applied.

