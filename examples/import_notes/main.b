// A small CLI workload: typed JSON -> one atomic SQLite import -> report.
package main

import sqlite
import std.encoding.json
import std.fs
import std.io
import std.os

struct Note {
    pub id: int
    pub body: string
}

fn import_notes(database_path: string, input_path: string) -> Result<bool> {
    // Decode before touching the database. Unknown/missing fields and wrong
    // types use the existing strict typed JSON decoder's diagnostics.
    let text: string = fs.read(input_path)?
    let notes: List<Note> = json.decode(text)?
    let db: sqlite.Database = sqlite.Database.open(database_path)?
    let tx: sqlite.Transaction = db.begin_immediate()?
    db.exec("CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY CHECK(id > 0), body TEXT NOT NULL CHECK(length(body) > 0))")?
    let insert: sqlite.Statement = db.prepare("INSERT INTO notes(id, body) VALUES (?1, ?2)")?
    for note: Note in notes {
        insert.bind_int(1, note.id)?
        insert.bind_text(2, note.body)?
        insert.step()?
        insert.reset()?
    }
    insert.finalize()?
    tx.commit()?
    io.println("imported {notes.len()} notes")
    return ok(true)
}

fn report(database_path: string) -> Result<bool> {
    // A separate process reopens existing storage; reporting never creates it.
    let db: sqlite.Database = sqlite.Database.open_read_only(database_path)?
    let rows: sqlite.Statement = db.prepare("SELECT id, body FROM notes ORDER BY id")?
    for rows.step()? {
        io.println("{rows.column_int(0)}: {rows.column_text(1)}")
    }
    return ok(true)
}

fn run() -> Result<bool> {
    let args: List<string> = os.args()
    if args.len() == 3 && args[0] == "import" {
        return import_notes(args[1], args[2])
    }
    if args.len() == 2 && args[0] == "report" {
        return report(args[1])
    }
    return err("usage: import_notes import <database> <notes.json> | report <database>", "usage")
}

fn main() {
    match run() {
        ok(_) => {}
        err(problem) => {
            io.eprintln("{problem.kind}: {problem.msg}")
            os.exit(1)
        }
    }
}
