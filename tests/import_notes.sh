#!/usr/bin/env bash
# Acceptance for the real CLI example, using independent expected results.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BEANSC=${BEANSC:?test.sh supplies BEANSC}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/beans-import-notes.XXXXXX")
lock_pid=""
cleanup() {
    if [[ -n $lock_pid ]]; then
        kill "$lock_pid" 2>/dev/null || true
        wait "$lock_pid" 2>/dev/null || true
    fi
    chmod -R u+rw "$tmp"
    rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/good.json" <<'JSON'
[{"id":2,"body":"'; DROP TABLE notes; --"},{"id":1,"body":"বাংলা"}]
JSON
cat >"$tmp/duplicate.json" <<'JSON'
[{"id":3,"body":"must roll back"},{"id":1,"body":"duplicate"}]
JSON
printf '%s\n' '1: বাংলা' "2: '; DROP TABLE notes; --" >"$tmp/report.expected"
printf '%s\n' 'imported 2 notes' >"$tmp/import.expected"
printf '%s\n' '[{"id":4,"body":"first"},{"id":0,"body":"invalid id"}]' >"$tmp/invalid-id.json"
printf '%s\n' '[{"id":4,"body":"first"},{"id":5,"body":""}]' >"$tmp/empty-body.json"
printf '%s\n' '[{"id":3}]' >"$tmp/missing-field.json"
printf '%s\n' '[{"id":3,"body":"note","typo":true}]' >"$tmp/unknown-field.json"
printf '%s\n' '[{"id":"3","body":"note"}]' >"$tmp/wrong-type.json"
printf '%s\n' '[{"id":3,"body":' >"$tmp/malformed.json"
printf '%s\n' '[]' >"$tmp/empty-array.json"
: >"$tmp/empty-file.json"
printf '%s\n' '[{"id":9,"body":"must not write"}]' >"$tmp/denied.json"
printf '%s\n' 'imported 0 notes' >"$tmp/empty.expected"

acceptance() {
    local backend=$1
    shift
    local db="$tmp/$backend.db"
    local kind
    "$@" import "$db" "$tmp/good.json" >"$tmp/import.actual"
    diff -u "$tmp/import.expected" "$tmp/import.actual"
    "$@" report "$db" >"$tmp/report.actual"
    diff -u "$tmp/report.expected" "$tmp/report.actual"

    "$@" import "$tmp/$backend-empty.db" "$tmp/empty-array.json" >"$tmp/import.actual"
    diff -u "$tmp/empty.expected" "$tmp/import.actual"
    "$@" report "$tmp/$backend-empty.db" >"$tmp/report.actual"
    test ! -s "$tmp/report.actual"

    for kind in duplicate invalid-id empty-body; do
        if "$@" import "$db" "$tmp/$kind.json" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
            echo "$backend accepted $kind" >&2; exit 1
        fi
        test ! -s "$tmp/rejected.out"
        grep -q '^constraint:' "$tmp/rejected.err"
        "$@" report "$db" >"$tmp/report.actual"
        diff -u "$tmp/report.expected" "$tmp/report.actual"
    done
    for kind in missing-field unknown-field wrong-type malformed empty-file; do
        if "$@" import "$tmp/$backend-$kind.db" "$tmp/$kind.json" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
            echo "$backend accepted $kind" >&2; exit 1
        fi
        test ! -s "$tmp/rejected.out"
        test -s "$tmp/rejected.err"
        test ! -e "$tmp/$backend-$kind.db"
    done
    if "$@" import "$db" "$tmp/absent.json" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
        echo "$backend accepted an absent input" >&2; exit 1
    fi
    test -s "$tmp/rejected.err"
    if "$@" report "$tmp/absent.db" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
        echo "$backend created an absent report database" >&2; exit 1
    fi
    grep -q '^cantopen:' "$tmp/rejected.err"
    test ! -e "$tmp/absent.db"
    if "$@" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
        echo "$backend accepted missing arguments" >&2; exit 1
    fi
    grep -q '^usage:' "$tmp/rejected.err"

    # A separate Beans process owns a real SQLite write lock. Readiness is
    # signaled after BEGIN IMMEDIATE; no timing guess or simulated lock.
    local ready="$tmp/$backend-ready"
    local release="$tmp/$backend-release"
    "$BEANSC" run "$ROOT/tests/hold_lock.b" -- "$db" "$ready" "$release" >"$tmp/holder.out" 2>"$tmp/holder.err" &
    lock_pid=$!
    for ((attempt=0; attempt<200; attempt++)); do
        if [[ -f $ready ]]; then break; fi
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            cat "$tmp/holder.err" >&2
            echo "lock holder exited before readiness" >&2; exit 1
        fi
        sleep 0.1
    done
    test -f "$ready"
    if "$@" import "$db" "$tmp/denied.json" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
        echo "$backend wrote through a SQLite lock" >&2; exit 1
    fi
    grep -q '^busy:' "$tmp/rejected.err"
    touch "$release"
    wait "$lock_pid"
    lock_pid=""
    "$@" report "$db" >"$tmp/report.actual"
    diff -u "$tmp/report.expected" "$tmp/report.actual"

    # Root and some Windows filesystems do not enforce chmod denial. Say so,
    # while the package persistence suite always proves open_read_only denial.
    chmod a-w "$db"
    if [[ -w $db ]]; then
        echo "SKIPPED import_notes $backend file-permission denial: current user/filesystem can still write"
        chmod u+w "$db"
    else
        if "$@" import "$db" "$tmp/denied.json" >"$tmp/rejected.out" 2>"$tmp/rejected.err"; then
            echo "$backend wrote to an unwritable database" >&2; exit 1
        fi
        chmod u+w "$db"
        grep -Eq '^(readonly|cantopen):' "$tmp/rejected.err"
        "$@" report "$db" >"$tmp/report.actual"
        diff -u "$tmp/report.expected" "$tmp/report.actual"
        echo "ok import_notes $backend: file-permission denial"
    fi
    echo "ok import_notes $backend: strict and empty input, atomic writes, persisted report, lock contention, errors"
}

acceptance interpreter "$BEANSC" run "$ROOT/examples/import_notes/main.b" --
if [[ ${1:-} == --native ]]; then
    "$BEANSC" build "$ROOT/examples/import_notes/main.b" --locked --offline -o "$tmp/import_notes" >/dev/null
    acceptance native "$tmp/import_notes"
fi
