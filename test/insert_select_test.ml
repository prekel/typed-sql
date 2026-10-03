open! Base
open Typed_sql
open Statement_compile
open Infix

let%test_module "INSERT from SELECT" =
  (module struct
    module Book = struct
      type row

      let table : row Table.t = Table.v_exn "book"
      let id_column = Column.v_exn table "id" Db_type.int64
      let title_column = Column.v_exn table "title" Db_type.text
      let year_column = Column.v_exn table "year" Db_type.int64
      let id row = Expr.column row id_column
      let title row = Expr.column row title_column
      let year row = Expr.column row year_column
    end

    module Archive = struct
      type row

      let table : row Table.t = Table.v_exn "book_archive"
      let id_column = Column.v_exn table "id" Db_type.int64
      let title_column = Column.v_exn table "title" Db_type.text

      let nullable_title_column =
        Column.nullable_v_exn table "nullable_title" Db_type.text
      ;;

      let id row = Expr.column row id_column
    end

    let columns = Insert.Columns.(column Archive.id_column |> add Archive.title_column)

    let source =
      Query.(
        from Book.table
        |> select (fun book -> Projection.pair (Book.id book) (Book.title book)))
    ;;

    let filtered_statement =
      Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map cutoff = params.expr Db_type.int64 ~get:Fn.id in
        let source =
          Query.(
            from Book.table
            |> where (fun book -> Book.year book <. cutoff)
            |> select (fun book -> Projection.pair (Book.id book) (Book.title book)))
        in
        params.command
          Insert.(into Archive.table |> from_select columns source |> command))
    ;;

    let on_conflict_statement =
      Statement.command
        ~dialect:Dialect.portable
        Insert.(
          into Archive.table
          |> from_select columns source
          |> on_conflict_do_nothing
          |> command)
    ;;

    let error command =
      match Compiler.compile_portable_command ~dialect:Dialect.Postgresql command with
      | Error error -> Compile_error.to_string error
      | Ok _ -> failwith "expected INSERT compilation error"
    ;;

    let%expect_test "PostgreSQL INSERT SELECT with a parameter" =
      Stdlib.print_endline
        (Statement.sql_exn ~dialect:postgresql ~input:1900L filtered_statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id",
          "title"
        )
        SELECT
          t0."id",
          t0."title"
        FROM "book" AS t0
        WHERE
          (t0."year" < $1)
        |}]
    ;;

    let%expect_test "SQLite INSERT SELECT with a parameter" =
      Stdlib.print_endline
        (Statement.sql_exn ~dialect:sqlite ~input:1900L filtered_statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id",
          "title"
        )
        SELECT
          t0."id",
          t0."title"
        FROM "book" AS t0
        WHERE
          (t0."year" < ?1)
        |}]
    ;;

    let%expect_test "SQLite disambiguates SELECT and ON CONFLICT" =
      Stdlib.print_endline (Statement.sql_exn ~dialect:sqlite on_conflict_statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id",
          "title"
        )
        SELECT
          t0."id",
          t0."title"
        FROM "book" AS t0
        WHERE TRUE
        ON CONFLICT DO NOTHING
        |}]
    ;;

    let%test "SELECT projection must match the target column count" =
      let one_column =
        Query.(from Book.table |> select (fun book -> Projection.expr (Book.id book)))
      in
      let command =
        Insert.(into Archive.table |> from_select columns one_column |> command)
      in
      String.equal
        (error command)
        "INSERT target types [int64, text] do not match SELECT types [int64]"
    ;;

    let%test "SELECT projection must match target database types in order" =
      let reversed =
        Query.(
          from Book.table
          |> select (fun book -> Projection.pair (Book.title book) (Book.id book)))
      in
      let command =
        Insert.(into Archive.table |> from_select columns reversed |> command)
      in
      String.equal
        (error command)
        "INSERT target types [int64, text] do not match SELECT types [text, int64]"
    ;;

    let%test "nullable target requires a nullable source expression" =
      let targets =
        Insert.Columns.(column Archive.id_column |> add Archive.nullable_title_column)
      in
      let command =
        Insert.(into Archive.table |> from_select targets source |> command)
      in
      String.equal
        (error command)
        "INSERT target types [int64, option(text)] do not match SELECT types [int64, text]"
    ;;

    let%test "duplicate target columns are rejected" =
      let targets = Insert.Columns.(column Archive.id_column |> add Archive.id_column) in
      let command =
        Insert.(into Archive.table |> from_select targets source |> command)
      in
      String.equal (error command) "column id is assigned more than once"
    ;;

    let%test "target columns must belong to the INSERT table descriptor" =
      let other_table : Archive.row Table.t = Table.v_exn "other_archive" in
      let other_id = Column.v_exn other_table "id" Db_type.int64 in
      let command =
        Insert.(
          into Archive.table |> from_select (Columns.column other_id) source |> command)
      in
      String.is_prefix (error command) ~prefix:"assignment belongs to source #"
    ;;

    let%test "mapped codecs retain their identity in type checks" =
      let mapped_text =
        Db_type.map
          ~encode:(fun value -> Ok value)
          ~decode:(fun value -> Ok value)
          Db_type.text
      in
      let mapped_title = Column.v_exn Archive.table "mapped_title" mapped_text in
      let targets = Insert.Columns.(column Archive.id_column |> add mapped_title) in
      let command =
        Insert.(into Archive.table |> from_select targets source |> command)
      in
      String.is_substring (error command) ~substring:"map#"
    ;;

    let%test "SELECT and VALUES sources cannot be mixed" =
      let command =
        Insert.(
          into Archive.table
          |> from_select columns source
          |> set Archive.id_column 7L
          |> command)
      in
      String.equal (error command) "INSERT cannot combine VALUES and SELECT sources"
    ;;

    let%test "VALUES and SELECT sources cannot be mixed" =
      let command =
        Insert.(
          into Archive.table
          |> set Archive.id_column 7L
          |> from_select columns source
          |> command)
      in
      String.equal (error command) "INSERT cannot combine VALUES and SELECT sources"
    ;;

    let%test_unit "DEFAULT cannot follow a SELECT source" =
      let command =
        Insert.(
          into Archive.table
          |> from_select columns source
          |> default Archive.id_column
          |> command)
      in
      match Compiler.compile_command ~dialect:Dialect.postgresql command with
      | Error Compile_error.Mixed_insert_sources -> ()
      | Error error -> failwith (Compile_error.to_string error)
      | Ok _ -> failwith "INSERT combined DEFAULT and SELECT"
    ;;

    let%test "multi-row VALUES cannot contain a SELECT source" =
      let command =
        Insert.(
          rows Archive.table [ (fun row -> from_select columns source row) ] |> command)
      in
      String.equal (error command) "INSERT cannot combine VALUES and SELECT sources"
    ;;

    let singleton_statement =
      Statement.command
        ~dialect:Dialect.portable
        Insert.(
          into Archive.table
          |> from_select
               (Columns.column Archive.id_column)
               (Query.select_one (Expr.constant Db_type.int64 7L))
          |> on_conflict_do_nothing
          |> command)
    ;;

    let%expect_test "PostgreSQL INSERT from a source-free SELECT" =
      Stdlib.print_endline (Statement.sql_exn ~dialect:postgresql singleton_statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id"
        )
        SELECT
          $1
        ON CONFLICT DO NOTHING
        |}]
    ;;

    let%expect_test "SQLite INSERT from a source-free SELECT with ON CONFLICT" =
      Stdlib.print_endline (Statement.sql_exn ~dialect:sqlite singleton_statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id"
        )
        SELECT
          ?1
        WHERE TRUE
        ON CONFLICT DO NOTHING
        |}]
    ;;

    let%expect_test "INSERT SELECT RETURNING" =
      let statement =
        Statement.query_many
          ~dialect:Dialect.portable
          Insert.(
            into Archive.table
            |> from_select columns source
            |> returning (fun row -> Projection.expr (Archive.id row)))
      in
      Stdlib.print_endline (Statement.sql_exn ~dialect:postgresql statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id",
          "title"
        )
        SELECT
          t0."id",
          t0."title"
        FROM "book" AS t0
        RETURNING
          "id"
        |}]
    ;;

    let%expect_test "SQLite compound source with ON CONFLICT" =
      let left =
        Query.(
          from Book.table
          |> where (fun book -> Book.year book <$ 1900L)
          |> select (fun book -> Projection.pair (Book.id book) (Book.title book)))
      in
      let right =
        Query.(
          from Book.table
          |> where (fun book -> Book.year book >$ 2000L)
          |> select (fun book -> Projection.pair (Book.id book) (Book.title book)))
      in
      let statement =
        Statement.command
          ~dialect:Dialect.portable
          Insert.(
            into Archive.table
            |> from_select columns (Query.union_all left right)
            |> on_conflict_do_nothing
            |> command)
      in
      Stdlib.print_endline (Statement.sql_exn ~dialect:sqlite statement);
      [%expect
        {|
        INSERT INTO "book_archive" (
          "id",
          "title"
        )
        SELECT *
        FROM (
          SELECT
            t0."id",
            t0."title"
          FROM "book" AS t0
          WHERE
            (t0."year" < ?1)
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            t0."id",
            t0."title"
          FROM "book" AS t0
          WHERE
            (t0."year" > ?2)
        ) AS s0
        WHERE TRUE
        ON CONFLICT DO NOTHING
        |}]
    ;;
  end)
;;
