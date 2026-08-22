// SQLite for Beans — the connection.
//
// The vendored C library compiles into the consumer's build through the
// `csrc` row in beans.pot; nothing here needs a make step. The raw generated
// surface lives in `sqlite.sys` (bindgen output, regenerable); this package
// is the hand-written layer that owns every pointer, so no RawPtr, no C
// type and no manual free ever reaches a caller.
//
// Lifetimes are the runtime's reference order. A `Statement` keeps its
// `Database` alive, so handles always die child-first: statements finalize,
// then the connection closes. `deinit` is the backstop; `close()` and
// `finalize()` exist for callers who want the resource gone now.
package sqlite

import sqlite.sys

// ---- C text helpers (package-private) ----

// A NUL-terminated byte copy of `text`, so a borrowed pointer to it is a
// valid C string for the duration of the call it feeds.
fn c_text(text: string) -> Bytes {
    var buffer: Bytes = Bytes.from(text)
    buffer.push(0)
    return move buffer
}

// The same address seen as sqlite's `const char*`. Beans keeps u8 and i8
// pointers distinct; the C ABI does not.
fn as_char_ptr(pointer: RawPtr<u8>) -> RawPtr<i8> {
    unsafe {
        return RawPtr.from_address(pointer.address())
    }
}

// Copies a NUL-terminated C string into a Beans string. Every text that
// crosses the boundary is copied out immediately — after this returns,
// no Beans value depends on C-owned memory.
fn read_c_text(pointer: RawPtr<i8>) -> string {
    if pointer.is_null() {
        return ""
    }
    var length: int = 0
    unsafe {
        let view: RawPtr<u8> = RawPtr.from_address(pointer.address())
        for (view.offset(length).read() as int) != 0 {
            length = length + 1
        }
        let copy: Bytes = Bytes.from_raw(view, length)
        return copy.to_string()
    }
}

// ---- error mapping (package-private) ----
//
// sqlite result codes are #defines, which a generated binding cannot see;
// the ones named here are frozen by sqlite's compatibility promise
// (https://sqlite.org/rescode.html). Extended codes collapse to their
// primary before mapping.

fn error_kind(code: int) -> string {
    let primary: int = code % 256
    if primary == 5 { return "busy" }        // SQLITE_BUSY
    if primary == 6 { return "locked" }      // SQLITE_LOCKED
    if primary == 7 { return "nomem" }       // SQLITE_NOMEM
    if primary == 8 { return "readonly" }    // SQLITE_READONLY
    if primary == 13 { return "full" }       // SQLITE_FULL
    if primary == 14 { return "cantopen" }   // SQLITE_CANTOPEN
    if primary == 19 { return "constraint" } // SQLITE_CONSTRAINT
    if primary == 20 { return "datatype" }   // SQLITE_MISMATCH
    if primary == 21 { return "misuse" }     // SQLITE_MISUSE
    return "sqlite"
}

// The library's own text for a result code, for failures with no live
// connection to ask.
fn code_text(code: int) -> string {
    unsafe {
        return read_c_text(sys.sqlite3_errstr(code as i32))
    }
}

// Shared open path for the three public constructors. On failure sqlite
// still hands a handle back so the message survives; read it, then close.
fn open_with_flags(path: string, flags: int) -> Result<Database> {
    var path_buf: Bytes = c_text(path)
    var status: int = 0
    var handle: RawPtr<sys.Sqlite3> = RawPtr.null()
    unsafe {
        let handle_out: RawPtr<RawPtr<sys.Sqlite3>> = RawPtr.alloc(1)
        let no_vfs: RawPtr<i8> = RawPtr.null()
        status = sys.sqlite3_open_v2(
            as_char_ptr(path_buf.as_ptr()), handle_out, flags as i32, no_vfs) as int
        handle = handle_out.read()
        handle_out.free()
    }
    if status != 0 {
        var detail: string = code_text(status)
        if !handle.is_null() {
            unsafe {
                detail = read_c_text(sys.sqlite3_errmsg(handle))
                let ignored: i32 = sys.sqlite3_close_v2(handle)
            }
        }
        return err("open {path}: {detail} (sqlite code {status})", error_kind(status))
    }
    if handle.is_null() {
        return err("open {path}: out of memory", "nomem")
    }
    return ok(new Database(handle))
}

