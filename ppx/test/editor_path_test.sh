set -eu
ppx="$1"
source_schema="$2"
project_dir="$(mktemp -d)"
trap 'rm -rf "$project_dir"' EXIT
cp "$ppx" "$project_dir/driver.exe"
mkdir "$project_dir/app"
cp "$source_schema" "$project_dir/app/schema.json"
chmod u+w "$project_dir/app/schema.json"
cat > "$project_dir/app/query.ml" <<'OCAML'
open! Base
let query conn : int32 list = [%pgsql conn "SELECT id FROM people"]
OCAML
# Build-directory invocation with a relative source filename.
(
  cd "$project_dir"
  PGHOST=/nonexistent/typed-sql-offline ./driver.exe --typed-sql-schema schema.json \
    --impl app/query.ml -o "$project_dir/build.ml"
)
# Merlin invocation from the stanza directory with an absolute source filename.
(
  cd "$project_dir/app"
  PGHOST=/nonexistent/typed-sql-offline ../driver.exe --typed-sql-schema schema.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/editor.ml"
)
grep -Fq 'PGOCaml.int32_of_string' "$project_dir/build.ml"
grep -Fq 'PGOCaml.int32_of_string' "$project_dir/editor.ml"
(
  cd "$project_dir/app"
  ../driver.exe --typed-sql-schema "$project_dir/app/schema.json" \
    --impl "$project_dir/app/query.ml" -o "$project_dir/absolute.ml"
)
cmp "$project_dir/editor.ml" "$project_dir/absolute.ml"
# CWD fallback also retains the original build-root-relative argument.
(
  cd "$project_dir"
  ./driver.exe --typed-sql-schema app/schema.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/legacy.ml"
)
cmp "$project_dir/editor.ml" "$project_dir/legacy.ml"
# An existing but different CWD file must not shadow the source-relative one.
sed 's/"kind": "int"/"kind": "int64"/g; s/"name": "int4"/"name": "int8"/g' \
  "$project_dir/app/schema.json" > "$project_dir/schema.json"
(
  cd "$project_dir"
  ./driver.exe --typed-sql-schema schema.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/priority.ml"
)
cmp "$project_dir/editor.ml" "$project_dir/priority.ml"
# A readable invalid source snapshot must report its error, not use the fallback.
printf '%s\n' '{ invalid JSON' > "$project_dir/app/schema.json"
if (
  cd "$project_dir"
  ./driver.exe --typed-sql-schema schema.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/invalid.ml"
) 2> "$project_dir/error"; then
  echo 'invalid source snapshot was replaced by the CWD fallback' >&2
  exit 1
fi
grep -Fq 'invalid JSON' "$project_dir/error"
rm "$project_dir/app/schema.json"
# A missing source snapshot permits the CWD file to be read.
(
  cd "$project_dir"
  ./driver.exe --typed-sql-schema schema.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/fallback.ml"
)
grep -Fq 'PGOCaml.int64_of_string' "$project_dir/fallback.ml"
if (
  cd "$project_dir/app"
  ../driver.exe --typed-sql-schema missing.json \
    --impl "$project_dir/app/query.ml" -o "$project_dir/missing.ml"
) 2> "$project_dir/error"; then
  echo 'missing snapshot unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'cannot read schema snapshot' "$project_dir/error"
grep -Fq 'missing.json' "$project_dir/error"
