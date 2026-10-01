set -eu

codegen="$1"
fixture_generator="$2"
formatter="$3"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

"$fixture_generator" > "$test_dir/schema_fixture.json"
cmp schema_fixture.json "$test_dir/schema_fixture.json"
"$codegen" --type-rules schema_type_rules.json schema_fixture.json > "$test_dir/from_file.ml"
"$codegen" --type-rules schema_type_rules.json - < schema_fixture.json > "$test_dir/from_stdin.ml"
"$formatter" --root ../.. --name test/schema/generated_schema.ml --impl - \
  < "$test_dir/from_file.ml" > "$test_dir/formatted_from_file.ml"
"$formatter" --root ../.. --name test/schema/generated_schema.ml --impl - \
  < "$test_dir/from_stdin.ml" > "$test_dir/formatted_from_stdin.ml"
cmp generated_schema.ml "$test_dir/formatted_from_file.ml"
cmp generated_schema.ml "$test_dir/formatted_from_stdin.ml"

"$codegen" \
  --exclude-table public.advanced \
  --exclude-table 'public."USER PROFILE"' \
  --type-rules schema_type_rules.json \
  schema_fixture.json \
  > "$test_dir/filtered.ml"
if grep -Fq 'module Advanced = struct' "$test_dir/filtered.ml"; then
  echo 'excluded table was generated' >&2
  exit 1
fi
if grep -Fq 'Table.v_exn ~schema:"public" "USER PROFILE"' "$test_dir/filtered.ml"; then
  echo 'quoted excluded table was generated' >&2
  exit 1
fi
grep -Fq 'Table.v_exn ~schema:"public" "user-profile"' "$test_dir/filtered.ml"
grep -Fq 'Table.v_exn ~schema:"public" "user_profile"' "$test_dir/filtered.ml"
if grep -Fq 'module Type_public_mood = struct' "$test_dir/filtered.ml"; then
  echo 'type used only by an excluded table was generated' >&2
  exit 1
fi

"$codegen" --exclude-table public.parent schema_fixture.json > "$test_dir/no_match.ml" 2> "$test_dir/no_match.stderr" && {
  echo 'unknown table exclusion unexpectedly succeeded' >&2
  exit 1
}
grep -Fq 'excluded table not found: public.parent' "$test_dir/no_match.stderr"

"$codegen" --exclude-table public.parent - > "$test_dir/foreign_key.ml" <<'JSON'
{
  "version": 2,
  "tables": [
    {
      "schema": "public",
      "name": "parent",
      "columns": [
        { "name": "id", "db_type": { "kind": "int" }, "nullable": false, "default": null, "generated": false, "primary_key_position": null }
      ],
      "foreign_keys": [],
      "unique_constraints": []
    },
    {
      "schema": "public",
      "name": "child",
      "columns": [
        { "name": "parent_id", "db_type": { "kind": "int" }, "nullable": false, "default": null, "generated": false, "primary_key_position": null }
      ],
      "foreign_keys": [
        { "columns": ["parent_id"], "referenced_schema": "public", "referenced_table": "parent", "referenced_columns": ["id"] }
      ],
      "unique_constraints": []
    },
    {
      "schema": "archive",
      "name": "parent",
      "columns": [
        { "name": "id", "db_type": { "kind": "int" }, "nullable": false, "default": null, "generated": false, "primary_key_position": null }
      ],
      "foreign_keys": [],
      "unique_constraints": []
    }
  ]
}
JSON
if grep -Fq 'Table.v_exn ~schema:"public" "parent"' "$test_dir/foreign_key.ml"; then
  echo 'excluded parent table was generated' >&2
  exit 1
fi
grep -Fq '"parent_id"' "$test_dir/foreign_key.ml"
grep -Fq '"parent"' "$test_dir/foreign_key.ml"
grep -Fq 'Table.v_exn ~schema:"archive" "parent"' "$test_dir/foreign_key.ml"

"$codegen" --exclude-table '"schema.with.dot"."table""with.dot"' - \
  > "$test_dir/quoted_identifier.ml" <<'JSON'
{
  "version": 2,
  "tables": [
    {
      "schema": "schema.with.dot",
      "name": "table\"with.dot",
      "columns": [
        { "name": "id", "db_type": { "kind": "int" }, "nullable": false, "default": null, "generated": false, "primary_key_position": null }
      ],
      "foreign_keys": [],
      "unique_constraints": []
    }
  ]
}
JSON
if grep -Fq 'table\"with.dot' "$test_dir/quoted_identifier.ml"; then
  echo 'quoted schema and table identifiers were not parsed' >&2
  exit 1
fi

expect_failure() {
  expected_status="$1"
  expected="$2"
  shift 2
  actual_status=0
  if "$codegen" "$@" > "$test_dir/stdout" 2> "$test_dir/stderr"; then
    echo 'invalid CLI invocation succeeded' >&2
    exit 1
  else
    actual_status="$?"
  fi
  test "$actual_status" -eq "$expected_status"
  test ! -s "$test_dir/stdout"
  grep -Fq "$expected" "$test_dir/stderr"
}

expect_failure 1 'typed-sql-codegen:' "$test_dir/missing.json"
expect_failure 2 'Usage:'
expect_failure 2 'Usage:' schema_fixture.json extra
expect_failure 2 'Usage:' --exclude-table schema_fixture.json
expect_failure 2 'Usage:' --exclude-table 'public."unterminated' schema_fixture.json
expect_failure 1 'invalid JSON' - <<'JSON'
{
JSON
expect_failure 1 'unsupported snapshot version' - <<'JSON'
{"version": 3, "tables": []}
JSON
expect_failure 1 'table empty has no columns' - <<'JSON'
{"version":1,"tables":[{"schema":null,"name":"empty","columns":[],"foreign_keys":[],"unique_constraints":[]}]}
JSON
expect_failure 1 'unsupported type custom for items.value' - <<'JSON'
{"version":1,"tables":[{"schema":null,"name":"items","columns":[{"name":"value","db_type":{"kind":"unsupported","database_type":"custom"},"nullable":false,"default":null,"generated":false,"primary_key_position":null}],"foreign_keys":[],"unique_constraints":[]}]}
JSON
expect_failure 1 'typed-sql-codegen:' --type-rules "$test_dir/missing.json" schema_fixture.json
"$codegen" --help > "$test_dir/help"
grep -Fq 'Usage:' "$test_dir/help"
