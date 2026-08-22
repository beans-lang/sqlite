// The whole library in one file: open, migrate, insert inside a
// transaction, query, and let scope-exit do every cleanup.
package main

import sqlite
import std.io

fn main() {
    let db: sqlite.Database = sqlite.Database.open("quickstart.db").expect("open")
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
