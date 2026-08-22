// A compiled SQL statement: bind, step, read columns.
//
// Every value read out of a row is copied into Beans-owned memory before
// the accessor returns — sqlite's column pointers are only valid until the
// next step, and no caller should have to know that.
package sqlite

import sqlite.sys

// SQLITE_TRANSIENT is a macro (a -1 cast to a function pointer), so binding
// with a private copy goes through these two shims in src/beans_sqlite.c.
// They take unsigned char* to line up with Bytes.as_ptr()'s RawPtr<u8>.
extern "C" fn beans_sqlite3_bind_text_copy(
    stmt: RawPtr<sys.Sqlite3Stmt>, index: i32, text: RawPtr<u8>, len: i32) -> i32
extern "C" fn beans_sqlite3_bind_blob_copy(
    stmt: RawPtr<sys.Sqlite3Stmt>, index: i32, data: RawPtr<u8>, len: i32) -> i32

/// What a column holds in the current row.
pub enum ColumnType {
    integer
    real
    text
    blob
    absent
}

/// One compiled statement, owned by the `Database` that prepared it.
///
/// Parameters are 1-based (`bind_*`), columns are 0-based (`column_*`) —
/// sqlite's own convention, kept so its documentation reads straight
/// across. Finalized by `deinit`, or eagerly with `finalize()`. Reusable:
/// `reset` rewinds it, `clear_bindings` empties the parameters.
pub class Statement {
    stmt: RawPtr<sys.Sqlite3Stmt> = RawPtr.null()
    owner: Database
    live: bool = false

    fn init(stmt: RawPtr<sys.Sqlite3Stmt>, owner: Database) {
        self.stmt = stmt
        self.owner = owner
        self.live = true
    }

    fn deinit() {
        if self.live {
            self.live = false
            unsafe {
                let ignored: i32 = sys.sqlite3_finalize(self.stmt)
            }
        }
    }

