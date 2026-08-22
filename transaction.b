// A transaction that cannot be left half-open.
//
// `Database.begin()` runs BEGIN and hands one of these back. Exactly one of
// `commit()` or `rollback()` finishes it; a Transaction that dies
// unfinished — an early return, a `?` propagating an error — rolls back in
// `deinit`. That is the whole point: the failure path needs no code.
package sqlite

/// An open transaction on a `Database`.
pub class Transaction {
    owner: Database
    finished: bool = false

    fn init(owner: Database) {
        self.owner = owner
    }

    fn deinit() {
        if !self.finished {
            self.finished = true
            // Nowhere to report from a destructor; a failed rollback here
            // means the connection is already gone, which is itself the
            // rollback.
            let ignored: Result<bool> = self.owner.exec("ROLLBACK")
        }
    }

    /// Makes the transaction's writes permanent.
    pub fn commit() -> Result<bool> {
        if self.finished {
            return err("commit: transaction is already finished", "misuse")
        }
        self.finished = true
        return self.owner.exec("COMMIT")
    }

    /// Undoes the transaction's writes now, without waiting for `deinit`.
    pub fn rollback() -> Result<bool> {
        if self.finished {
            return err("rollback: transaction is already finished", "misuse")
        }
        self.finished = true
        return self.owner.exec("ROLLBACK")
    }

    /// True once committed or rolled back.
    pub fn is_finished() -> bool {
        return self.finished
    }
}
