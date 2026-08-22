# Vendored: SQLite

| field | value |
|---|---|
| version | 3.53.4 |
| source | https://sqlite.org/2026/sqlite-amalgamation-3530400.zip |
| archive SHA3-256 | `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e` (as published on sqlite.org/download.html) |
| archive SHA-256 | `1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d` |
| license | Public domain (https://sqlite.org/copyright.html) |

## Inventory

Byte-identical to the upstream amalgamation — no local edits, ever. All
configuration is `#define`s in `src/beans_sqlite.c`.

| file | SHA-256 |
|---|---|
| `sqlite3.c` | `b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189` |
| `sqlite3.h` | `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d` |

`shell.c` and `sqlite3ext.h` from the archive are not vendored: the shell is
a program, and the extension header only serves loadable extensions, which
this package compiles out (`SQLITE_OMIT_LOAD_EXTENSION`).

## Upgrade

1. Download the new amalgamation zip; verify its SHA3-256 against the value
   published on https://sqlite.org/download.html.
2. Replace `sqlite3.c` / `sqlite3.h`, update every hash above.
3. Regenerate `sys/sys.b` (command in the repo README) and diff — additions
   are new API; removals need a look.
4. Update `SKIPPED.md` if the skip list changed, and run `./test.sh`.
