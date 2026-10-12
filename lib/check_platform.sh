set -eu

word_size="$1"
int_size="$2"

if [ "$word_size" != 64 ] || [ "$int_size" != 63 ]; then
  echo "typed-sql requires 64-bit OCaml with 63-bit int (word_size=$word_size, int_size=$int_size)." >&2
  exit 1
fi
