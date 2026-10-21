#!/usr/bin/env bash
set -euo pipefail
prepare="$(realpath "$1")"
preprocessor="$(realpath "$2")"
embedded="$(realpath "$3")"
fixture="$(realpath "$4")"
cache="$(realpath "$5")"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export PGHOST=/nonexistent/typed-sql-offline

# Compiler preprocessing sees the same fragments, without needing a database.
"$embedded" --impl "$fixture" -o "$workdir/expanded.ml"
grep -Fq 'PGOCaml.int32_of_string' "$workdir/expanded.ml"

# A source name with shell metacharacters must stay one literal argument.
source_file="$workdir/queries ' \$(touch injected).ml"
cp "$cache" "$workdir/cache.json"
cp "$cache" "$workdir/original.json"

# Locate a collector failure after preprocessing, before any connection attempt.
printf '%s\n' 'let q dbh = [%pgsql dbh "execute" "SELECT 1"]' > "$source_file"
for output in text binary; do
  command="$(printf '%q' "$preprocessor") --impl"
  if [[ "$output" == binary ]]; then
    command="$(printf '%q' "$preprocessor") -dump-ast --impl"
  fi
  if "$prepare" prepare --output "$workdir/cache.json" --pp "$command" \
    "$source_file" 2> "$workdir/error"; then
    echo "$output preprocessing unexpectedly accepted an unsupported flag" >&2
    exit 1
  fi
  grep -Fq 'unsupported flag: execute' "$workdir/error"
  grep -Fq "$source_file" "$workdir/error"
  cmp "$workdir/cache.json" "$workdir/original.json"
done
test ! -e injected

# The binary AST keeps the original quotation line, despite removing fragments.
cat > "$workdir/location.ml" <<'OCAML'
let%concat header = "SELECT"


let q dbh = [%pgsql dbh "execute" [%concat header "1"]]
OCAML
if "$prepare" prepare --output "$workdir/cache.json" \
  --pp "$(printf '%q' "$preprocessor") -dump-ast --impl" \
  "$workdir/location.ml" 2> "$workdir/error"; then
  echo 'invalid preprocessed quotation unexpectedly collected' >&2
  exit 1
fi
grep -Fq 'location.ml", line 4' "$workdir/error"
grep -Fq 'unsupported flag: execute' "$workdir/error"

for action in prepare check; do
  cache_flag=--output
  if [[ "$action" == check ]]; then cache_flag=--cache; fi
  if "$prepare" "$action" "$cache_flag" "$workdir/cache.json" \
    --pp 'sh -c "exit 7"' "$fixture" 2> "$workdir/error"; then
    echo 'failed preprocessor unexpectedly succeeded' >&2
    exit 1
  fi
  grep -Fq 'exit code 7' "$workdir/error"
  grep -Fq "$fixture" "$workdir/error"
  cmp "$workdir/cache.json" "$workdir/original.json"
done

# An invalid preprocessing result also fails before database access.
malformed_pp="sh -c 'printf \"let =\"'"
if "$prepare" prepare --output "$workdir/cache.json" \
  --pp "$malformed_pp" "$fixture" 2> "$workdir/error"; then
  echo 'malformed preprocessor output unexpectedly parsed' >&2
  exit 1
fi
grep -Fq 'Syntax error' "$workdir/error"
cmp "$workdir/cache.json" "$workdir/original.json"

# A ppxlib driver may report errors inside a successful binary AST output.
printf '%s\n' 'let q dbh = [%pgsql dbh [%concat missing "WHERE id = 1"]]' \
  > "$workdir/fragment.ml"
if "$prepare" prepare --output "$workdir/cache.json" \
  --pp "$(printf '%q' "$preprocessor") -as-pp --impl" \
  "$workdir/fragment.ml" 2> "$workdir/error"; then
  echo 'embedded preprocessing error unexpectedly collected' >&2
  exit 1
fi
grep -Fq 'unknown fragment: missing' "$workdir/error"
grep -Fq 'fragment.ml' "$workdir/error"
cmp "$workdir/cache.json" "$workdir/original.json"

unknown_version_pp="sh -c 'printf Caml1999M999'"
if "$prepare" prepare --output "$workdir/cache.json" --pp "$unknown_version_pp" \
  "$fixture" 2> "$workdir/error"; then
  echo 'unknown binary AST version unexpectedly loaded' >&2
  exit 1
fi
grep -Fiq 'unknown version' "$workdir/error"
cmp "$workdir/cache.json" "$workdir/original.json"

printf '%s\n' 'val q : int' > "$workdir/interface.ml"
if "$prepare" prepare --output "$workdir/cache.json" \
  --pp "$(printf '%q' "$preprocessor") -dump-ast --intf" \
  "$workdir/interface.ml" 2> "$workdir/error"; then
  echo 'interface AST unexpectedly accepted as an implementation' >&2
  exit 1
fi
grep -Fq 'expected an implementation AST' "$workdir/error"
cmp "$workdir/cache.json" "$workdir/original.json"

if "$prepare" prepare --output "$workdir/cache.json" "$fixture" \
  2> "$workdir/error"; then
  echo 'unexpanded concat unexpectedly collected' >&2
  exit 1
fi
grep -Fq 'expected SQL literal' "$workdir/error"

if "$prepare" prepare --output "$workdir/cache.json" --pp cat --pp cat \
  "$fixture" 2> "$workdir/error"; then
  echo 'duplicate preprocessor unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'preprocessor specified more than once' "$workdir/error"

if "$prepare" prepare --output "$workdir/cache.json" --pp '' \
  "$fixture" 2> "$workdir/error"; then
  echo 'empty preprocessor unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'preprocessor command must not be empty' "$workdir/error"
