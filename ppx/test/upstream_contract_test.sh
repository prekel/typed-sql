set -eu
upstream="$1"
offline="$2"
runtime_archive="$3"
runtime_interface="$4"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

"$upstream" --impl ppx/test/upstream_contract.ml -o "$workdir/upstream.ml"
PGHOST=/nonexistent/typed-sql-offline "$offline" \
  --impl ppx/test/upstream_contract.ml -o "$workdir/offline.ml"
ocamlfind ocamlc -package base,pgocaml -linkpkg "$workdir/upstream.ml" -o "$workdir/upstream.exe"
ocamlfind ocamlc -package base,pgocaml -linkpkg -I "$(dirname "$runtime_interface")" \
  "$runtime_archive" "$workdir/offline.ml" -o "$workdir/offline.exe"
"$workdir/upstream.exe" > "$workdir/upstream.out"
"$workdir/offline.exe" > "$workdir/offline.out"
diff -u "$workdir/upstream.out" "$workdir/offline.out"
