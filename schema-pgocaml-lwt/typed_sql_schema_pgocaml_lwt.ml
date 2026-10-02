open! Base

module Make (P : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t) = struct
  module Pgocaml = P

  type error =
    | Schema of string
    | Pgocaml_error of exn

  let error_to_string = function
    | Schema message -> "schema introspection failed: " ^ message
    | Pgocaml_error error -> Exn.to_string error
  ;;

  let error_of_exn error = Pgocaml_error error

  module S = Typed_sql_schema_backend.Schema_introspection

  let missing context = Error (context ^ " is NULL")

  let required context = function
    | Some value -> Ok value
    | None -> missing context
  ;;

  let integer context value =
    let open Result.Let_syntax in
    let%bind value = required context value in
    match Int.of_string_opt value with
    | Some number -> Ok number
    | None -> Error (context ^ " is not an integer: " ^ value)
  ;;

  let optional_integer context = function
    | None -> Ok None
    | Some value -> Result.map (integer context (Some value)) ~f:Option.some
  ;;

  let boolean context value =
    let open Result.Let_syntax in
    let%bind value = required context value in
    match value with
    | "t" | "true" -> Ok true
    | "f" | "false" -> Ok false
    | _ -> Error (context ^ " is not a boolean: " ^ value)
  ;;

  let wrong_width expected fields =
    Error
      ("expected "
       ^ Int.to_string expected
       ^ " fields, got "
       ^ Int.to_string (List.length fields))
  ;;

  let decode_column = function
    | [ schema; table; column; db_type; nullable; default; generated; pk ] ->
      let open Result.Let_syntax in
      let%bind table = required "table name" table in
      let%bind column = required "column name" column in
      let%bind db_type = required "column type OID" db_type in
      let%bind nullable = boolean "column nullable" nullable in
      let%bind generated = boolean "column generated" generated in
      let%map pk = optional_integer "primary-key position" pk in
      schema, table, column, (db_type, nullable, default, (generated, pk))
    | fields -> wrong_width 8 fields
  ;;

  let decode_foreign_key = function
    | [ schema
      ; table
      ; name
      ; position
      ; column
      ; referenced_schema
      ; referenced_table
      ; referenced_column
      ] ->
      let open Result.Let_syntax in
      let%bind table = required "foreign-key table" table in
      let%bind position = integer "foreign-key position" position in
      let%bind column = required "foreign-key column" column in
      let%map referenced_table = required "referenced table" referenced_table in
      ( schema
      , table
      , name
      , (position, column, referenced_schema, (referenced_table, referenced_column)) )
    | fields -> wrong_width 8 fields
  ;;

  let decode_unique = function
    | [ schema; table; name; position; column ] ->
      let open Result.Let_syntax in
      let%bind table = required "unique table" table in
      let%bind position = integer "unique position" position in
      let%map column = required "unique column" column in
      schema, table, name, (position, column)
    | fields -> wrong_width 5 fields
  ;;

  let decode_type = function
    | [ oid; schema; name; kind; base_oid; element_oid; labels ] ->
      let open Result.Let_syntax in
      let%bind oid = integer "type OID" oid in
      let%bind schema = required "type schema" schema in
      let%bind name = required "type name" name in
      let%bind kind = required "type kind" kind in
      let%bind base_oid = integer "base type OID" base_oid in
      let%bind element_oid = integer "element type OID" element_oid in
      let%map labels = required "enum labels" labels in
      oid, schema, name, (kind, base_oid, element_oid, labels)
    | fields -> wrong_width 7 fields
  ;;

  let fetch conn ~name ~decode sql =
    let open Lwt.Syntax in
    Lwt.catch
      (fun () ->
         let* () = Pgocaml.prepare conn ~query:sql () in
         let* rows = Pgocaml.execute conn ~params:[] () in
         Lwt.return
           (List.map rows ~f:decode
            |> Result.all
            |> Result.map_error ~f:(fun message -> Schema (name ^ ": " ^ message))))
      (fun exn -> Lwt.return (Error (error_of_exn exn)))
  ;;

  let introspect ~conn =
    let open Lwt.Syntax in
    let* types = fetch conn ~name:"types" ~decode:decode_type S.postgresql_types in
    match types with
    | Error error -> Lwt.return (Error error)
    | Ok types ->
      let* columns =
        fetch conn ~name:"columns" ~decode:decode_column S.postgresql_columns
      in
      (match columns with
       | Error error -> Lwt.return (Error error)
       | Ok columns ->
         let* foreign_keys =
           fetch
             conn
             ~name:"foreign keys"
             ~decode:decode_foreign_key
             S.postgresql_foreign_keys
         in
         (match foreign_keys with
          | Error error -> Lwt.return (Error error)
          | Ok foreign_keys ->
            let* uniques =
              fetch
                conn
                ~name:"unique constraints"
                ~decode:decode_unique
                S.postgresql_uniques
            in
            Lwt.return
              (let open Result.Let_syntax in
               let%bind uniques = uniques in
               S.make_schema
                 ~db_type:(S.postgresql_type_mapper types)
                 columns
                 foreign_keys
                 uniques
               |> Result.map_error ~f:(function S.Schema message -> Schema message))))
  ;;
end

include Make (Typed_sql_pgocaml_lwt.Pgocaml)
