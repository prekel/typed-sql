#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
case "$mode" in
  all | mega-coverage) ;;
  *)
    printf 'usage: %s [all|mega-coverage]\n' "$0" >&2
    exit 2
    ;;
esac

pg_config_command="${TYPED_SQL_PG_CONFIG:-pg_config}"
pg_bindir="$("$pg_config_command" --bindir)"
workdir="$(mktemp -d /tmp/typed-sql-pg.XXXXXX)"
socket_dir="$workdir/socket"
data_dir="$workdir/data"
mkdir "$socket_dir"

cleanup() {
  "$pg_bindir/pg_ctl" -D "$data_dir" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$workdir"
}
trap cleanup EXIT

"$pg_bindir/initdb" -D "$data_dir" --encoding=UTF8 --locale=C \
  --auth-local=trust --no-instructions --no-sync >/dev/null
"$pg_bindir/pg_ctl" -D "$data_dir" \
  -o "-c listen_addresses='' -k $socket_dir -p 5432" \
  -l "$workdir/server.log" -w start >/dev/null

export PGHOST="$socket_dir"
export PGPORT=5432
export PGUSER="$(id -un)"
export PGDATABASE=typed_sql_test
"$pg_bindir/createdb" "$PGDATABASE"

server_version="$("$pg_bindir/psql" -Atqc 'SHOW server_version_num')"
if [[ "$server_version" -lt 150000 || "$server_version" -ge 190000 ]]; then
  echo "PostgreSQL 15-18 required, got $server_version" >&2
  exit 1
fi
echo "Testing against PostgreSQL $("$pg_bindir/psql" -Atqc 'SHOW server_version')"

if [[ "$mode" == mega-coverage ]]; then
  if [[ "$server_version" -lt 170000 ]]; then
    echo "Mega coverage requires PostgreSQL 17-18, got $server_version" >&2
    exit 1
  fi
  # Run the instrumented executable built by coverage.sh without rebuilding it.
  build_dir="${DUNE_BUILD_DIR:-_build}"
  "$build_dir/default/caqti-lwt/test/mega_coverage_server_test.exe"
  exit 0
fi

"$pg_bindir/createdb" typed_sql_schema_fixture_test
PGDATABASE=typed_sql_schema_fixture_test \
  "$pg_bindir/psql" -X -v ON_ERROR_STOP=1 -f test/schema/schema_fixture.sql >/dev/null
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . caqti-lwt/schema/typed_sql_schema_dump.exe \
  > "$workdir/live_schema_fixture.json"
diff -u test/schema/schema_fixture.json "$workdir/live_schema_fixture.json"
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe \
  > "$workdir/live_pgocaml_schema_fixture.json"
diff -u "$workdir/live_schema_fixture.json" "$workdir/live_pgocaml_schema_fixture.json"
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe -- \
  postgresql:///typed_sql_schema_fixture_test \
  > "$workdir/live_pgocaml_uri_schema_fixture.json"
diff -u "$workdir/live_schema_fixture.json" "$workdir/live_pgocaml_uri_schema_fixture.json"
PGHOST=/nonexistent/typed-sql-uri-host-override PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe -- \
  "postgresql:///typed_sql_schema_fixture_test?host=$socket_dir" \
  > "$workdir/live_pgocaml_socket_uri_schema_fixture.json"
diff -u "$workdir/live_schema_fixture.json" "$workdir/live_pgocaml_socket_uri_schema_fixture.json"
if PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe -- \
  'postgresql:///?sslmode=require' > "$workdir/unsupported_uri.json" 2> "$workdir/unsupported_uri.stderr"; then
  echo 'PGOCaml dump accepted an unsupported URI parameter' >&2
  exit 1
fi
test ! -s "$workdir/unsupported_uri.json"
grep -Fq 'unsupported URI parameter: sslmode' "$workdir/unsupported_uri.stderr"

PGDATABASE=typed_sql_schema_fixture_test \
  "$pg_bindir/psql" -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE SCHEMA archive;
