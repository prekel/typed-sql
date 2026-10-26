set -eu
ppx="$1"
source="$2"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
if PGHOST=/nonexistent/typed-sql-offline "$ppx" --impl "$source" -o "$test_dir/out.ml" 2> "$test_dir/error"; then
  echo 'quotation without embedded cache unexpectedly expanded' >&2
  exit 1
fi
grep -Fq 'no query cache is registered' "$test_dir/error"
