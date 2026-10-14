set -eu
ppx="$1"
ocamlfind="$2"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

for fixture in compile_fail/*.ml; do
  expected="$(sed -n 's/^(\* expected: \(.*\) \*)$/\1/p' "$fixture")"
  if "$ppx" --typed-sql-schema schema.json --impl "$fixture" -o "$test_dir/fixture.ml" > "$test_dir/stdout" 2> "$test_dir/stderr"; then
    if "$ocamlfind" ocamlc -package base,pgocaml -c "$test_dir/fixture.ml" -o "$test_dir/fixture.cmo" > "$test_dir/stdout" 2> "$test_dir/stderr"; then
      echo "$fixture unexpectedly compiled" >&2
      exit 1
    fi
  fi
  if ! grep -Fq "$expected" "$test_dir/stderr"; then
    cat "$test_dir/stderr" >&2
    exit 1
  fi
done

printf '%s\n' 'let query conn = [%pgsql conn "SELECT id FROM people"]' > "$test_dir/query.ml"
if "$ppx" --impl "$test_dir/query.ml" -o "$test_dir/out.ml" 2> "$test_dir/error"; then
  echo 'missing schema argument unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'missing --typed-sql-schema PATH' "$test_dir/error"
if PGCUSTOM_CONVERTERS_CONFIG=unsupported.conf "$ppx" --typed-sql-schema schema.json --impl "$test_dir/query.ml" -o "$test_dir/out.ml" 2> "$test_dir/error"; then
  echo 'custom converter config unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'custom converter config is not supported yet' "$test_dir/error"
PGHOST=/nonexistent/typed-sql-offline "$ppx" --typed-sql-schema schema.json --impl "$test_dir/query.ml" -o "$test_dir/out.ml"

cat > "$test_dir/dml.ml" <<'OCAML'
open! Base

let insert conn tenant id name : unit =
  [%pgsql conn "INSERT INTO ppx_items (tenant, id, name) VALUES ($tenant, $id, $name)"]

let save conn tenant id name : int32 list =
  [%pgsql conn "INSERT INTO ppx_items (tenant, id, name) VALUES ($tenant, $id, $name) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.name RETURNING id"]

let update conn id note : string option list =
  [%pgsql conn "UPDATE ppx_items SET note = $?note WHERE id = $id RETURNING note"]

let delete conn id : unit =
  [%pgsql conn "DELETE FROM ppx_items WHERE id = $id"]
OCAML
PGHOST=/nonexistent/typed-sql-offline "$ppx" --typed-sql-schema schema.json --impl "$test_dir/dml.ml" -o "$test_dir/dml_generated.ml"
"$ocamlfind" ocamlc -package base,pgocaml -c "$test_dir/dml_generated.ml" -o "$test_dir/dml_generated.cmo"
