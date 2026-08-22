// Where the memory goes: prepared-statement reuse over hundreds of rows,
// results freed by scope exit (deinit) instead of hand-written free calls,
// close-before-finalize (sqlite's zombie connection), use-after-finalize as
// an error instead of a crash — and at the end, sqlite's own allocator
// meter reads zero, proving nothing leaked.
package main

import sqlite
import sqlite.sys
import std.io

fn count_rows(db: sqlite.Database) -> int {
    let q: sqlite.Statement = db.prepare("SELECT COUNT(*) FROM t").expect("prepare count")
    q.step().expect("step count")
    let value: int = q.column_int(0)
    q.finalize().expect("finalize count")
    return value
}

fn main() {
    let db: sqlite.Database = sqlite.Database.open_memory().expect("open")
    db.exec("CREATE TABLE t(x INTEGER PRIMARY KEY, s TEXT NOT NULL)").expect("create")

    // 500 inserts through one statement: bind, step, reset, repeat.
    let bulk: sqlite.Transaction = db.begin_immediate().expect("begin bulk")
    let ins: sqlite.Statement = db.prepare("INSERT INTO t(x, s) VALUES (?1, ?2)").expect("prepare insert")
    for index: int in 0..500 {
        ins.bind_int(1, index).expect("bind x")
        ins.bind_text(2, "row {index}").expect("bind s")
        ins.step().expect("step insert")
        ins.reset().expect("reset insert")
    }
    ins.finalize().expect("finalize insert")
    bulk.commit().expect("commit bulk")
    io.println("rows {count_rows(db)}")

    var used_while_open: i64 = 0
    unsafe {
        used_while_open = sys.sqlite3_memory_used()
    }
    io.println("memory in use {(used_while_open as int) > 0}")

    // A result read inside a scope and never finalized by hand: the
    // statement's deinit finalizes it at the closing brace.
    if true {
        let peek: sqlite.Statement = db.prepare("SELECT s FROM t WHERE x = ?1").expect("prepare peek")
        peek.bind_int(1, 250).expect("bind peek")
        let has_row: bool = peek.step().expect("step peek")
        io.println("peek {has_row} {peek.column_text(0)}")
    }

    // Statement misuse after finalize is an error, never a crash.
    let spent: sqlite.Statement = db.prepare("SELECT 1").expect("prepare spent")
    spent.finalize().expect("finalize spent")
    match spent.step() {
        ok(row) => io.println("spent step accepted {row}"),
        err(error) => io.println("spent step refused {error.kind}"),
    }
    spent.finalize().expect("second finalize is quiet")

    // Close with a statement still alive: sqlite keeps a zombie connection
    // until the last statement finalizes, so the read still answers — and
    // the connection object itself reports closed.
    let straggler: sqlite.Statement = db.prepare("SELECT COUNT(*) FROM t").expect("prepare straggler")
    db.close().expect("close with straggler live")
    io.println("open after close {db.is_open()}")
    match db.exec("SELECT 1") {
        ok(ran) => io.println("exec after close accepted {ran}"),
        err(error) => io.println("exec after close refused {error.kind}"),
    }
    straggler.step().expect("zombie step")
    io.println("zombie count {straggler.column_int(0)}")
    straggler.finalize().expect("finalize straggler")

    // Everything is closed and finalized: sqlite's allocator meter must be
    // back to zero. This is the no-leak proof, from the library itself.
    var used_at_end: i64 = 0
    unsafe {
        used_at_end = sys.sqlite3_memory_used()
    }
    io.println("memory clean {(used_at_end as int) == 0}")
    io.println("lifecycle ok")
}
