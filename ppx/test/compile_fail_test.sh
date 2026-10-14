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
