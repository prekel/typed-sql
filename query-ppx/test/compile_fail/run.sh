set -eu
ocamlfind="$1"
library_dir="$(dirname "$2")"
driver="$(realpath "$3")"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export PGHOST=/nonexistent/typed-sql-offline
for fixture in ./*.ml; do
  name="$(basename "$fixture" .ml)"
  if "$ocamlfind" ocamlc -package base,ptime -I "$library_dir" -ppx "$driver --as-ppx" -c "$fixture" -o "$workdir/$name.cmo" >"$workdir/log" 2>&1; then
    echo "$fixture unexpectedly compiled" >&2
    exit 1
  fi
  case "$name" in
    value | wrong_type | sqlite | statement_wrong_type | statement_expr | statement_sqlite | statement_input) expected='This expression has type' ;;
    statement_unused_input) expected='statement input pattern requires' ;;
    statement_missing_input) expected='statement parameters require an input pattern' ;;
    statement_object_command) expected='pgsql.statement.object requires returned rows' ;;
    statement_command_flags) expected='command quotation does not accept result flags' ;;
    command_as_query) expected='query quotation requires returned rows' ;;
    query_as_command) expected='pgsql.command requires DML' ;;
    missing) expected='query is absent from the cache' ;;
  esac
  if ! grep -Fq "$expected" "$workdir/log"; then
    cat "$workdir/log" >&2
    exit 1
  fi
done
