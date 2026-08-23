# sqlite

SQLite for Beans. The database compiles into your build from pinned,
checksummed source — no system packages, no make step, no manual memory.

```beans
import sqlite

fn main() {
    let db: sqlite.Database = sqlite.Database.open("app.db").expect("open")
    db.exec("CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, body TEXT NOT NULL)").expect("migrate")

    let tx: sqlite.Transaction = db.begin().expect("begin")
    let ins: sqlite.Statement = db.prepare("INSERT INTO notes(body) VALUES (?1)").expect("prepare")
    ins.bind_text(1, "hello from Beans").expect("bind")
    ins.step().expect("insert")
    ins.finalize().expect("finalize")
    tx.commit().expect("commit")

    let q: sqlite.Statement = db.prepare("SELECT id, body FROM notes ORDER BY id").expect("query")
    for q.step().expect("row") {
        io.println("note {q.column_int(0)}: {q.column_text(1)}")
    }
    // No finalize, no close: Statement and Database clean up in deinit.
}
```

Add it to a project:

```
beansc pot add github.com/beans-lang/sqlite v0.1.0
```

The manifest's `csrc` row rides along: your build compiles the vendored
SQLite (3.53.4) with the same toolchain and target flags as your own code.
First build pays for compiling sqlite3.c once; after that it comes from the
content-addressed cache.

## The shape of the API

| type | job | freed by |
|---|---|---|
| `Database` | connection: `open` / `open_read_only` / `open_memory`, `exec`, `prepare`, `begin`, `last_insert_rowid`, `changes`, `busy_timeout` | `deinit`, or `close()` now |
| `Statement` | one compiled statement: `bind_int/float/text/blob/null`, `step`, `reset`, `clear_bindings`, `column_*` | `deinit`, or `finalize()` now |
| `Transaction` | `commit` / `rollback`; one that dies unfinished **rolls back** | `deinit` |

Rules the whole surface follows:

- **No C leaks through.** No RawPtr, no C types, no manual free in any
  public signature. Errors are ordinary `Result` values with sqlite's own
  message and a stable `kind` (`constraint`, `busy`, `readonly`, ...).
- **Everything is copied out.** Column text and blobs are Beans-owned the
  moment an accessor returns; nothing you hold ever points into sqlite's
  row buffer.
- **Lifetimes are reference order.** A `Statement` keeps its `Database`
  alive, so drops always finalize before they close. `tests/lifecycle.b`
  ends by asserting `sqlite3_memory_used() == 0` — the no-leak proof comes
  from sqlite's own allocator meter.
- Parameters are 1-based, columns 0-based — sqlite's convention, kept so
  its docs read straight across.

## Layout

| path | what |
|---|---|
| `sqlite.b`, `statement.b`, `transaction.b` | the hand-written layer (start here) |
| `sys/sys.b` | generated raw bindings (`tools/regen_sys.sh`), 290/306 public functions — every gap explained in `SKIPPED.md` |
| `src/beans_sqlite.c` | the single translation unit: build `#define`s + two shims for the `SQLITE_TRANSIENT` macro |
| `vendor/` | upstream amalgamation, byte-identical, pinned in `VENDOR.md` (version, URL, SHA3-256 from sqlite.org, SHA-256) |
| `tests/` | scenario tests with golden outputs — CRUD, transactions, lifecycle/memory, persistence (`./test.sh`, `./test.sh --native`) |

## Build configuration

Set in `src/beans_sqlite.c`, documented there: `SQLITE_THREADSAFE=1`
(serialized — a Beans `deinit` may run on any thread), `SQLITE_DQS=0`,
`SQLITE_OMIT_LOAD_EXTENSION`, `SQLITE_ENABLE_MATH_FUNCTIONS` (the math
functions come from libc on every supported platform; no libm link row).

`sys/sys.b` is generated for `arm64-apple-darwin` and used everywhere: the
API is opaque-pointer-shaped, so the declarations are target-portable (a
`char*`-vs-`unsigned char*` signedness difference is type-level only; the
C ABI is identical). Cross-target type checks run in `test.sh`; per-target
regeneration diffs are the planned CI upgrade.

## License

Apache-2.0 for this package. SQLite itself is public domain
(https://sqlite.org/copyright.html).
