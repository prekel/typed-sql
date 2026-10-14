set -eu
ppx="$1"
source_schema="$2"
project_dir="$(mktemp -d)"
trap 'rm -rf "$project_dir"' EXIT
cp "$ppx" "$project_dir/driver.exe"
cp "$source_schema" "$project_dir/schema.json"
printf '%s\n' '(lang dune 3.14)' > "$project_dir/dune-project"
cat > "$project_dir/dune" <<'DUNE'
(library
 (name downstream)
 (libraries base pgocaml)
 (preprocessor_deps schema.json)
 (preprocess
  (action
   (run %{dep:driver.exe} --typed-sql-schema %{dep:schema.json} --impl %{input-file}))))
DUNE
cat > "$project_dir/downstream.ml" <<'OCAML'
open! Base
let query conn : int32 list = [%pgsql conn "SELECT id FROM people"]
OCAML
PGHOST=/nonexistent/typed-sql-offline dune build --root "$project_dir" @all > "$project_dir/log" 2>&1 || {
  cat "$project_dir/log" >&2
  exit 1
}
cp "$project_dir/_build/default/downstream.pp.ml" "$project_dir/first.ml"
"$project_dir/driver.exe" --typed-sql-schema "$project_dir/schema.json" --impl "$project_dir/downstream.ml" -o "$project_dir/one.ml"
"$project_dir/driver.exe" --typed-sql-schema "$project_dir/schema.json" --impl "$project_dir/downstream.ml" -o "$project_dir/two.ml"
cmp "$project_dir/one.ml" "$project_dir/two.ml"
# The fixture has a single int4 column, id. Change both its native and portable types.
sed -i 's/"kind": "int"/"kind": "int64"/g; s/"name": "int4"/"name": "int8"/g' "$project_dir/schema.json"
if PGHOST=/nonexistent/typed-sql-offline dune build --root "$project_dir" @all > "$project_dir/log" 2>&1; then
  echo 'changing schema did not invalidate the OCaml result type' >&2
  exit 1
fi
grep -Fq 'int64' "$project_dir/log"
if cmp -s "$project_dir/first.ml" "$project_dir/_build/default/downstream.pp.ml"; then
  echo 'schema update did not regenerate the quotation' >&2
  exit 1
fi
sed -i 's/int32 list/int64 list/' "$project_dir/downstream.ml"
PGHOST=/nonexistent/typed-sql-offline dune build --root "$project_dir" @all > "$project_dir/log" 2>&1 || {
  cat "$project_dir/log" >&2
  exit 1
}
