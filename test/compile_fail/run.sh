set -eu

ocamlfind="$1"
library_cmi="$2"
library_dir="$(dirname "$library_cmi")"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

for fixture in mismatched_expression.ml foreign_column.ml wrong_ordering.ml left_join_requires_nullable_column.ml update_requires_scope.ml private_ast_is_not_public.ml; do
  log="$temporary_dir/$fixture.log"
  output="$temporary_dir/$fixture.cmo"
  if "$ocamlfind" ocamlc -package base -I "$library_dir" -c "$fixture" -o "$output" >"$log" 2>&1; then
    echo "$fixture unexpectedly compiled" >&2
    exit 1
  fi
  if [ "$fixture" != private_ast_is_not_public.ml ] && grep -q "Unbound module" "$log"; then
    cat "$log" >&2
    exit 1
  fi
done
