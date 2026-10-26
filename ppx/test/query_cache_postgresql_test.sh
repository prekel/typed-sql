#!/usr/bin/env bash
set -euo pipefail
prepare="$1"
driver="$2"
embedded="$3"
example="$4"
build_dir="$5"
mixed_example="$6"
pg_bin="$("${TYPED_SQL_PG_CONFIG:-pg_config}" --bindir)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
fixture=ppx/test/query_cache/cache_queries.ml

"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -f ppx/test/query_cache/setup.sql >/dev/null
"$prepare" prepare --output "$workdir/cache.json" "$fixture"
cp "$workdir/cache.json" "$workdir/original.json"
"$prepare" check --cache "$workdir/cache.json" "$fixture"
# Describe must neither execute DML nor need values for its placeholders.
test "$("$pg_bin/psql" -Atqc 'SELECT count(*) FROM query_cache_test.people')" = 1
test "$("$pg_bin/psql" -Atqc 'SELECT note IS NULL FROM query_cache_test.people')" = t

compare_metadata() {
python3 - "$1" "$2" <<'PY'
import json
import sys
left, right = (json.load(open(path)) for path in sys.argv[1:])
left.pop("role")
right.pop("role")
if left != right:
    raise SystemExit("prepared query metadata differs from the offline fixture")
PY
}

compare_metadata "$workdir/cache.json" ppx/test/query_cache/queries.json

# OCaml binding names and source locations do not identify cached SQL.
sed 's/\$id/\$identifier/g' "$fixture" > "$workdir/renamed.ml"
"$prepare" check --cache "$workdir/cache.json" "$workdir/renamed.ml"
"$prepare" prepare --output "$workdir/cache.json" "$workdir/renamed.ml"
cmp "$workdir/cache.json" "$workdir/original.json"

printf '%s\n' 'let bad dbh = [%pgsql dbh "SELECT missing FROM query_cache_test.people"]' > "$workdir/invalid.ml"
if "$prepare" prepare --output "$workdir/cache.json" "$fixture" "$workdir/invalid.ml" 2> "$workdir/error"; then
  echo 'invalid SQL unexpectedly prepared' >&2
  exit 1
fi
grep -Fq 'invalid.ml' "$workdir/error"
cmp "$workdir/cache.json" "$workdir/original.json"

printf '%s\n' 'let extra dbh = [%pgsql dbh "SELECT 2::int4"]' > "$workdir/extra.ml"
if "$prepare" check --cache "$workdir/cache.json" "$fixture" "$workdir/extra.ml" 2> "$workdir/error"; then
  echo 'new query was not detected' >&2
  exit 1
fi
grep -Fq 'query cache is stale' "$workdir/error"
if "$prepare" check --cache "$workdir/cache.json" "$workdir/extra.ml" 2> "$workdir/error"; then
  echo 'removed queries were not detected' >&2
  exit 1
fi
if "$prepare" check --cache "$workdir/cache.json" --search-path query_cache_test "$fixture" 2> "$workdir/error"; then
  echo 'changed search path was not detected' >&2
  exit 1
fi
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -c 'ALTER TABLE query_cache_test.people ALTER COLUMN name DROP NOT NULL' >/dev/null
if "$prepare" check --cache "$workdir/cache.json" "$fixture" 2> "$workdir/error"; then
  echo 'changed database metadata was not detected' >&2
  exit 1
fi
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -c 'ALTER TABLE query_cache_test.people ALTER COLUMN name SET NOT NULL' >/dev/null

PGHOST=/nonexistent/typed-sql-offline "$prepare" codegen "$workdir/cache.json" > "$workdir/first.ml"
PGHOST=/nonexistent/typed-sql-offline "$prepare" codegen "$workdir/cache.json" > "$workdir/second.ml"
cmp "$workdir/first.ml" "$workdir/second.ml"

# The embedded production driver works from an unrelated directory, without JSON.
embedded="$(realpath "$embedded")"
fixture="$(realpath "$fixture")"
(cd "$workdir" && PGHOST=/nonexistent/typed-sql-offline "$embedded" --impl "$fixture" -o "$workdir/expanded.ml")
if PGHOST=/nonexistent/typed-sql-offline "$embedded" --impl "$workdir/extra.ml" -o "$workdir/out.ml" 2> "$workdir/error"; then
  echo 'missing cached query unexpectedly expanded' >&2
  exit 1
fi
grep -Fq 'run typed-sql-pgocaml-queries prepare' "$workdir/error"

"$example"

# Compile the shared Lwt/DSL transaction fixture with prepared metadata.
# The executable creates its table itself; prepare needs it only for Describe.
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -c \
  'CREATE TABLE public.ppx_mixed_items (id bigint PRIMARY KEY, name text NOT NULL, note text)' >/dev/null
"$prepare" prepare --output "$workdir/mixed.json" ppx/test/mixed_transaction_postgresql_test.ml
compare_metadata "$workdir/mixed.json" ppx/test/query_cache/mixed_queries.json
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -c 'DROP TABLE public.ppx_mixed_items' >/dev/null
"$mixed_example"

# Recreating native types changes their OIDs, but not the persisted metadata.
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -c 'DROP SCHEMA query_cache_test CASCADE' >/dev/null
"$pg_bin/psql" -X -v ON_ERROR_STOP=1 -f ppx/test/query_cache/setup.sql >/dev/null
"$prepare" prepare --output "$workdir/recreated.json" "$fixture"
cmp "$workdir/cache.json" "$workdir/recreated.json"

if [[ -n "${TYPED_SQL_UPSTREAM_PPX:-}" ]]; then
  "$prepare" prepare --output "$workdir/shared.json" \
    ppx/test/upstream_contract.ml \
    ppx/test/join_postgresql_test.ml \
    ppx/test/rich_postgresql_test.ml \
    ppx/test/compatibility_postgresql_test.ml \
    ppx/test/runtime_contract_postgresql_test.ml \
    ppx/test/srf_postgresql_test.ml \
    ppx/test/srf_select_postgresql_test.ml
  TYPED_SQL_TEST_QUERY_CACHE="$workdir/shared.json" \
    bash ppx/test/upstream_contract_test.sh \
    "$TYPED_SQL_UPSTREAM_PPX" "$driver" \
    "$build_dir/default/ppx/runtime/typed_sql_pgocaml_runtime.cma" \
    "$build_dir/default/ppx/runtime/.typed_sql_pgocaml_runtime.objs/byte/typed_sql_pgocaml_runtime.cmi"
fi
