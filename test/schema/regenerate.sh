#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

generated_dir="$(mktemp -d)"
trap 'rm -rf "$generated_dir"' EXIT

opam exec -- dune exec --root . test/schema/schema_codegen_fixture_generator.exe \
  > "$generated_dir/schema_fixture.json"
opam exec -- dune exec --root . bin/typed_sql_codegen.exe -- \
  --type-rules test/schema/schema_type_rules.json \
  "$generated_dir/schema_fixture.json" \
  > "$generated_dir/generated_schema_raw.ml"
opam exec -- ocamlformat --root . --name test/schema/generated_schema.ml --impl - \
  < "$generated_dir/generated_schema_raw.ml" \
  > "$generated_dir/generated_schema.ml"

mv "$generated_dir/schema_fixture.json" test/schema/schema_fixture.json
mv "$generated_dir/generated_schema.ml" test/schema/generated_schema.ml
