open! Base
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id person = Expr.column person id_column
  let name person = Expr.column person name_column
end

type input =
  { id : int64
  ; name : string
  }

let lookup =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters id = params.column Person.id_column ~get:(fun input -> input.id)
    and name = params.column Person.name_column ~get:(fun input -> input.name) in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person ->
          Person.id person
          =. id
          &&. (Person.id person >=. id)
          &&. (Person.name person =. name))
        |> select (fun person -> Projection.expr (Person.name person))))
;;

let input = { id = 7L; name = "O'Reilly\\staff" }

let%expect_test "PostgreSQL debug SQL substitutes each slot and escapes text" =
  Statement.debug_sql_exn ~dialect:Postgresql ~input lookup |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name"
    FROM "people" AS t0
    WHERE
      (
        (t0."id" = CAST(E'7' AS bigint))
        AND (t0."id" >= CAST(E'7' AS bigint))
        AND (t0."name" = CAST(E'O''Reilly\\staff' AS text))
      );
    |}]
;;

let%expect_test "SQLite debug SQL substitutes each slot and escapes text" =
  Statement.debug_sql_exn ~dialect:Sqlite ~input lookup |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name"
    FROM "people" AS t0
    WHERE
      (
        (t0."id" = 7)
        AND (t0."id" >= 7)
        AND (t0."name" = 'O''Reilly\staff')
      );
    |}]
;;

let insert_person =
  Statement.command
    ~dialect:Dialect.portable
    Insert.(
      into Person.table
      |> set Person.id_column 7L
      |> set Person.name_column "Ada"
      |> command)
;;

let%expect_test "PostgreSQL command is copyable" =
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() insert_person
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "people" (
      "id",
      "name"
    )
    VALUES
      (CAST(E'7' AS bigint), CAST(E'Ada' AS text));
    |}]
;;

let%expect_test "SQLite command is copyable" =
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() insert_person |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "people" (
      "id",
      "name"
    )
    VALUES
      (7, 'Ada');
    |}]
;;

let constant ~dialect db_type value =
  Statement.query_one ~dialect (Query.select_one (Expr.constant db_type value))
;;

let%expect_test "PostgreSQL NULL preserves its SQL type" =
  let statement =
    constant ~dialect:Dialect.postgresql (Db_type.option Db_type.int64) None
  in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(NULL AS bigint);
    |}]
;;

let%expect_test "SQLite NULL remains NULL" =
  let statement = constant ~dialect:Dialect.sqlite (Db_type.option Db_type.int64) None in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      NULL;
    |}]
;;

let%expect_test "PostgreSQL array keeps its element type" =
  let db_type = Db_type.Postgresql.array_list Db_type.int64 in
  let statement = constant ~dialect:Dialect.postgresql db_type [ 1L; 2L ] in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'{"1","2"}' AS bigint[]);
    |}]
;;

let%expect_test "PostgreSQL named type keeps its descriptor" =
  let db_type =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "person_name")
      Db_type.text
  in
  let statement = constant ~dialect:Dialect.postgresql db_type "Ada" in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'Ada' AS "public"."person_name");
    |}]
;;

let%expect_test "PostgreSQL nullable array retains its type" =
  let db_type = Db_type.option (Db_type.Postgresql.array_list Db_type.int64) in
  let statement = constant ~dialect:Dialect.postgresql db_type None in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(NULL AS bigint[]);
    |}]
;;

let%expect_test "PostgreSQL array keeps bounds and NULL elements" =
  let value =
    Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 0 ] ~elements:[ Some 1L; None ]
    |> Result.ok_or_failwith
  in
  let statement =
    constant ~dialect:Dialect.postgresql (Db_type.Postgresql.array Db_type.int64) value
  in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'[0:1]={"1",NULL}' AS bigint[]);
    |}]
;;

let%expect_test "PostgreSQL text escapes control characters" =
  let statement =
    constant
      ~dialect:Dialect.postgresql
      Db_type.text
      "line\nreturn\rtab\tvertical\011del\127"
  in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'line\nreturn\rtab\tvertical\013del\177' AS text);
    |}]
;;

let%expect_test "PostgreSQL finite float retains its type" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.float 1.5 in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'1.5' AS double precision);
    |}]
;;

let%expect_test "PostgreSQL negative zero keeps its sign and type" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.float (-0.0) in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'-0' AS double precision);
    |}]