CREATE TABLE public.filter_parent (id bigint PRIMARY KEY);
CREATE TABLE public.filter_child (
  parent_id bigint REFERENCES public.filter_parent (id)
);
CREATE TABLE archive.filter_parent (id bigint PRIMARY KEY);
SQL
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . caqti-lwt/schema/typed_sql_schema_dump.exe -- \
  --exclude-table public.advanced \
  --exclude-table 'public."USER PROFILE"' \
  --exclude-table public.filter_parent \
  > "$workdir/filtered_schema_fixture.json"
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe -- \
  --exclude-table public.advanced \
  --exclude-table 'public."USER PROFILE"' \
  --exclude-table public.filter_parent \
  > "$workdir/filtered_pgocaml_schema_fixture.json"
diff -u "$workdir/filtered_schema_fixture.json" "$workdir/filtered_pgocaml_schema_fixture.json"
if grep -Fq '"name": "advanced"' "$workdir/filtered_schema_fixture.json"; then
  echo 'dump included an excluded table' >&2
  exit 1
fi
if grep -Fq '"name": "USER PROFILE"' "$workdir/filtered_schema_fixture.json"; then
  echo 'dump included the quoted excluded table' >&2
  exit 1
fi
grep -A1 -F '"schema": "archive"' "$workdir/filtered_schema_fixture.json" \
  | grep -Fq '"name": "filter_parent"'
grep -Fq '"name": "filter_child"' "$workdir/filtered_schema_fixture.json"
grep -Fq '"referenced_table": "filter_parent"' "$workdir/filtered_schema_fixture.json"
if PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . caqti-lwt/schema/typed_sql_schema_dump.exe -- \
  --exclude-table public.missing > "$workdir/missing_table.json" 2> "$workdir/missing_table.stderr"; then
  echo 'missing table exclusion unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$workdir/missing_table.json"
grep -Fq 'excluded table not found: public.missing' "$workdir/missing_table.stderr"
if PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe -- \
  --exclude-table public.missing > "$workdir/missing_pgocaml_table.json" 2> "$workdir/missing_pgocaml_table.stderr"; then
  echo 'PGOCaml dump accepted a missing table exclusion' >&2
  exit 1
fi
test ! -s "$workdir/missing_pgocaml_table.json"
grep -Fq 'excluded table not found: public.missing' "$workdir/missing_pgocaml_table.stderr"

PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . caqti-lwt/schema/test/postgresql_schema_test.exe
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . schema-pgocaml-lwt/test/postgresql_schema_test.exe
dune exec --root . caqti-lwt/test/postgresql_test.exe
TYPED_SQL_PG_EXPECT=1 dune build --root . @runtest-typed_sql_postgresql_expect_tests
dune exec --root . caqti-lwt/test/insert_select_test.exe -- --postgres
dune exec --root . pgocaml-lwt/test/postgresql_test.exe
"$pg_bindir/createdb" typed_sql_ppx_test
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/dml_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/extended_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/join_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/rich_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/literal_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/compatibility_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/srf_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/srf_select_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/runtime_contract_postgresql_test.exe
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/test/mixed_transaction_postgresql_test.exe
if [[ -n "${TYPED_SQL_UPSTREAM_PPX:-}" ]]; then
  dune build --root . ppx/test/ppx_driver.exe ppx/runtime/typed_sql_pgocaml_runtime.cma
  build_dir="${DUNE_BUILD_DIR:-_build}"
  PGDATABASE=typed_sql_ppx_test bash ppx/test/upstream_contract_test.sh \
    "$TYPED_SQL_UPSTREAM_PPX" \
    "$build_dir/default/ppx/test/ppx_driver.exe" \
    "$build_dir/default/ppx/runtime/typed_sql_pgocaml_runtime.cma" \
    "$build_dir/default/ppx/runtime/.typed_sql_pgocaml_runtime.objs/byte/typed_sql_pgocaml_runtime.cmi"
fi
dune build --root . ppx/bin/typed_sql_pgocaml_queries.exe ppx/test/cache_driver.exe \
  ppx/test/query_cache/embedded_driver.exe ppx/test/query_cache/main.exe \
  ppx/test/query_cache/mixed_transaction_postgresql_test.exe \
  ppx/test/preprocess/driver.exe ppx/test/preprocess/embedded_driver.exe \
  ppx/test/preprocess/postgresql_test.exe \
  ppx/runtime/typed_sql_pgocaml_runtime.cma