    /// Binds a 64-bit integer to parameter `index` (1-based).
    pub fn bind_int(index: int, value: int) -> Result<bool> {
        if !self.live {
            return err("bind_int: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_bind_int64(self.stmt, index as i32, value as i64) as int
        }
        return self.bind_result(status, "bind_int")
    }

    /// Binds a float to parameter `index`.
    pub fn bind_float(index: int, value: f64) -> Result<bool> {
        if !self.live {
            return err("bind_float: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_bind_double(self.stmt, index as i32, value) as int
        }
        return self.bind_result(status, "bind_float")
    }

    /// Binds text to parameter `index`. The bytes are copied before this
    /// returns; the string owes sqlite nothing afterward.
    pub fn bind_text(index: int, value: string) -> Result<bool> {
        if !self.live {
            return err("bind_text: statement is finalized", "closed")
        }
        // The extra NUL keeps the buffer non-empty, so as_ptr() is a real
        // address even for ""; the length passed excludes it.
        var text_buf: Bytes = Bytes.from(value)
        text_buf.push(0)
        var status: int = 0
        unsafe {
            status = beans_sqlite3_bind_text_copy(
                self.stmt, index as i32, text_buf.as_ptr(),
                (text_buf.len() - 1) as i32) as int
        }
        return self.bind_result(status, "bind_text")
    }

    /// Binds a blob to parameter `index`, copying the bytes.
    pub fn bind_blob(index: int, value: Bytes) -> Result<bool> {
        if !self.live {
            return err("bind_blob: statement is finalized", "closed")
        }
        var status: int = 0
        if value.len() == 0 {
            // A null pointer with length zero would bind SQL NULL; an empty
            // blob is a different thing, and zeroblob(0) is exactly it.
            unsafe {
                status = sys.sqlite3_bind_zeroblob(self.stmt, index as i32, 0 as i32) as int
            }
        } else {
            unsafe {
                status = beans_sqlite3_bind_blob_copy(
                    self.stmt, index as i32, value.as_ptr(), value.len() as i32) as int
            }
        }
        return self.bind_result(status, "bind_blob")
    }

    /// Binds SQL NULL to parameter `index`.
    pub fn bind_null(index: int) -> Result<bool> {
        if !self.live {
            return err("bind_null: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_bind_null(self.stmt, index as i32) as int
        }
        return self.bind_result(status, "bind_null")
    }

    /// Runs the statement one row forward. `ok(true)` means a row is ready
    /// to read; `ok(false)` means it finished. Anything else is the error.
    pub fn step() -> Result<bool> {
        if !self.live {
            return err("step: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_step(self.stmt) as int
        }
        if status == 100 { // SQLITE_ROW
            return ok(true)
        }
        if status == 101 { // SQLITE_DONE
            return ok(false)
        }
        return err(self.owner.describe(status, "step"), error_kind(status))
    }

    /// Rewinds the statement so it can run again. Bindings survive a reset;
    /// use `clear_bindings` to drop them too.
    pub fn reset() -> Result<bool> {
        if !self.live {
            return err("reset: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_reset(self.stmt) as int
        }
        if status != 0 {
            return err(self.owner.describe(status, "reset"), error_kind(status))
        }
        return ok(true)
    }

    /// Sets every parameter back to NULL.
    pub fn clear_bindings() -> Result<bool> {
        if !self.live {
            return err("clear_bindings: statement is finalized", "closed")
        }
        var status: int = 0
        unsafe {
            status = sys.sqlite3_clear_bindings(self.stmt) as int
        }
        if status != 0 {
            return err(self.owner.describe(status, "clear_bindings"), error_kind(status))
        }
        return ok(true)
    }

    /// Columns in the result set.
    pub fn column_count() -> int {
        if !self.live {
            return 0
        }
        unsafe {
            return sys.sqlite3_column_count(self.stmt) as int
        }
    }

    /// The name of column `index` (0-based), as written in the SELECT.
    pub fn column_name(index: int) -> string {
        if !self.live {
            return ""
        }
        unsafe {
            return read_c_text(sys.sqlite3_column_name(self.stmt, index as i32))
        }
    }

    /// The type of column `index` in the current row.
    pub fn column_type(index: int) -> ColumnType {
        if !self.live {
            return ColumnType.absent
        }
        var code: int = 0
        unsafe {
            code = sys.sqlite3_column_type(self.stmt, index as i32) as int
        }
        if code == 1 { return ColumnType.integer }
        if code == 2 { return ColumnType.real }
        if code == 3 { return ColumnType.text }
        if code == 4 { return ColumnType.blob }
        return ColumnType.absent
    }

    /// True when column `index` is SQL NULL in the current row.
    pub fn column_is_null(index: int) -> bool {
        return self.column_type(index) == ColumnType.absent
    }

    /// Column `index` as an integer (sqlite's own coercion rules; NULL
    /// reads as 0).
    pub fn column_int(index: int) -> int {
        if !self.live {
            return 0
        }
        unsafe {
            return sys.sqlite3_column_int64(self.stmt, index as i32) as int
        }
    }

    /// Column `index` as a float (NULL reads as 0.0).
    pub fn column_float(index: int) -> f64 {
        if !self.live {
            return 0.0
        }
        unsafe {
            return sys.sqlite3_column_double(self.stmt, index as i32)
        }
    }

    /// Column `index` as text, copied out; NULL reads as "". Use
    /// `column_text_opt` when NULL and "" must stay distinct.
    pub fn column_text(index: int) -> string {
        if !self.live {
            return ""
        }
        unsafe {
            let pointer: RawPtr<u8> = sys.sqlite3_column_text(self.stmt, index as i32)
            if pointer.is_null() {
                return ""
            }
            let length: int = sys.sqlite3_column_bytes(self.stmt, index as i32) as int
            let copy: Bytes = Bytes.from_raw(pointer, length)
            return copy.to_string()
        }
    }

    /// Column `index` as text, or `none` for SQL NULL.
    pub fn column_text_opt(index: int) -> Option<string> {
        if self.column_is_null(index) {
            return none
        }
        return some(self.column_text(index))
    }

    /// Column `index` as bytes, copied out; NULL reads as empty.
    pub fn column_blob(index: int) -> Bytes {
        if !self.live {
            return new Bytes(0)
        }
        unsafe {
            let pointer: RawPtr<u8> = sys.sqlite3_column_blob(self.stmt, index as i32)
            if pointer.is_null() {
                return new Bytes(0)
            }
            let length: int = sys.sqlite3_column_bytes(self.stmt, index as i32) as int
            return Bytes.from_raw(pointer, length)
        }
    }

    /// Finalizes now instead of waiting for `deinit`. Safe to call twice.
    pub fn finalize() -> Result<bool> {
        if !self.live {
            return ok(true)
        }
        self.live = false
        var status: int = 0
        unsafe {
            status = sys.sqlite3_finalize(self.stmt) as int
        }
        if status != 0 {
            // Finalize reports the statement's last error; the statement is
            // gone either way.
            return err("finalize: {code_text(status)}", error_kind(status))
        }
        return ok(true)
    }

    // Shared tail for the bind_* family.
    fn bind_result(status: int, what: string) -> Result<bool> {
        if status != 0 {
            return err(self.owner.describe(status, what), error_kind(status))
        }
        return ok(true)
    }
}
