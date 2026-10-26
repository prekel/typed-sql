#!/usr/bin/env bash
set -euo pipefail
prepare="$1"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
pg_bin="$("${TYPED_SQL_PG_CONFIG:-pg_config}" --bindir)"
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -f ppx/test/setup.sql >/dev/null

"$prepare" prepare --output "$workdir/integration.json" \
  ppx/test/*postgresql_test.ml ppx/test/upstream_contract.ml
"$prepare" prepare --output "$workdir/offline.json" \
  ppx/test/*quotation_test.ml ppx/test/driver_queries.ml \
  ppx/test/compile_fail/*type.ml ppx/test/compile_fail/*parameter*.ml \
  ppx/test/compile_fail/*result.ml ppx/test/compile_fail/*object*.ml \
  ppx/test/compile_fail/*methods.ml ppx/test/compile_fail/srf_array_dimension.ml

python3 - "$workdir" <<'PYCOMPARE'
import json
import sys
import difflib
from pathlib import Path
for name in ['integration', 'offline']:
    actual = json.loads((Path(sys.argv[1]) / (name + '.json')).read_text())
    expected = json.loads((Path('ppx/test') / (name + '_queries.json')).read_text())
    actual.pop('role')
    expected.pop('role')
    if actual != expected:
        sys.stderr.writelines(difflib.unified_diff(
            json.dumps(expected, indent=2).splitlines(keepends=True),
            json.dumps(actual, indent=2).splitlines(keepends=True),
            fromfile=name + '/expected', tofile=name + '/actual'))
        raise SystemExit('prepared query metadata differs from the offline fixture')
PYCOMPARE