/// The vendored SQLite version, e.g. "3.53.4".
pub fn version() -> string {
    unsafe {
        return read_c_text(sys.sqlite3_libversion())
    }
}

// ---- the connection ----

/// An open SQLite database.
///
/// Obtained from `Database.open` / `open_read_only` / `open_memory`. Closed
/// by `deinit` when the last reference drops, or eagerly with `close()`.
/// Statements hold their database alive, so drop order can never close a
/// connection out from under a live statement.
pub class Database {
    handle: RawPtr<sys.Sqlite3> = RawPtr.null()
    live: bool = false

    fn init(handle: RawPtr<sys.Sqlite3>) {
        self.handle = handle
        self.live = true
    }

    fn deinit() {
        if self.live {
            self.live = false
            unsafe {
                let ignored: i32 = sys.sqlite3_close_v2(self.handle)
            }
        }
    }

    /// Opens (creating if missing) a database file for reading and writing.
    pub static fn open(path: string) -> Result<Database> {
        // SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        return open_with_flags(path, 6)
    }

    /// Opens an existing database file read-only.
    pub static fn open_read_only(path: string) -> Result<Database> {
        // SQLITE_OPEN_READONLY
        return open_with_flags(path, 1)
    }

    /// Opens a private in-memory database.
    pub static fn open_memory() -> Result<Database> {
        return open_with_flags(":memory:", 6)
    }

    /// Runs one or more SQL statements, separated by semicolons, discarding
    /// any rows they produce. For statements with parameters or results,
    /// use `prepare`.
    pub fn exec(sql: string) -> Result<bool> {
        if !self.live {
            return err("exec: database is closed", "closed")
        }
        var failed: int = 0
        var stage: string = ""
        var text_buf: Bytes = c_text(sql)
        unsafe {
            var cursor: RawPtr<i8> = as_char_ptr(text_buf.as_ptr())
            let stmt_out: RawPtr<RawPtr<sys.Sqlite3Stmt>> = RawPtr.alloc(1)
            let tail_out: RawPtr<RawPtr<i8>> = RawPtr.alloc(1)
            let whole_text: i32 = -1
            var more: bool = true
            for more {
                let view: RawPtr<u8> = RawPtr.from_address(cursor.address())
                if (view.read() as int) == 0 {
                    more = false
                } else {
                    let prepared: int = sys.sqlite3_prepare_v2(
                        self.handle, cursor, whole_text, stmt_out, tail_out) as int
                    if prepared != 0 {
                        failed = prepared
                        stage = "exec (prepare)"
                        more = false
                    } else {
                        let stmt: RawPtr<sys.Sqlite3Stmt> = stmt_out.read()
                        cursor = tail_out.read()
                        // A null statement is trailing whitespace or a
                        // comment: nothing to run in this round.
                        if !stmt.is_null() {
                            var stepping: bool = true
                            for stepping {
                                let status: int = sys.sqlite3_step(stmt) as int
                                if status == 100 {
                                    // SQLITE_ROW: exec discards rows.
                                } else {
                                    stepping = false
                                    if status != 101 {
                                        // Not SQLITE_DONE: a real failure.
                                        failed = status
                                        stage = "exec (step)"
                                    }
                                }
                            }
                            let finalized: int = sys.sqlite3_finalize(stmt) as int
                            if failed == 0 && finalized != 0 {
                                failed = finalized
                                stage = "exec (finalize)"
                            }
                            if failed != 0 {
                                more = false
                            }
                        }
                    }
                }
            }
            stmt_out.free()
            tail_out.free()
        }
        if failed != 0 {
            return err(self.describe(failed, stage), error_kind(failed))
        }
        return ok(true)
    }

