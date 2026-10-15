set -eu
codegen="$1"
source_schema="$2"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

"$codegen" --target pgocaml-ppx "$source_schema" > "$test_dir/from_file.ml"
"$codegen" --target pgocaml-ppx - < "$source_schema" > "$test_dir/from_stdin.ml"
cmp "$test_dir/from_file.ml" "$test_dir/from_stdin.ml"

"$codegen" "$source_schema" > "$test_dir/default.ml"
"$codegen" --target descriptors "$source_schema" > "$test_dir/explicit.ml"
cmp "$test_dir/default.ml" "$test_dir/explicit.ml"

if "$codegen" --target pgocaml-ppx --type-rules unused.json "$source_schema" \
  > "$test_dir/stdout" 2> "$test_dir/stderr"
then
  echo '--type-rules unexpectedly accepted for the PPX target' >&2
  exit 1
fi
grep -Fq 'only applies to descriptor generation' "$test_dir/stderr"
