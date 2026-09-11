set -eu

ocamlfind="$1"
library_cmi="$2"
library_dir="$(dirname "$library_cmi")"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

for fixture in mismatched_expression.ml foreign_column.ml wrong_ordering.ml left_join_requires_nullable_column.ml select_is_required.ml update_requires_scope.ml delete_requires_scope.ml private_ast_is_not_public.ml public_identifier_is_abstract.ml public_expr_constructor_is_hidden.ml phantom_table_rows_are_distinct.ml public_projection_view_is_hidden.ml public_packed_type_is_hidden.ml public_template_constructor_is_hidden.ml public_codec_view_is_hidden.ml public_parameter_constructor_is_hidden.ml public_parameters_are_hidden.ml public_command_parameters_are_hidden.ml public_decoder_is_hidden.ml public_shape_is_hidden.ml public_compiled_record_is_hidden.ml; do
  log="$temporary_dir/$fixture.log"
  output="$temporary_dir/$fixture.cmo"
  if "$ocamlfind" ocamlc -package base -I "$library_dir" -c "$fixture" -o "$output" >"$log" 2>&1; then
    echo "$fixture unexpectedly compiled" >&2
    exit 1
  fi
  expected_module=""
  case "$fixture" in
    private_ast_is_not_public.ml) expected_module="Query.Private" ;;
    public_template_constructor_is_hidden.ml) expected_module="Template" ;;
    public_shape_is_hidden.ml) expected_module="Shape" ;;
  esac
  if [ -n "$expected_module" ]; then
    if ! grep -Fq "Unbound module $expected_module" "$log"; then
      cat "$log" >&2
      exit 1
    fi
  elif grep -q "Unbound module" "$log"; then
    cat "$log" >&2
    exit 1
  fi
done
