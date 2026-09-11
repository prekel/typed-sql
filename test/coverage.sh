set -eu

cd "$(dirname "$0")/.."
coverage_dir="$PWD/_coverage"
coverage_data="$coverage_dir/data"
rm -rf "$coverage_data" "$coverage_dir/html"
mkdir -p "$coverage_data"
export BISECT_FILE="$coverage_data/bisect"

dune build --instrument-with bisect_ppx \
  test/.typed_sql_expect_tests.inline-tests/inline-test-runner.exe \
  test/property_test.exe \
  caqti-lwt/test/sqlite_test.exe
(
  cd test
  ../_build/default/test/.typed_sql_expect_tests.inline-tests/inline-test-runner.exe \
    inline-test-runner typed_sql_expect_tests -strict -source-tree-root ..
)
_build/default/test/property_test.exe
_build/default/caqti-lwt/test/sqlite_test.exe

summary="$(bisect-ppx-report summary --per-file --expect lib/ --coverage-path "$coverage_data")"
printf '%s\n' "$summary"
coverage="$(printf '%s\n' "$summary" | awk '/Project coverage/ { print $1 }')"
awk -v coverage="$coverage" 'BEGIN { if (coverage + 0 < 97.0) exit 1 }'
bisect-ppx-report html --expect lib/ --coverage-path "$coverage_data" -o "$coverage_dir/html"
