# Changelog

## v0.1.0 — 2026-08-23

- Initial release: SQLite 3.53.4 vendored (pinned + checksummed), OOP
  wrapper (`Database` / `Statement` / `Transaction`) with deinit-driven
  cleanup, copy-out column access, Result errors with stable kinds.
- 290/306 public functions bound via `beansc bindgen`; every gap accounted
  for in SKIPPED.md.
- Scenario tests with golden outputs: CRUD, transactions (commit, explicit
  rollback, scope-drop rollback, error-path rollback), lifecycle (500-row
  prepared reuse, zombie close, `sqlite3_memory_used() == 0` at exit),
  file persistence.
