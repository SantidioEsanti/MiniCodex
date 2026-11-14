\# patch 0.5.3a.1

Test-only fix. TagCrudTests.DeleteAsync\_RemovesTagAndAssociations seeded ModelTag rows for non-existent models, which failed under PRAGMA foreign\_keys = ON. Fix: seed Model rows via ModelRepository.UpsertAsync before AddAsync. No production code changes. Requires 0.5.3a applied.