;;

let%expect_test "PostgreSQL positive infinity has a castable spelling" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.float Stdlib.infinity in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'Infinity' AS double precision);
    |}]
;;

let%expect_test "PostgreSQL negative infinity has a castable spelling" =
  let statement =
    constant ~dialect:Dialect.postgresql Db_type.float Stdlib.neg_infinity
  in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'-Infinity' AS double precision);
    |}]
;;

let%expect_test "PostgreSQL NaN has a castable spelling" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.float Stdlib.nan in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'NaN' AS double precision);
    |}]
;;

let%expect_test "SQLite BLOB uses a hex literal" =
  let statement =
    constant ~dialect:Dialect.sqlite Db_type.bytes (Bytes.of_string "A\000B")
  in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      X'410042';
    |}]
;;

let%expect_test "SQLite text with NUL uses a text cast" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.text "A\000B" in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(X'410042' AS TEXT);
    |}]
;;

let%expect_test "SQLite text with DEL uses a text cast" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.text "A\127B" in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(X'417f42' AS TEXT);
    |}]
;;

let%expect_test "SQLite whole-valued float keeps REAL storage" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.float 1.0 in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      1.0;
    |}]
;;

let%expect_test "SQLite fractional float keeps REAL storage" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.float 0.5 in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      0.5;
    |}]
;;

let%expect_test "SQLite scientific float keeps REAL storage" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.float 1e100 in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      1e+100;
    |}]
;;

let%expect_test "SQLite minimum int64 stays an INTEGER" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.int64 Int64.min_value in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST('-9223372036854775808' AS INTEGER);
    |}]
;;

let%expect_test "PostgreSQL boolean has its SQL type" =
  let statement = constant ~dialect:Dialect.portable Db_type.bool true in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'true' AS boolean);
    |}]
;;

let%expect_test "SQLite boolean uses its integer representation" =
  let statement = constant ~dialect:Dialect.portable Db_type.bool true in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      1;
    |}]
;;

let%expect_test "PostgreSQL date uses a typed literal" =
  let date = Date.of_string "2026-10-07" |> Option.value_exn in
  let statement = constant ~dialect:Dialect.portable Db_type.date date in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'2026-10-07' AS date);
    |}]
;;

let%expect_test "SQLite date uses its text representation" =
  let date = Date.of_string "2026-10-07" |> Option.value_exn in
  let statement = constant ~dialect:Dialect.portable Db_type.date date in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      '2026-10-07';
    |}]
;;

let%expect_test "PostgreSQL UUID uses a typed literal" =
  let uuid = Uuid.of_string_exn "00000000-0000-0000-0000-000000000001" in
  let statement = constant ~dialect:Dialect.portable Db_type.uuid uuid in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'00000000-0000-0000-0000-000000000001' AS uuid);
    |}]
;;

let%expect_test "SQLite UUID uses its text representation" =
  let uuid = Uuid.of_string_exn "00000000-0000-0000-0000-000000000001" in
  let statement = constant ~dialect:Dialect.portable Db_type.uuid uuid in
  Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      '00000000-0000-0000-0000-000000000001';
    |}]
;;

let%expect_test "PostgreSQL numeric keeps its exact value" =
  let decimal = Decimal.of_string "12.50" |> Option.value_exn in
  let statement = constant ~dialect:Dialect.postgresql Db_type.numeric decimal in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'12.5' AS numeric);
    |}]
;;

let%expect_test "PostgreSQL bytea uses hexadecimal input" =
  let statement =
    constant ~dialect:Dialect.postgresql Db_type.bytes (Bytes.of_string "A\000B")
  in
  Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      CAST(E'\\x410042' AS bytea);
    |}]
;;

let%test "PostgreSQL text with NUL returns a located error" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.text "A\000B" in
  match Statement.debug_sql ~dialect:Postgresql ~input:() statement with
  | Error (Statement.Unrepresentable_literal { position = 1; name = None; _ }) -> true
  | Ok _ | Error _ -> false
;;

let%test "SQLite non-finite float returns a located error" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.float Stdlib.infinity in
  match Statement.debug_sql ~dialect:Sqlite ~input:() statement with
  | Error (Statement.Unrepresentable_literal { position = 1; name = None; _ }) -> true
  | Ok _ | Error _ -> false
