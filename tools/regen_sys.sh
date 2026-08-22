#!/usr/bin/env bash
# Regenerates sys/sys.b from the vendored header and reports coverage:
# every public function in sqlite3.h is either bound, or accounted for in
# SKIPPED.md. Run after a vendor upgrade; commit the result.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BEANSC=${BEANSC:-$(command -v beansc)}

"$BEANSC" bindgen "$ROOT/vendor/sqlite3.h" -o "$ROOT/sys/sys.b" \
    --package sys --pub --allow-unsupported

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

grep -o '^SQLITE_API [a-zA-Z_0-9* ]*sqlite3_[a-z_0-9]*(' "$ROOT/vendor/sqlite3.h" \
    | grep -o 'sqlite3_[a-z_0-9]*(' | tr -d '(' | sort -u >"$tmp/header.txt"
grep -o 'fn sqlite3_[a-z_0-9]*' "$ROOT/sys/sys.b" \
    | sed 's/fn //' | sort -u >"$tmp/bound.txt"

bound=$(wc -l <"$tmp/bound.txt" | tr -d ' ')
total=$(wc -l <"$tmp/header.txt" | tr -d ' ')
echo "bound $bound of $total public functions; not bound:"
comm -23 "$tmp/header.txt" "$tmp/bound.txt" | sed 's/^/  /'
echo "check the list against SKIPPED.md — every name must be explained there"
