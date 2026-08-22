// The sqlite package's single translation unit.
//
// Configuration lives here, never in the vendored tree: vendor/ stays
// byte-identical to the upstream amalgamation (vendor/VENDOR.md has the
// pinned version and checksums), and this file #includes it with the
// package's build choices as #defines.

// Serialized mode is a requirement, not a preference: a Beans `deinit` runs
// on whichever thread drops the last reference, so a connection's close can
// arrive from a different thread than the one that used it.
#define SQLITE_THREADSAFE 1

// No extension loader: keeps every hosted target linkable without a dynamic
// loader dependency, and closes the classic load_extension attack surface.
#define SQLITE_OMIT_LOAD_EXTENSION 1

// Double-quoted string literals are a compatibility misfeature; new
// consumers get the strict behavior from day one.
#define SQLITE_DQS 0

// The SQL math functions (sin, log, pow, ...); pulls libm on Linux, which
// beans.pot links.
#define SQLITE_ENABLE_MATH_FUNCTIONS 1

#include "../vendor/sqlite3.c"

// The two entry points below exist because SQLITE_TRANSIENT is a macro that
// casts -1 to a function pointer — a constant no generated binding can
// carry. They take unsigned char* so the Beans side stays on RawPtr<u8>,
// which is what Bytes.as_ptr() yields; char* and unsigned char* share one
// C ABI.

int beans_sqlite3_bind_text_copy(sqlite3_stmt *stmt, int index,
                                 const unsigned char *text, int len) {
    return sqlite3_bind_text(stmt, index, (const char *)text, len,
                             SQLITE_TRANSIENT);
}

int beans_sqlite3_bind_blob_copy(sqlite3_stmt *stmt, int index,
                                 const unsigned char *data, int len) {
    return sqlite3_bind_blob(stmt, index, (const void *)data, len,
                             SQLITE_TRANSIENT);
}
