open! Base

let pp_parameter_fingerprints formatter parameters =
  Stdlib.Format.pp_print_list
    ~pp_sep:(fun formatter () -> Stdlib.Format.pp_print_char formatter ',')
    (fun formatter -> function
       | Ast.Value (Db_type.Value (db_type, _)) ->
         Stdlib.Format.pp_print_string formatter (Db_type.fingerprint db_type)
       | Ast.Slot { db_type = Db_type.Pack db_type; _ } ->
         Stdlib.Format.pp_print_string formatter (Db_type.fingerprint db_type))
    formatter
    parameters
;;

let pp_projection_fingerprints formatter projection =
  Projection.types projection
  |> Stdlib.Format.pp_print_list
       ~pp_sep:(fun formatter () -> Stdlib.Format.pp_print_char formatter ',')
       (fun formatter (Db_type.Pack db_type) ->
          Stdlib.Format.pp_print_string formatter (Db_type.fingerprint db_type))
       formatter
;;

let shape ~dialect ~template ~parameters ~projection =
  Stdlib.Format.asprintf
    "%s:%a|params:%a|result:%a"
    (Dialect.to_string dialect)
    Template.pp_shape
    template
    pp_parameter_fingerprints
    parameters
    pp_projection_fingerprints
    projection
  |> Shape.create
;;

let command_shape ~dialect ~template ~parameters =
  Stdlib.Format.asprintf
    "%s:%a|params:%a"
    (Dialect.to_string dialect)
    Template.pp_shape
    template
    pp_parameter_fingerprints
    parameters
  |> Shape.create
;;

type 'result query_plan =
  { dialect : Dialect.t
  ; template : Template.t
  ; parameters : Ast.parameter list
  ; projection : 'result Projection.erased
  ; shape : Shape.t
  }

type command_plan =
  { dialect : Dialect.t
  ; template : Template.t
  ; parameters : Ast.parameter list
  ; shape : Shape.t
  }

let compile_query_plan ~dialect query =
  let ast = Result_query.ast query |> Normalizer.result_query in
  let open Result.Let_syntax in
  let%bind () = Validator.result_query ast in
  let%bind () =
    if Result_query.requires_exactly_one query then (
      match
        ast
      with
      | Ast.Select (Ast.Simple select) when Aggregate_scope.exactly_one select -> Ok ()
      | Ast.Select (Ast.Compound _) | Ast.Returning _ | Ast.Select (Ast.Simple _) ->
        Error Compile_error.Exactly_one_query_not_proven)
    else
      Ok ()
  in
  let%map lowered = Lower.result_query ~dialect ast in
  let template, parameters = Renderer.result_query ~dialect lowered in
  let projection = Result_query.projection query in
  let shape = shape ~dialect ~template ~parameters ~projection in
  let projection = Projection.erase projection in
  { dialect; template; parameters; projection; shape }
;;

let compile_command_plan ~dialect command =
  let ast = Command.ast command |> Normalizer.command in
  let open Result.Let_syntax in
  let%bind () = Validator.command ast in
  let%map lowered = Lower.command ~dialect ast in
  let template, parameters = Renderer.command ~dialect lowered in
  let shape = command_shape ~dialect ~template ~parameters in
  { dialect; template; parameters; shape }
;;
