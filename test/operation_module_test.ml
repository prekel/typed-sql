open! Base
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let email_column = Column.nullable_v_exn table "email" Db_type.text
  let id person = Expr.column person id_column
  let name person = Expr.column person name_column
  let projection person = Projection.pair (id person) (name person)
end

module Find_people = struct
  module Input = struct
    type t =
      { name : string
      ; min_id : int64
      ; maximum_rows : int
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.Portable.query_many_exn (fun params ->
      let name = params.column Person.name_column ~get:Input.name in
      let min_id = params.column Person.id_column ~get:Input.min_id in
      let maximum_rows =
        params.non_negative_int ~name:"maximum_rows" ~get:Input.maximum_rows
      in
      Query.(
        from Person.table
        |> where (fun person ->
          Person.name person =. name &&. (Person.id person >=. min_id))
        |> order_by (fun person -> Person.id person) `Asc
        |> limit_param maximum_rows
        |> select Person.projection))
  ;;
end

module Create_person = struct
  module Input = struct
    type t =
      { id : int64
      ; name : string
      ; email : string option
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let id = params.column Person.id_column ~get:Input.id in
      let name = params.column Person.name_column ~get:Input.name in
      let email = params.column Person.email_column ~get:Input.email in
      Insert.(
        into Person.table
        |> set_expr Person.id_column id
        |> set_expr Person.name_column name
        |> set_expr Person.email_column email
        |> command))
  ;;
end

let%test_module "typed operation modules" =
  (module struct
    let query_input : Find_people.Input.t =
      { name = "Ada"; min_id = 10L; maximum_rows = 20 }
    ;;

    let query_postgresql =
      Statement.sql_exn
        ~dialect:Dialect.Postgresql
        ~input:query_input
        Find_people.statement
    ;;

    let query_sqlite =
      Statement.sql_exn ~dialect:Dialect.Sqlite ~input:query_input Find_people.statement
    ;;

    let command_input : Create_person.Input.t =
      { id = 1L; name = "Ada"; email = Some "ada@example.test" }
    ;;

    let command_postgresql =
      Statement.sql_exn
        ~dialect:Dialect.Postgresql
        ~input:command_input
        Create_person.statement
    ;;

    let command_sqlite =
      Statement.sql_exn
        ~dialect:Dialect.Sqlite
        ~input:command_input
        Create_person.statement
    ;;

    let%test_unit "query operation owns its input type and static statement" =
      assert (String.is_substring query_postgresql ~substring:"$1");
      assert (String.is_substring query_postgresql ~substring:"$2");
      assert (String.is_substring query_postgresql ~substring:"$3");
      assert (String.is_substring query_sqlite ~substring:"?1");
      assert (String.is_substring query_sqlite ~substring:"?2");
      assert (String.is_substring query_sqlite ~substring:"?3")
    ;;

    let%test_unit "command operation uses the same module layout" =
      assert (String.is_substring command_postgresql ~substring:"VALUES");
      assert (Int.(String.count command_postgresql ~f:(Char.equal '$') = 3));
      assert (Int.(String.count command_sqlite ~f:(Char.equal '?') = 3))
    ;;
  end)
;;
