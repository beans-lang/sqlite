// A database file that outlives its connection: write inside a
// transaction, let scope-exit close the connection, reopen read-only,
// verify, clean up.
package main

import sqlite
import std.io

fn main() {
    let path: string = "beans_sqlite_persistence_test.db"
    let fresh: Result<bool> = File.remove(path)

    if true {
        let db: sqlite.Database = sqlite.Database.open(path).expect("open create")
        db.exec("CREATE TABLE notes(id INTEGER PRIMARY KEY, body TEXT NOT NULL)").expect("create")
        let tx: sqlite.Transaction = db.begin().expect("begin")
        let ins: sqlite.Statement = db.prepare("INSERT INTO notes(body) VALUES (?1)").expect("prepare")
        ins.bind_text(1, "first note").expect("bind 1")
        ins.step().expect("insert 1")
        ins.reset().expect("reset")
        ins.bind_text(1, "second note").expect("bind 2")
        ins.step().expect("insert 2")
        ins.finalize().expect("finalize")
        tx.commit().expect("commit")
        io.println("wrote up to rowid {db.last_insert_rowid()}")
        // No close() on purpose: deinit closes at the brace.
    }

    io.println("file exists {File.exists(path)}")

    let db: sqlite.Database = sqlite.Database.open_read_only(path).expect("reopen")
    let q: sqlite.Statement = db.prepare("SELECT id, body FROM notes ORDER BY id").expect("prepare read")
    for q.step().expect("step read") {
        io.println("note {q.column_int(0)}: {q.column_text(1)}")
    }
    q.finalize().expect("finalize read")

    // Read-only means read-only.
    match db.exec("INSERT INTO notes(body) VALUES ('nope')") {
        ok(ran) => io.println("write on read-only accepted {ran}"),
        err(error) => io.println("write on read-only refused {error.kind}"),
    }

    db.close().expect("close")
    File.remove(path).expect("cleanup")
    io.println("persistence ok")
}
