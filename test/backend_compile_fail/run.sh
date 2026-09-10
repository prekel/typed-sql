set -eu

ocamlfind="$1"
library_dir="$(dirname "$2")"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

for fixture in construct_view.ml construct_parameter.ml; do
  log="$temporary_dir/$fixture.log"
  if "$ocamlfind" ocamlc -package base -I "$library_dir" -c "$fixture" -o "$temporary_dir/$fixture.cmo" >"$log" 2>&1; then
    echo "$fixture unexpectedly compiled" >&2
    exit 1
  fi
  if ! grep -q "Cannot create values of the private type" "$log"; then
    cat "$log" >&2
    exit 1
  fi
done
