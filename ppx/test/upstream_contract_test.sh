set -eu
upstream="$1"
offline="$2"
runtime_archive="$3"
runtime_interface="$4"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for fixture in ppx/test/upstream_contract.ml ppx/test/join_postgresql_test.ml ppx/test/rich_postgresql_test.ml ppx/test/compatibility_postgresql_test.ml; do
  "$upstream" --impl "$fixture" -o "$workdir/upstream.ml"
  PGHOST=/nonexistent/typed-sql-offline "$offline" \
    --impl "$fixture" -o "$workdir/offline.ml"
  ocamlfind ocamlc -package base,pgocaml -linkpkg "$workdir/upstream.ml" -o "$workdir/upstream.exe"
  ocamlfind ocamlc -package base,pgocaml -linkpkg -I "$(dirname "$runtime_interface")" \
    "$runtime_archive" "$workdir/offline.ml" -o "$workdir/offline.exe"
  "$workdir/upstream.exe" > "$workdir/upstream.out"
  "$workdir/offline.exe" > "$workdir/offline.out"
  diff -u "$workdir/upstream.out" "$workdir/offline.out"
done
