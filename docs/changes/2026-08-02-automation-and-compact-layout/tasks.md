# Tasks: Checkbox Automation and Compact Layout

- [x] Inspect the current settings, task lifecycle, header, and shared player implementation.
- [x] Gather Lazyweb references for automation settings and responsive table toolbars.
- [x] Add regression tests for checkbox-only operation and compact layout variants.
- [x] Make every automation save handler start on enable and cancel on disable.
- [x] Remove redundant automation start/stop buttons while retaining passive progress.
- [x] Add compact library-header and flexible search layouts.
- [x] Add compact shared-player layout without dropping controls.
- [x] Add the persistent translation toggle, clickable right-pane status, and current-page reload.
- [x] Add upper/lower variation selection, confirmation, safe batch writing, and refresh.
- [x] Run focused tests, the full test suite, and an Apple Silicon debug build without launching the app.
  - Focused regression tests passed. The full `LibraryDatabaseTests` run retains three pre-existing failures (`migrationEnablesExpectedSchemaAndWAL`, `compactBatchEditorAndResizableSummaryColumnsAreWired`, and `cacheRetentionLimitCanBeTypedAndStepped`). The arm64 Debug build passed.
- [x] Record the fix and prevention notes in English and Japanese.
