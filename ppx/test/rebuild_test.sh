set -eu
codegen="$1"
source_schema="$2"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

"$codegen" --target pgocaml-ppx "$source_schema" > "$test_dir/first.ml"
"$codegen" --target pgocaml-ppx "$source_schema" > "$test_dir/second.ml"
cmp "$test_dir/first.ml" "$test_dir/second.ml"

sed 's/"kind": "int"/"kind": "int64"/g; s/"name": "int4"/"name": "int8"/g' \
  "$source_schema" > "$test_dir/schema.json"
"$codegen" --target pgocaml-ppx "$test_dir/schema.json" > "$test_dir/updated.ml"
grep -Fq 'S.Int64' "$test_dir/updated.ml"
grep -Fq '"int8"' "$test_dir/updated.ml"
