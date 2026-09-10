open! Base

let parameter_fingerprints parameters =
  List.map parameters ~f:(fun (Db_type.Value (db_type, _)) -> Db_type.fingerprint db_type)
  |> String.concat ~sep:","
;;

let projection_fingerprints projection =
  Projection.types projection
  |> List.map ~f:(fun (Db_type.Pack db_type) -> Db_type.fingerprint db_type)
  |> String.concat ~sep:","
;;

let shape ~dialect ~template ~parameters ~projection =
  String.concat
    [ Dialect.to_string dialect
    ; ":"
    ; Template.shape_string template
    ; "|params:"
    ; parameter_fingerprints parameters
    ; "|result:"
    ; projection_fingerprints projection
    ]
  |> Shape.create
;;

let command_shape ~dialect ~template ~parameters =
  String.concat
    [ Dialect.to_string dialect
    ; ":"
    ; Template.shape_string template
    ; "|params:"
    ; parameter_fingerprints parameters
    ]
  |> Shape.create
;;

let compile ~dialect query =
  let ast = Result_query.ast query |> Normalizer.result_query in
  let open Result.Let_syntax in
  let%bind () = Validator.result_query ast in
  let%map lowered = Lower.result_query ~dialect ast in
  let template, parameters = Renderer.result_query lowered in
  let projection = Result_query.projection query in
  let shape = shape ~dialect ~template ~parameters ~projection in
  Compiled_query.create ~dialect ~template ~parameters ~projection ~shape
;;

let compile_command ~dialect command =
  let ast = Command.ast command |> Normalizer.command in
  let open Result.Let_syntax in
  let%bind () = Validator.command ast in
  let%map lowered = Lower.command ~dialect ast in
  let template, parameters = Renderer.command lowered in
  let shape = command_shape ~dialect ~template ~parameters in
  Compiled_command.create ~dialect ~template ~parameters ~shape
;;
