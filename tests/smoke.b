package main

import sqlite
import std.io

fn main() {
    let db: sqlite.Database = sqlite.Database.open_memory().expect("open")
    db.exec("CREATE TABLE t(a INTEGER, b TEXT)").expect("create")
    db.exec("INSERT INTO t VALUES (1,'one'),(2,'two')").expect("insert")
    io.println("changes {db.changes()}")
    let q: sqlite.Statement = db.prepare("SELECT a, b FROM t ORDER BY a").expect("prepare")
    for q.step().expect("step") {
        io.println("row {q.column_int(0)} {q.column_text(1)}")
    }
    q.finalize().expect("finalize")

    // SQLITE_ENABLE_MATH_FUNCTIONS, served by libc — no libm link row.
    let math: sqlite.Statement = db.prepare("SELECT CAST(pow(2, 10) AS INTEGER), CAST(sqrt(144.0) AS INTEGER)").expect("prepare math")
    math.step().expect("step math")
    io.println("math {math.column_int(0)} {math.column_int(1)}")
    math.finalize().expect("finalize math")

    db.close().expect("close")
    io.println("smoke ok")
}
