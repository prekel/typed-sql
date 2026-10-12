set -eu

check_platform="$1"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

sh "$check_platform" 64 63 > "$test_dir/stdout" 2> "$test_dir/stderr"
test ! -s "$test_dir/stdout"
test ! -s "$test_dir/stderr"

expect_rejection() {
  word_size="$1"
  int_size="$2"
  status=0
  sh "$check_platform" "$word_size" "$int_size" \
    > "$test_dir/stdout" 2> "$test_dir/stderr" || status="$?"
  test "$status" -eq 1
  test ! -s "$test_dir/stdout"
  echo "typed-sql requires 64-bit OCaml with 63-bit int (word_size=$word_size, int_size=$int_size)." \
    > "$test_dir/expected"
  cmp "$test_dir/expected" "$test_dir/stderr"
}

expect_rejection 32 31
expect_rejection 64 32
