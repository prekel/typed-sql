#!/usr/bin/env bash
set -euo pipefail

pg_bindir="$(pg_config --bindir)"
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
if [[ "$server_version" -lt 180000 || "$server_version" -ge 190000 ]]; then
  echo "PostgreSQL 18 required, got $server_version" >&2
  exit 1
fi
echo "Testing against PostgreSQL $("$pg_bindir/psql" -Atqc 'SHOW server_version')"

"$pg_bindir/createdb" typed_sql_schema_fixture_test
PGDATABASE=typed_sql_schema_fixture_test \
  "$pg_bindir/psql" -X -v ON_ERROR_STOP=1 -f test/schema/schema_fixture.sql >/dev/null
PGDATABASE=typed_sql_schema_fixture_test \
  dune exec --root . caqti-lwt/typed_sql_schema_dump.exe \
  > "$workdir/live_schema_fixture.json"
diff -u test/schema/schema_fixture.json "$workdir/live_schema_fixture.json"

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
  dune exec --root . caqti-lwt/typed_sql_schema_dump.exe -- \
  --exclude-table public.advanced \
  --exclude-table 'public."USER PROFILE"' \
  --exclude-table public.filter_parent \
  > "$workdir/filtered_schema_fixture.json"
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
  dune exec --root . caqti-lwt/typed_sql_schema_dump.exe -- \
  --exclude-table public.missing > "$workdir/missing_table.json" 2> "$workdir/missing_table.stderr"; then
  echo 'missing table exclusion unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$workdir/missing_table.json"
grep -Fq 'excluded table not found: public.missing' "$workdir/missing_table.stderr"

dune exec --root . caqti-lwt/test/postgresql_test.exe
dune exec --root . caqti-lwt/test/mega_coverage_server_test.exe
dune exec --root . caqti-lwt/test/insert_select_test.exe -- --postgres
dune exec --root . pgocaml-lwt/test/postgresql_test.exe
if [[ "${TYPED_SQL_PREPARE_BENCH:-0}" == 1 ]]; then
  dune exec --root . pgocaml-lwt/test/prepare_bench.exe
fi
