// Transactions the way applications actually hit them: a committed
// transfer, an explicit rollback, a scope that drops the transaction on the
// floor (deinit rolls back), an error path that propagates with `?` and
// still rolls back, misuse of a finished transaction, and BEGIN inside
// BEGIN.
package main

import sqlite
import std.io

fn balance(db: sqlite.Database, name: string) -> int {
    let q: sqlite.Statement = db.prepare("SELECT balance FROM accounts WHERE name = ?1").expect("prepare balance")
    q.bind_text(1, name).expect("bind balance")
    q.step().expect("step balance")
    let value: int = q.column_int(0)
    q.finalize().expect("finalize balance")
    return value
}

fn transfer(db: sqlite.Database, from: string, to: string, amount: int) -> Result<bool> {
    let tx: sqlite.Transaction = db.begin()?
    let debit: sqlite.Statement = db.prepare("UPDATE accounts SET balance = balance - ?1 WHERE name = ?2")?
    debit.bind_int(1, amount)?
    debit.bind_text(2, from)?
    debit.step()?
    debit.finalize()?
    let credit: sqlite.Statement = db.prepare("UPDATE accounts SET balance = balance + ?1 WHERE name = ?2")?
    credit.bind_int(1, amount)?
    credit.bind_text(2, to)?
    credit.step()?
    credit.finalize()?
    return tx.commit()
}

// The failing write sits after a successful one; `?` bails out, the
// unfinished Transaction dies, and its deinit rolls the first write back.
fn broken_transfer(db: sqlite.Database) -> Result<bool> {
    let tx: sqlite.Transaction = db.begin()?
    db.exec("UPDATE accounts SET balance = balance - 10 WHERE name = 'alice'")?
    db.exec("INSERT INTO no_such_table VALUES (1)")?
    return tx.commit()
}

fn main() {
    let db: sqlite.Database = sqlite.Database.open_memory().expect("open")
    db.exec("CREATE TABLE accounts(name TEXT PRIMARY KEY, balance INTEGER NOT NULL)").expect("create")
    db.exec("INSERT INTO accounts VALUES ('alice', 100), ('bob', 50)").expect("seed")

    // Committed transfer moves the money and keeps the total.
    transfer(db, "alice", "bob", 30).expect("transfer")
    let alice_after_commit: int = balance(db, "alice")
    let bob_after_commit: int = balance(db, "bob")
    io.println("after commit alice {alice_after_commit} bob {bob_after_commit}")

    // Explicit rollback undoes the write.
    let tx: sqlite.Transaction = db.begin().expect("begin rollback case")
    db.exec("UPDATE accounts SET balance = 0 WHERE name = 'alice'").expect("zero alice")
    tx.rollback().expect("rollback")
    let alice_after_rollback: int = balance(db, "alice")
    io.println("after rollback alice {alice_after_rollback}")

    // A transaction dropped without commit rolls back in deinit.
    if true {
        let abandoned: sqlite.Transaction = db.begin().expect("begin abandoned")
        db.exec("UPDATE accounts SET balance = 999 WHERE name = 'bob'").expect("touch bob")
    }
    let bob_after_abandoned: int = balance(db, "bob")
    io.println("after abandoned bob {bob_after_abandoned}")

    // The ? error path also lands on deinit's rollback.
    match broken_transfer(db) {
        ok(done) => io.println("broken transfer accepted {done}"),
        err(error) => io.println("broken transfer refused {error.kind}"),
    }
    let alice_after_broken: int = balance(db, "alice")
    io.println("after broken alice {alice_after_broken}")

    // A finished transaction refuses a second finish.
    let done_tx: sqlite.Transaction = db.begin().expect("begin misuse case")
    done_tx.commit().expect("first commit")
    match done_tx.commit() {
        ok(again) => io.println("double commit accepted {again}"),
        err(error) => io.println("double commit refused {error.kind}"),
    }

    // BEGIN inside BEGIN is sqlite's own error, reported not panicked.
    let outer: sqlite.Transaction = db.begin().expect("begin outer")
    match db.begin() {
        ok(inner) => io.println("nested begin accepted"),
        err(error) => io.println("nested begin refused {error.kind}"),
    }
    outer.rollback().expect("finish outer")

    // Immediate transactions take the write lock up front.
    let bulk: sqlite.Transaction = db.begin_immediate().expect("begin immediate")
    db.exec("INSERT INTO accounts VALUES ('carol', 25)").expect("insert carol")
    bulk.commit().expect("commit immediate")
    let carol_balance: int = balance(db, "carol")
    io.println("carol {carol_balance}")

    db.close().expect("close")
    io.println("transactions ok")
}
