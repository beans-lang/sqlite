// Cross-process lock contention for the CLI acceptance test. Readiness is
// published only after SQLite owns the actual reserved write lock.
package main

import sqlite
import std.fs
import std.os
import std.time

fn main() {
    let args: List<string> = os.args()
    let db: sqlite.Database = sqlite.Database.open(args[0]).expect("open lock database")
    let tx: sqlite.Transaction = db.begin_immediate().expect("take write lock")
    fs.write(args[1], "ready").expect("publish lock readiness")
    // The shell releases it after asserting SQLITE_BUSY. Also expire so an
    // interrupted harness can never leave a lock holder running indefinitely.
    for tick: int in 0..1500 {
        if File.exists(args[2]) { break }
        time.sleep_millis(20)
    }
    tx.rollback().expect("release lock")
}