build_dir="${DUNE_BUILD_DIR:-_build}"
PGDATABASE=typed_sql_ppx_test bash ppx/test/query_cache_postgresql_test.sh \
  "$build_dir/default/ppx/bin/typed_sql_pgocaml_queries.exe" \
  "$build_dir/default/ppx/test/cache_driver.exe" \
  "$build_dir/default/ppx/test/query_cache/embedded_driver.exe" \
  "$build_dir/default/ppx/test/query_cache/main.exe" "$build_dir" \
  "$build_dir/default/ppx/test/query_cache/mixed_transaction_postgresql_test.exe"
PGDATABASE=typed_sql_ppx_test bash ppx/test/preprocess/postgresql_test.sh \
  "$build_dir/default/ppx/bin/typed_sql_pgocaml_queries.exe" \
  "$build_dir/default/ppx/test/preprocess/driver.exe" \
  "$build_dir/default/ppx/test/preprocess/embedded_driver.exe" \
  "$build_dir/default/ppx/test/preprocess/postgresql_test.exe"
PGDATABASE=typed_sql_ppx_test dune exec --root . caqti-lwt/schema/typed_sql_schema_dump.exe > "$workdir/ppx_caqti_schema.json"
PGDATABASE=typed_sql_ppx_test dune exec --root . schema-pgocaml-lwt/typed_sql_pgocaml_schema_dump.exe > "$workdir/ppx_pgocaml_schema.json"
diff -u "$workdir/ppx_caqti_schema.json" "$workdir/ppx_pgocaml_schema.json"
# The shared grouping fixture exercises immediate and deferrable primary keys.
grep -Fq '"postgresql_primary_key_deferrable": false' "$workdir/ppx_caqti_schema.json"
grep -Fq '"postgresql_primary_key_deferrable": true' "$workdir/ppx_caqti_schema.json"
# The typmod fixture has varchar(10), numeric(8,2), and interval DAY TO SECOND(3).
grep -Fq '"postgresql_type_modifier": 14' "$workdir/ppx_caqti_schema.json"
grep -Fq '"postgresql_type_modifier": 524294' "$workdir/ppx_caqti_schema.json"
grep -Fq '"postgresql_type_modifier": 470286339' "$workdir/ppx_caqti_schema.json"
grep -Fq '"name": "int2"' "$workdir/ppx_caqti_schema.json"
grep -Fq '"name": "int4"' "$workdir/ppx_caqti_schema.json"
if [[ "$server_version" -ge 170000 ]]; then
  # The mega query includes MERGE inside WITH, which requires PostgreSQL 17+.
  dune exec --root . caqti-lwt/test/mega_coverage_server_test.exe
  dune exec --root . caqti-lwt/test/merge_test.exe
  dune exec --root . pgocaml-lwt/test/merge_test.exe
else
  echo "Skipping MERGE and mega-query integration tests: PostgreSQL 17+ required, got $server_version"
fi
if [[ "${TYPED_SQL_PREPARE_BENCH:-0}" == 1 ]]; then
  dune exec --root . pgocaml-lwt/test/prepare_bench.exe
fi

# Driver-independent cache quotations execute the same Statements through both adapters.
PGDATABASE=typed_sql_ppx_test "$pg_bindir/psql" -X -v ON_ERROR_STOP=1 \
  -f query-ppx/test/setup.sql >/dev/null
PGDATABASE=typed_sql_ppx_test dune exec --root . ppx/bin/typed_sql_pgocaml_queries.exe -- \
  prepare --output "$workdir/query-ppx.json" query-ppx/test/queries.ml
python3 - "$workdir/query-ppx.json" query-ppx/test/queries.json <<'PYCOMPARE'
import json, sys
actual, expected = (json.load(open(path)) for path in sys.argv[1:])
actual.pop("role")
expected.pop("role")
if actual != expected:
    raise SystemExit("typed-sql-ppx metadata differs from the fixture")
PYCOMPARE
PGDATABASE=typed_sql_ppx_test dune exec --root . query-ppx/test/postgresql_test.exe
