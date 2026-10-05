set -eu

cd "$(dirname "$0")/.."
mode="${1:-public}"
case "$mode" in
  public | all | mega) ;;
  *)
    printf 'usage: %s [public|all|mega]\n' "$0" >&2
    exit 2
    ;;
esac

coverage_dir="$PWD/_coverage/$mode"
coverage_data="$coverage_dir/data"
rm -rf "$coverage_data" "$coverage_dir/html"
mkdir -p "$coverage_data"
export BISECT_FILE="$coverage_data/bisect"

if [ "$mode" = mega ]; then
  targets="test/.typed_sql_mega_coverage_tests.inline-tests/inline-test-runner.exe"
else
  targets="
test/.typed_sql_expect_tests.inline-tests/inline-test-runner.exe
test/.typed_sql_let_syntax_tests.inline-tests/inline-test-runner.exe
test/.typed_sql_statement_inspection_codec_tests.inline-tests/inline-test-runner.exe
test/schema/.typed_sql_schema_expect_tests.inline-tests/inline-test-runner.exe
test/property_test.exe
caqti-lwt/test/sqlite_test.exe
caqti-lwt/schema/test/sqlite_schema_test.exe
test/schema/generated_schema_downstream_test.exe
"
fi
if [ "$mode" = all ]; then
  targets="$targets
test/.typed_sql_mega_coverage_tests.inline-tests/inline-test-runner.exe
test/.typed_sql_backend_expect_tests.inline-tests/inline-test-runner.exe
test/.typed_sql_private_expect_tests.inline-tests/inline-test-runner.exe
"
fi

# Intentional word splitting: every line above is one dune target.
# shellcheck disable=SC2086
dune build --instrument-with bisect_ppx $targets
if [ "$mode" = mega ]; then
  (
    cd test
    ../_build/default/test/.typed_sql_mega_coverage_tests.inline-tests/inline-test-runner.exe \
      inline-test-runner typed_sql_mega_coverage_tests -strict -source-tree-root ..
  )
else
  (
    cd test
    ../_build/default/test/.typed_sql_expect_tests.inline-tests/inline-test-runner.exe \
      inline-test-runner typed_sql_expect_tests -strict -source-tree-root ..
    ../_build/default/test/.typed_sql_let_syntax_tests.inline-tests/inline-test-runner.exe \
      inline-test-runner typed_sql_let_syntax_tests -strict -source-tree-root ..
    ../_build/default/test/.typed_sql_statement_inspection_codec_tests.inline-tests/inline-test-runner.exe \
      inline-test-runner typed_sql_statement_inspection_codec_tests -strict -source-tree-root ..
  )
  (
    cd test/schema
    ../../_build/default/test/schema/.typed_sql_schema_expect_tests.inline-tests/inline-test-runner.exe \
      inline-test-runner typed_sql_schema_expect_tests -strict -source-tree-root ../..
  )
  _build/default/test/property_test.exe
  _build/default/caqti-lwt/test/sqlite_test.exe
  _build/default/caqti-lwt/schema/test/sqlite_schema_test.exe
  _build/default/test/schema/generated_schema_downstream_test.exe

  if [ "$mode" = all ]; then
    (
      cd test
      ../_build/default/test/.typed_sql_mega_coverage_tests.inline-tests/inline-test-runner.exe \
        inline-test-runner typed_sql_mega_coverage_tests -strict -source-tree-root ..
      ../_build/default/test/.typed_sql_backend_expect_tests.inline-tests/inline-test-runner.exe \
        inline-test-runner typed_sql_backend_expect_tests -strict -source-tree-root ..
      ../_build/default/test/.typed_sql_private_expect_tests.inline-tests/inline-test-runner.exe \
        inline-test-runner typed_sql_private_expect_tests -strict -source-tree-root ..
    )
  fi
fi

summary="$(bisect-ppx-report summary --per-file --expect lib/ --coverage-path "$coverage_data")"
printf '%s\n' "$summary"
coverage="$(printf '%s\n' "$summary" | awk '/Project coverage/ { print $1 }')"
bisect-ppx-report html --expect lib/ --coverage-path "$coverage_data" -o "$coverage_dir/html"
case "$mode" in
  public) threshold=96.5 ;;
  all) threshold=99.0 ;;
  mega)
    printf 'Mega lib coverage: %s%%\n' "$coverage"
    threshold=67.0
    ;;
esac
awk -v coverage="$coverage" -v threshold="$threshold" \
  'BEGIN { if (coverage + 0 < threshold) exit 1 }'
