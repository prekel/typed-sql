open! Base
open Typed_sql

let print_s sexp = Stdlib.print_endline (Sexp.to_string_hum sexp)

let mapped () =
  Db_type.map
    ~name:"upper_text"
    ~encode:(fun value ->
      if String.is_empty value then
        Error "empty value"
      else
        Ok (String.uppercase value))
    ~decode:(fun value -> Ok (String.lowercase value))
    Db_type.text
;;

let statement () =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters value = params.expr ~name:"label" (mapped ()) ~get:Fn.id in
    params.query_one (Query.select_one value))
;;

let%test "mapped codec value is shown after encoding" =
  match Statement.inspect ~dialect:Postgresql ~input:"Ada" (statement ()) with
  | Ok
      ( _
      , { parameters =
            [ { value = Some (Statement.Encoded "ADA"); db_type = "upper_text"; _ } ]
        ; _
        } ) -> true
  | Ok _ | Error _ -> false
;;

let%test "mapped codec error retains parameter context" =
  match Statement.inspect ~dialect:Postgresql ~input:"" (statement ()) with
  | Error
      (Statement.Codec_error
         { position = 1; name = Some "label"; message = "empty value" }) -> true
  | Ok _ | Error _ -> false
;;

let%test "inspect_exn raises a structured codec error" =
  match Statement.inspect_exn ~dialect:Postgresql ~input:"" (statement ()) with
  | exception
      Statement.Inspection_error
        (Statement.Codec_error { position = 1; name = Some "label"; _ }) -> true
  | _ -> false
;;

let%expect_test "codec inspection error has a structured sexp" =
  Statement.sexp_of_inspection_error
    (Statement.Codec_error { position = 1; name = Some "label"; message = "empty value" })
  |> print_s;
  [%expect {| (Codec_error (position 1) (name (label)) (message "empty value")) |}]
;;

let%test "mapped input parameter remains unknown without input" =
  match Statement.inspect ~dialect:Sqlite (statement ()) with
  | Ok
      ( _
      , { parameters =
            [ { name = Some "label"
              ; db_type = "upper_text"
              ; value = None
              ; dialect_type = None
              ; _
              }
            ]
        ; _
        } ) -> true
  | Ok _ | Error _ -> false
;;

let%test_module "mapped constants without input" =
  (module struct
    let constant ~dialect value =
      Statement.query_one ~dialect (Query.select_one (Expr.constant (mapped ()) value))
    ;;

    let%test "PostgreSQL constant uses the encoded value" =
      match
        Statement.inspect ~dialect:Postgresql (constant ~dialect:Dialect.portable "Ada")
      with
      | Ok
          ( _
          , { parameters =
                [ { name = None
                  ; db_type = "upper_text"
                  ; dialect_type = Some "text"
                  ; value = Some (Statement.Encoded "ADA")
                  ; _
                  }
                ]
            ; _
            } ) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "SQLite constant reports encoded storage" =
      match
        Statement.inspect ~dialect:Sqlite (constant ~dialect:Dialect.portable "Ada")
      with
      | Ok
          ( _
          , { parameters =
                [ { name = None
                  ; db_type = "upper_text"
                  ; dialect_type = Some "TEXT"
                  ; value = Some (Statement.Encoded "ADA")
                  ; _
                  }
                ]
            ; _
            } ) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "constant codec error retains its position and anonymous name" =
      match Statement.inspect ~dialect:Sqlite (constant ~dialect:Dialect.portable "") with
      | Error
          (Statement.Codec_error { position = 1; name = None; message = "empty value" })
        -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "inspect_exn raises the constant codec error" =
      match
        Statement.inspect_exn ~dialect:Sqlite (constant ~dialect:Dialect.portable "")
      with
      | exception
          Statement.Inspection_error
            (Statement.Codec_error { position = 1; name = None; message = "empty value" })
        -> true
      | _ -> false
    ;;

    let%test "dialect choice encodes only the selected branch" =
      let statement =
        Statement.choose_dialect
          ~postgresql:(constant ~dialect:Dialect.postgresql "")
          ~sqlite:(constant ~dialect:Dialect.sqlite "Ada")
      in
      match Statement.inspect ~dialect:Sqlite statement with
      | Ok (_, { parameters = [ { value = Some (Statement.Encoded "ADA"); _ } ]; _ }) ->
        true
      | Ok _ | Error _ -> false
    ;;
  end)
;;
