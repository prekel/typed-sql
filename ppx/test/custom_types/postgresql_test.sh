#!/usr/bin/env bash
set -euo pipefail
prepare="$1"
example="$2"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
fixture=ppx/test/custom_types/queries.ml
pg_bin="$("${TYPED_SQL_PG_CONFIG:-pg_config}" --bindir)"

"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -f ppx/test/custom_types/setup.sql >/dev/null
"$prepare" prepare --output "$workdir/queries.json" "$fixture"
"$prepare" check --cache "$workdir/queries.json" "$fixture"
python3 - "$workdir/queries.json" ppx/test/custom_types/queries.json <<'PY'
import json
import sys
actual, expected = (json.load(open(path)) for path in sys.argv[1:])
actual.pop('role')
expected.pop('role')
if actual != expected:
    raise SystemExit('custom type metadata differs from the offline fixture')
PY

"$example"
