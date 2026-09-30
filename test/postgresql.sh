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

dune exec --root . caqti-lwt/test/postgresql_test.exe
dune exec --root . caqti-lwt/test/mega_coverage_server_test.exe
dune exec --root . caqti-lwt/test/insert_select_test.exe -- --postgres
dune exec --root . pgocaml-lwt/test/postgresql_test.exe
if [[ "${TYPED_SQL_PREPARE_BENCH:-0}" == 1 ]]; then
  dune exec --root . pgocaml-lwt/test/prepare_bench.exe
fi
