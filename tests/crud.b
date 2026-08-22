// Real-world CRUD: parameter binding across every type, NULL round-trips,
// blob bytes with embedded NULs, UTF-8 text, 64-bit extremes, column
// metadata, and the constraint/syntax error paths.
package main

import sqlite
import std.io

fn main() {
    io.println("version set {sqlite.version().len() > 0}")

    let db: sqlite.Database = sqlite.Database.open_memory().expect("open")
    db.exec("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, age INTEGER, score REAL, avatar BLOB)").expect("create")

    let ins: sqlite.Statement = db.prepare("INSERT INTO users(name, age, score, avatar) VALUES (?1, ?2, ?3, ?4)").expect("prepare insert")

    // Full row: text, int, float, blob with an embedded NUL byte.
    var avatar: Bytes = new Bytes(4)
    avatar.set(0, 137)
    avatar.set(1, 0)
    avatar.set(2, 255)
    avatar.set(3, 7)
    let keep: Bytes = avatar.slice(0, avatar.len())
    ins.bind_text(1, "ada").expect("bind name")
    ins.bind_int(2, 36).expect("bind age")
    ins.bind_float(3, 99.5).expect("bind score")
    ins.bind_blob(4, avatar).expect("bind avatar")
    let first_done: bool = ins.step().expect("insert ada")
    io.println("insert row pending {first_done} rowid {db.last_insert_rowid()}")

    // NULLs everywhere the schema allows them.
    ins.reset().expect("reset")
    ins.clear_bindings().expect("clear")
    ins.bind_text(1, "grace").expect("bind name 2")
    ins.bind_null(2).expect("null age")
    ins.bind_null(3).expect("null score")
    ins.bind_null(4).expect("null avatar")
    ins.step().expect("insert grace")

    // UTF-8 well outside ASCII.
    ins.reset().expect("reset 2")
    ins.bind_text(1, "চা ☕").expect("bind name 3")
    ins.bind_int(2, 1).expect("bind age 3")
    ins.bind_float(3, 0.25).expect("bind score 3")
    ins.bind_null(4).expect("null avatar 3")
    ins.step().expect("insert tea")

    // The 64-bit rails.
    ins.reset().expect("reset 3")
    ins.bind_text(1, "max").expect("bind name 4")
    ins.bind_int(2, 9223372036854775807).expect("bind age 4")
    ins.bind_float(3, -0.5).expect("bind score 4")
    ins.bind_null(4).expect("null avatar 4")
    ins.step().expect("insert max")
    ins.finalize().expect("finalize insert")

    // Read it all back, copied out row by row.
    let q: sqlite.Statement = db.prepare("SELECT id, name, age, score, avatar FROM users ORDER BY id").expect("prepare select")
    for q.step().expect("step select") {
        let id: int = q.column_int(0)
        let name: string = q.column_text(1)
        var age_text: string = "null"
        if !q.column_is_null(2) {
            age_text = "{q.column_int(2)}"
        }
        var score_text: string = "null"
        if !q.column_is_null(3) {
            score_text = "{q.column_float(3)}"
        }
        var avatar_text: string = "null"
        if !q.column_is_null(4) {
            avatar_text = "{q.column_blob(4).len()} bytes"
        }
        io.println("user {id} {name} age={age_text} score={score_text} avatar={avatar_text}")
    }
    q.finalize().expect("finalize select")

    // The blob comes back byte-identical, embedded NUL included.
    let one: sqlite.Statement = db.prepare("SELECT avatar FROM users WHERE name = ?1").expect("prepare blob")
    one.bind_text(1, "ada").expect("bind blob name")
    one.step().expect("step blob")
    let fetched: Bytes = one.column_blob(0)
    io.println("blob round-trip {fetched == keep} len {fetched.len()}")
    one.finalize().expect("finalize blob")

    // Optional text: NULL and "" stay distinct.
    let opt: sqlite.Statement = db.prepare("SELECT age FROM users WHERE name = ?1").expect("prepare opt")
    opt.bind_text(1, "grace").expect("bind opt")
    opt.step().expect("step opt")
    match opt.column_text_opt(0) {
        some(text) => io.println("grace age text {text}"),
        none => io.println("grace age is null"),
    }
    opt.finalize().expect("finalize opt")

    // Column metadata reads what the SELECT wrote.
    let meta: sqlite.Statement = db.prepare("SELECT id AS ident, name FROM users ORDER BY id").expect("prepare meta")
    meta.step().expect("step meta")
    io.println("meta count {meta.column_count()} first {meta.column_name(0)} type integer {meta.column_type(0) == sqlite.ColumnType.integer}")
    meta.finalize().expect("finalize meta")

    // UPDATE and DELETE report their row counts.
    db.exec("UPDATE users SET age = 2 WHERE name = 'ada'").expect("update")
    io.println("updated {db.changes()}")
    db.exec("DELETE FROM users WHERE name = 'grace'").expect("delete")
    io.println("deleted {db.changes()}")

    // UNIQUE violation surfaces as kind "constraint" with sqlite's message.
    match db.exec("INSERT INTO users(name) VALUES ('ada')") {
        ok(done) => io.println("duplicate accepted {done}"),
        err(error) => io.println("duplicate refused {error.kind}"),
    }

    // A typo is an ordinary error, not a panic.
    match db.prepare("SELEC 1") {
        ok(bad) => io.println("typo accepted"),
        err(error) => io.println("typo refused {error.kind}"),
    }

    db.close().expect("close")
    io.println("crud ok")
}
