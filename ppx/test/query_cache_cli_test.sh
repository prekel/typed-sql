#!/usr/bin/env bash
set -euo pipefail
prepare="$(realpath "$1")"
embedded="$(realpath "$2")"
mixed="$(realpath "$3")"
driver="$(realpath "$4")"
fixture="$(realpath "$5")"
source_file="$(realpath "$6")"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export PGHOST=/nonexistent/typed-sql-offline

"$prepare" codegen "$fixture" > "$workdir/first.ml"
"$prepare" codegen "$fixture" > "$workdir/second.ml"
cmp "$workdir/first.ml" "$workdir/second.ml"
python3 - "$fixture" "$workdir/changed.json" <<'PYMETADATA'
import json
import sys
from pathlib import Path

def replace(value):
    if isinstance(value, dict):
        return {key: replace(item) for key, item in value.items()}
    if isinstance(value, list):
        return [replace(item) for item in value]
    return 'pg_catalog.int8' if value == 'pg_catalog.int4' else value

data = replace(json.loads(Path(sys.argv[1]).read_text()))
data['types'].pop('pg_catalog.int4')
Path(sys.argv[2]).write_text(json.dumps(data))
PYMETADATA
"$prepare" codegen "$workdir/changed.json" > "$workdir/changed.ml"
if cmp -s "$workdir/first.ml" "$workdir/changed.ml"; then
  echo 'changed metadata did not change the generated module' >&2
  exit 1
fi
TYPED_SQL_TEST_QUERY_CACHE="$workdir/changed.json" "$driver" --impl "$source_file" -o "$workdir/changed_expansion.ml"
grep -Fq 'PGOCaml.int64_of_string' "$workdir/changed_expansion.ml"

# No relative JSON lookup, including when the IDE changes the working directory.
(cd "$workdir" && "$embedded" --impl "$source_file" -o "$workdir/expanded.ml")
if "$mixed" --impl "$source_file" -o "$workdir/mixed.ml" 2> "$workdir/error"; then
  echo 'multiple query caches unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'multiple query caches are registered' "$workdir/error"

printf '%s\n' 'let q dbh = [%pgsql dbh "SELECT 999::int4"]' > "$workdir/missing.ml"
if "$embedded" --impl "$workdir/missing.ml" -o "$workdir/missing_expansion.ml" 2> "$workdir/error"; then
  echo 'missing query unexpectedly expanded' >&2
  exit 1
fi
grep -Fq 'run typed-sql-pgocaml-queries prepare' "$workdir/error"

printf '%s\n' 'let q dbh = [%pgsql dbh "execute" "SELECT 1"]' > "$workdir/flags.ml"
if "$prepare" prepare --output "$workdir/cache.json" "$workdir/flags.ml" 2> "$workdir/error"; then
  echo 'unsupported flag unexpectedly collected' >&2
  exit 1
fi
grep -Fq 'unsupported flag: execute' "$workdir/error"
test ! -e "$workdir/cache.json"
