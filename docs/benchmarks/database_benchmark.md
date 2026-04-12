# DB Performance Baseline — 2026-04-12

## Before Phase 1 pragma changes
- cache_size: -2000 (2 MB)
- mmap_size: not set (default 0)
- TM row count: TODO: fill in — run the app and record
- TM FTS5 search on common term "cost": TODO: fill in — run the app and record
- App memory after opening 10 recent projects: TODO: fill in — check Task Manager
- App startup to first editable project: TODO: fill in — measure manually

## After Task 1.2 (pragma tuning)
- cache_size: -64000 (64 MB)
- mmap_size: 268435456 (256 MB)
- TM FTS5 search on "cost" (post-change): TODO: fill in — run the app and record
