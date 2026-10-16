#!/usr/bin/env bash
set -euo pipefail

mode="${1:-check}"
case "$mode" in
  prepare) cache_flag=--output ;;
  check) cache_flag=--cache ;;
  *) echo 'Usage: bash test/query-builder-survey/sqlx/cache.sh [prepare|check]' >&2; exit 2 ;;
esac

cd "$(dirname "$0")/../../.."
pg_config_command="${TYPED_SQL_PG_CONFIG:-pg_config}"
pg_bindir="$("$pg_config_command" --bindir)"
cache_workdir="$(mktemp -d /tmp/typed-sql-survey.XXXXXX)"
cleanup() {
  "$pg_bindir/pg_ctl" -D "$cache_workdir/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$cache_workdir"
}
trap cleanup EXIT
mkdir "$cache_workdir/socket"
"$pg_bindir/initdb" -D "$cache_workdir/data" --username=typed_sql_survey \
  --encoding=UTF8 --locale=C --auth-local=trust --no-instructions --no-sync >/dev/null
"$pg_bindir/pg_ctl" -D "$cache_workdir/data" \
  -o "-c listen_addresses='' -k $cache_workdir/socket -p 5432" \
  -l "$cache_workdir/server.log" -w start >/dev/null
export PGHOST="$cache_workdir/socket" PGPORT=5432 PGUSER=typed_sql_survey PGDATABASE=typed_sql_survey
"$pg_bindir/createdb" "$PGDATABASE"
"$pg_bindir/psql" -X -v ON_ERROR_STOP=1 -f test/query-builder-survey/sqlx/setup.sql >/dev/null
opam exec -- dune exec --root . ppx/bin/typed_sql_pgocaml_queries.exe -- \
  "$mode" "$cache_flag" test/query-builder-survey/sqlx/queries.json \
  test/query-builder-survey/sqlx/queries.ml
