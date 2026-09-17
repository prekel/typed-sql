set -eu

ocamlfind="$1"
library_cmi="$2"
library_dir="$(dirname "$library_cmi")"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

for fixture in ./*.ml; do
  log="$temporary_dir/$fixture.log"
  output="$temporary_dir/$fixture.cmo"
  if "$ocamlfind" ocamlc -package base,ptime -I "$library_dir" -c "$fixture" -o "$output" >"$log" 2>&1; then
    echo "$fixture unexpectedly compiled" >&2
    exit 1
  fi
  expected_module=""
  case "$fixture" in
    ./private_ast_is_not_public.ml) expected_module="Query.Private" ;;
    ./public_binding_error_is_not_private.ml) expected_module="Typed_sql_private" ;;
    ./public_command_parameters_are_hidden.ml) expected_module="Compiled_command" ;;
    ./public_compiler_is_hidden.ml) expected_module="Compiler" ;;
    ./public_compiled_record_is_hidden.ml) expected_module="Compiled_query" ;;
    ./public_decoder_is_hidden.ml) expected_module="Compiled_query" ;;
    ./public_dialect_is_not_private.ml) expected_module="Typed_sql_private" ;;
    ./public_parameters_are_hidden.ml) expected_module="Compiled_query" ;;
    ./public_template_constructor_is_hidden.ml) expected_module="Template" ;;
    ./public_shape_is_hidden.ml) expected_module="Shape" ;;
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
