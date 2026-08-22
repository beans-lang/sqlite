# Coverage: what is not bound, and why

`sys/sys.b` binds **290 of the 306** public functions in the vendored
`sqlite3.h` (`tools/regen_sys.sh` prints the live numbers). Every gap is
listed here with its disposition. If a regeneration changes this list, this
file must change in the same commit.

## Excluded on purpose — varargs (8)

C varargs cannot cross a generated binding safely; each of these is either
covered by the wrapper or intentionally absent:

| function | disposition |
|---|---|
| `sqlite3_config` / `sqlite3_db_config` | global/connection setup; the wrapper pins the settings that matter (`SQLITE_THREADSAFE=1` at compile time, `busy_timeout()` as a method). More knobs become methods when someone needs them. |
| `sqlite3_mprintf` / `sqlite3_snprintf` / `sqlite3_str_appendf` | C-side string formatting; Beans string interpolation is the replacement. |
| `sqlite3_log` | sqlite's internal log sink; not application surface. |
| `sqlite3_test_control` | test harness backdoor; not application surface. |
| `sqlite3_vtab_config` | virtual-table author surface; out of scope until a virtual-table API exists. |

## Not part of this build — compile-gated (7)

Declared in the header only under `#define`s this package does not set, so
they do not exist in the compiled library either; binding them would be a
link error:

- `sqlite3_preupdate_hook` family (6 functions) — needs
  `SQLITE_ENABLE_PREUPDATE_HOOK`.
- `sqlite3_normalized_sql` — needs `SQLITE_ENABLE_NORMALIZE`.

`sqlite3_activate_cerod` is in the same bucket: a stub for a commercial
extension this package will never carry.

## Skipped by bindgen, fail-closed (structural)

Each skip comment in `sys/sys.b` names its declaration:

- `declaration 'sqlite3_version'` — the raw version *global* is an
  unsized `char[]` (a flexible array to the binder). Irrelevant in
  practice: `sqlite3_libversion()` is bound and is what
  `sqlite.version()` uses.
- `record 'Fts5ExtensionApi'` / `record 'fts5_tokenizer_v2'` — carry
  callbacks with more than six parameters; `record 'Fts5Api'` depends on
  the former. All three are the FTS5 *extension-author* API. Writing an
  FTS5 extension in Beans is out of scope; **using** FTS5 from SQL is
  unaffected.

## Macros re-declared by hand

`#define`s never reach a generated binding; the ones this package needs are
re-stated in Beans with sqlite's frozen values
(https://sqlite.org/rescode.html — the codes are a compatibility promise):

- open flags: READONLY (1), READWRITE|CREATE (6) — in `sqlite.b`'s
  constructors.
- step results: `SQLITE_ROW` (100), `SQLITE_DONE` (101) — in `exec`/`step`.
- primary result codes used for error kinds (BUSY 5, LOCKED 6, NOMEM 7,
  READONLY 8, FULL 13, CANTOPEN 14, CONSTRAINT 19, MISMATCH 20, MISUSE 21)
  — in `error_kind`.
- `SQLITE_TRANSIENT` — a cast macro, unrepresentable; carried by the two
  shims in `src/beans_sqlite.c`.
