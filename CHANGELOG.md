# Changelog

## Unreleased

- Preserve an unfinished transaction after a rejected COMMIT or ROLLBACK, so
  a failed deferred constraint commit still rolls back on scope exit and can
  be repaired and retried through the same transaction handle.
- Add the typed JSON-to-SQLite `import_notes` CLI pilot and acceptance checks
  for interpreter/native execution, atomic failure, and reopened persistence.
- Discover the sibling compiler checkout in the documented workspace layout.
- Link the enabled SQLite math functions with libm on Linux; glibc still
  requires that library, and the existing interpreter resolves its soname.

## v0.1.1 — 2026-09-16

No library change. The README's example showed `import sqlite`; a consumer who
follows `pot add` writes `import github.com/beans-lang/sqlite`. Tagged so
cortado's cask example can pin a release instead of `require path "../sqlite"`.

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
