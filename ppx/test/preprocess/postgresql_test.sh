#!/usr/bin/env bash
set -euo pipefail
prepare="$(realpath "$1")"
preprocessor="$(realpath "$2")"
embedded="$(realpath "$3")"
example="$(realpath "$4")"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
fixture=ppx/test/preprocess/concat_queries.ml
literal=ppx/test/preprocess/literal_queries.ml

"$prepare" prepare --output "$workdir/literal.json" "$literal"
for output in text binary; do
  command="$(printf '%q' "$preprocessor") --impl"
  if [[ "$output" == binary ]]; then
    command="$(printf '%q' "$preprocessor") -dump-ast --impl"
  fi
  "$prepare" prepare --output "$workdir/$output.json" --pp "$command" "$fixture"
  cmp "$workdir/literal.json" "$workdir/$output.json"
  "$prepare" check --cache "$workdir/$output.json" --pp "$command" "$fixture"
done

# Changes to a shared fragment must invalidate every affected cached query.
sed 's/SELECT id, name/SELECT id, upper(name) AS name/' "$fixture" > "$workdir/changed.ml"
command="$(printf '%q' "$preprocessor") -dump-ast --impl"
if "$prepare" check --cache "$workdir/binary.json" --pp "$command" \
  "$workdir/changed.ml" 2> "$workdir/error"; then
  echo 'changed shared fragment was not detected' >&2
  exit 1
fi
grep -Fq 'query cache is stale' "$workdir/error"
cmp "$workdir/literal.json" "$workdir/binary.json"

# Server diagnostics retain the original location from the binary AST.
cat > "$workdir/invalid.ml" <<'OCAML'
let%concat header = "SELECT missing FROM query_cache_test.people"


let q dbh = [%pgsql dbh [%concat header "WHERE id = 1"]]
OCAML
if "$prepare" prepare --output "$workdir/binary.json" --pp "$command" \
  "$workdir/invalid.ml" 2> "$workdir/error"; then
  echo 'invalid SQL unexpectedly prepared after preprocessing' >&2
  exit 1
fi
grep -Fq 'invalid.ml", line 4' "$workdir/error"
grep -Fq 'missing' "$workdir/error"
cmp "$workdir/literal.json" "$workdir/binary.json"

# Source path quoting is exercised through a successful Prepare/Describe too.
source_file="$workdir/queries ' \$(touch injected).ml"
cat "$fixture" > "$source_file"
"$prepare" check --cache "$workdir/binary.json" --pp "$command" "$source_file"
test ! -e injected

PGHOST=/nonexistent/typed-sql-offline "$embedded" --impl "$fixture" \
  -o "$workdir/expanded.ml"
"$example"
