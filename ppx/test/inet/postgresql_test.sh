#!/usr/bin/env bash
set -euo pipefail
prepare="$1"
driver="$2"
example="$3"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
fixture=ppx/test/inet/queries.ml
pg_bin="$("${TYPED_SQL_PG_CONFIG:-pg_config}" --bindir)"

"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -f ppx/test/inet/setup.sql >/dev/null
"$prepare" prepare --output "$workdir/queries.json" "$fixture"
"$prepare" check --cache "$workdir/queries.json" "$fixture"
python3 - "$workdir/queries.json" ppx/test/inet/queries.json <<'PY'
import json
import sys
import difflib
actual, expected = (json.load(open(path)) for path in sys.argv[1:])
actual.pop('role')
expected.pop('role')
if actual != expected:
    sys.stderr.writelines(difflib.unified_diff(
        json.dumps(expected, indent=2).splitlines(keepends=True),
        json.dumps(actual, indent=2).splitlines(keepends=True),
        fromfile='expected', tofile='actual'))
    raise SystemExit('inet metadata differs from the offline fixture')
PY

PGHOST=/nonexistent/typed-sql-offline "$driver" --impl "$fixture" -null
"$example"
