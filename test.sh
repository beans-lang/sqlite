#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)

# A compiler built from a Beans checkout resolves the standard library and
# runtime relative to that checkout, so those runs happen from its root. An
# installed beansc carries its own, and runs from anywhere.
if [[ -z ${BEANS_ROOT:-} && -x "$ROOT/../../beans/build/beansc" ]]; then
    BEANS_ROOT=$(cd "$ROOT/../../beans" && pwd)
fi
if [[ -z ${BEANSC:-} ]]; then
    if [[ -n ${BEANS_ROOT:-} && -x "$BEANS_ROOT/build/beansc" ]]; then
        BEANSC="$BEANS_ROOT/build/beansc"
    else
        BEANSC=$(command -v beansc || true)
    fi
fi

# Windows launchers are .cmd files, which Git Bash can run but never
# marks executable — an existing file is enough there.
if [[ -z "$BEANSC" ]] || [[ ! -x "$BEANSC" && ! -f "$BEANSC" ]]; then
    echo "beansc not found: set BEANSC, set BEANS_ROOT, or put beansc on PATH" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [[ -n ${BEANS_ROOT:-} && "$BEANSC" == "$BEANS_ROOT/build/beansc" ]]; then
    cd "$BEANS_ROOT"
fi

# The persistence case writes its scratch file in the working directory and
# removes it itself; clear a leftover from an interrupted earlier run so the
# output stays deterministic.
rm -f beans_sqlite_persistence_test.db

cases=(smoke crud transactions lifecycle persistence)
for name in "${cases[@]}"; do
    "$BEANSC" run "$ROOT/tests/$name.b" >"$tmp/$name.interp"
    diff -u "$ROOT/tests/$name.out" "$tmp/$name.interp"
done

for target in x86_64-unknown-linux-gnu x86_64-pc-windows-gnu aarch64-unknown-linux-musl; do
    "$BEANSC" check "$ROOT/tests/smoke.b" --target "$target" >/dev/null
done

if [[ ${1:-} == "--native" ]]; then
    for name in "${cases[@]}"; do
        rm -f beans_sqlite_persistence_test.db
        "$BEANSC" build "$ROOT/tests/$name.b" -o "$tmp/$name.bin" >/dev/null
        "$tmp/$name.bin" >"$tmp/$name.native"
        diff -u "$ROOT/tests/$name.out" "$tmp/$name.native"
    done
fi

echo "ok sqlite: interpreter, target checks${1:+, native}"