    /// Compiles one SQL statement. Bind parameters with the `bind_*`
    /// methods, then walk rows with `step`.
    pub fn prepare(sql: string) -> Result<Statement> {
        if !self.live {
            return err("prepare: database is closed", "closed")
        }
        var status: int = 0
        var stmt: RawPtr<sys.Sqlite3Stmt> = RawPtr.null()
        var text_buf: Bytes = c_text(sql)
        unsafe {
            let stmt_out: RawPtr<RawPtr<sys.Sqlite3Stmt>> = RawPtr.alloc(1)
            let tail_out: RawPtr<RawPtr<i8>> = RawPtr.alloc(1)
            let whole_text: i32 = -1
            status = sys.sqlite3_prepare_v2(
                self.handle, as_char_ptr(text_buf.as_ptr()), whole_text,
                stmt_out, tail_out) as int
            stmt = stmt_out.read()
            stmt_out.free()
            tail_out.free()
        }
        if status != 0 {
            return err(self.describe(status, "prepare"), error_kind(status))
        }
        if stmt.is_null() {
            return err("prepare: no SQL statement in the text", "invalid")
        }
        return ok(new Statement(stmt, self))
    }

    /// Begins a deferred transaction. Commit or roll back through the
    /// returned handle; a `Transaction` that dies unfinished rolls back.
    pub fn begin() -> Result<Transaction> {
        self.exec("BEGIN")?
        return ok(new Transaction(self))
    }

    /// Begins an immediate transaction — takes the write lock now, so a
    /// later `commit` cannot fail with `busy` at the first write.
    pub fn begin_immediate() -> Result<Transaction> {
        self.exec("BEGIN IMMEDIATE")?
        return ok(new Transaction(self))
    }

    /// The rowid of the most recent successful INSERT on this connection.
    pub fn last_insert_rowid() -> int {
        if !self.live {
            return 0
        }
        unsafe {
            return sys.sqlite3_last_insert_rowid(self.handle) as int
        }
    }

    /// Rows changed by the most recent INSERT, UPDATE or DELETE.
    pub fn changes() -> int {
        if !self.live {
            return 0
        }
        unsafe {
            return sys.sqlite3_changes64(self.handle) as int
        }
    }

    /// Waits up to `milliseconds` on a locked database before a statement
    /// reports `busy`. Zero turns waiting off.
    pub fn busy_timeout(milliseconds: int) -> Result<bool> {
        if !self.live {
            return err("busy_timeout: database is closed", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_busy_timeout(self.handle, milliseconds as i32) as int
        }
        if status != 0 {
            return err(self.describe(status, "busy_timeout"), error_kind(status))
        }
        return ok(true)
    }

    /// Closes the connection now. Statements still alive keep working
    /// against a zombie connection sqlite tears down when the last one
    /// finalizes — but code that wants determinism should finalize first.
    /// Safe to call twice; `deinit` covers the forgotten case.
    pub fn close() -> Result<bool> {
        if !self.live {
            return err("close: database is already closed", "closed")
        }
        self.live = false
        var status: int = 0
        unsafe {
            status = sys.sqlite3_close_v2(self.handle) as int
        }
        if status != 0 {
            return err("close: {code_text(status)}", error_kind(status))
        }
        return ok(true)
    }

    /// True until `close()` runs or the value is collected.
    pub fn is_open() -> bool {
        return self.live
    }

    // The connection's own words for a failure, while it is still open to
    // ask; falls back to the library's static text.
    fn describe(code: int, what: string) -> string {
        var detail: string = ""
        if self.live {
            unsafe {
                detail = read_c_text(sys.sqlite3_errmsg(self.handle))
            }
        } else {
            detail = code_text(code)
        }
        return "{what}: {detail} (sqlite code {code})"
    }
}