;;

let%test "SQLite NaN returns a located error" =
  let statement = constant ~dialect:Dialect.sqlite Db_type.float Stdlib.nan in
  match Statement.debug_sql ~dialect:Sqlite ~input:() statement with
  | Error (Statement.Unrepresentable_literal { position = 1; name = None; _ }) -> true
  | Ok _ | Error _ -> false
;;

let%test "debug SQL reports a foreign parameter slot" =
  let captured = ref None in
  let _first =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let%map.Parameters expression = params.expr Db_type.int64 ~get:Fn.id in
      captured := Some expression;
      params.query_one (Query.select_one expression))
  in
  let expression = Option.value_exn !captured in
  let second =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      Parameters.return (params.query_one (Query.select_one expression)))
  in
  match Statement.debug_sql ~dialect:Sqlite ~input:7L second with
  | Error
      (Statement.Resolution_failure
         (Statement.Statement_error
            (Statement.Invalid_parameter { message = Statement.Unknown_parameter_slot; _ })))
    -> true
  | Ok _ | Error _ -> false
;;

let%test "debug SQL reports dynamic compilation errors" =
  let statement =
    Statement.Dynamic.query_many ~dialect:Dialect.portable (fun () ->
      Query.(
        from Person.table
        |> limit (-1)
        |> select (fun person -> Projection.expr (Person.id person))))
  in
  match Statement.debug_sql ~dialect:Sqlite ~input:() statement with
  | Error
      (Statement.Resolution_failure
         (Statement.Statement_error
            (Statement.Compilation_error { error = Negative_limit -1; _ }))) -> true
  | Ok _ | Error _ -> false
;;

let%test "debug_sql_exn raises a structured diagnostic error" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.text "A\000B" in
  match Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement with
  | exception
      Statement.Debug_sql_error
        (Statement.Unrepresentable_literal { position = 1; name = None; _ }) -> true
  | _ -> false
;;

let%test "debug SQL exception includes the reason in Printexc output" =
  let statement = constant ~dialect:Dialect.postgresql Db_type.text "A\000B" in
  try
    ignore (Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement);
    false
  with
  | Statement.Debug_sql_error _ as error ->
    String.is_substring
      (Stdlib.Printexc.to_string error)
      ~substring:"PostgreSQL text input cannot contain a NUL byte"
;;

let%test "mapped codec output is rendered and errors stay structured" =
  let db_type =
    Db_type.map
      ~name:"uppercase"
      ~encode:(fun value ->
        if String.is_empty value then
          Error "empty value"
        else
          Ok (String.uppercase value))
      ~decode:(fun value -> Ok value)
      Db_type.text
  in
  let statement =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let%map.Parameters value = params.expr ~name:"name" db_type ~get:Fn.id in
      params.query_one (Query.select_one value))
  in
  String.is_substring
    (Statement.debug_sql_exn ~dialect:Postgresql ~input:"Ada" statement)
    ~substring:"E'ADA'"
  &&
  match Statement.debug_sql ~dialect:Postgresql ~input:"" statement with
  | Error
      (Statement.Resolution_failure
         (Statement.Codec_error
            { position = 1; name = Some "name"; message = "empty value" })) -> true
  | Ok _ | Error _ -> false
;;

let%test "dynamic statement resolves the selected input once" =
  let builds = ref 0 in
  let statement =
    Statement.Dynamic.query_one ~dialect:Dialect.portable (fun value ->
      Int.incr builds;
      Query.select_one (Expr.constant Db_type.int value))
  in
  let sql = Statement.debug_sql_exn ~dialect:Sqlite ~input:42 statement in
  Int.equal !builds 1 && String.is_substring sql ~substring:"42"
;;

let%test "input choice renders only the selected branch" =
  let branch value =
    Statement.Dynamic.query_one ~dialect:Dialect.portable (fun _ ->
      Query.select_one (Expr.constant Db_type.int value))
  in
  let chosen = Statement.choose ~when_:Fn.id ~if_true:(branch 1) ~if_false:(branch 2) in
  let selected = Statement.debug_sql_exn ~dialect:Sqlite ~input:true chosen in
  let other = Statement.debug_sql_exn ~dialect:Sqlite ~input:false chosen in
  String.is_substring selected ~substring:"1;"
  && String.is_substring other ~substring:"2;"
;;
