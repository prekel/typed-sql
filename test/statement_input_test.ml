open! Base
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let email_column = Column.v_exn table "email" Db_type.text
  let age_column = Column.v_exn table "age" Db_type.int
  let city_column = Column.v_exn table "city" Db_type.text
  let active_column = Column.v_exn table "active" Db_type.bool
  let id person = Expr.column person id_column
  let name person = Expr.column person name_column
  let email person = Expr.column person email_column
  let age person = Expr.column person age_column
  let city person = Expr.column person city_column
  let active person = Expr.column person active_column
  let projection person = Projection.pair (id person) (name person)
end

let build_query
      ~name
      ~min_id
      ~max_id
      ~email
      ~min_age
      ~max_age
      ~city
      ~active
      ~maximum_rows
      ~start_at
  =
  Query.(
    from Person.table
    |> where (fun person ->
      Person.name person
      =. name
      &&. (Person.id person >=. min_id)
      &&. (Person.id person <=. max_id)
      &&. (Person.email person =. email)
      &&. (Person.age person >=. min_age)
      &&. (Person.age person <=. max_age)
      &&. (Person.city person =. city)
      &&. (Person.active person =. active))
    |> limit_param maximum_rows
    |> offset_param start_at
    |> select Person.projection)
;;

type tuple_input = string * int64 * int64 * string * int * int * string * bool * int * int

let tuple_statement =
  Statement.Portable.query_many_exn (fun params ->
    let name =
      params.column Person.name_column ~get:(fun (name, _, _, _, _, _, _, _, _, _) ->
        name)
    in
    let min_id =
      params.column Person.id_column ~get:(fun (_, min_id, _, _, _, _, _, _, _, _) ->
        min_id)
    in
    let max_id =
      params.column Person.id_column ~get:(fun (_, _, max_id, _, _, _, _, _, _, _) ->
        max_id)
    in
    let email =
      params.column Person.email_column ~get:(fun (_, _, _, email, _, _, _, _, _, _) ->
        email)
    in
    let min_age =
      params.column Person.age_column ~get:(fun (_, _, _, _, min_age, _, _, _, _, _) ->
        min_age)
    in
    let max_age =
      params.column Person.age_column ~get:(fun (_, _, _, _, _, max_age, _, _, _, _) ->
        max_age)
    in
    let city =
      params.column Person.city_column ~get:(fun (_, _, _, _, _, _, city, _, _, _) ->
        city)
    in
    let active =
      params.column Person.active_column ~get:(fun (_, _, _, _, _, _, _, active, _, _) ->
        active)
    in
    let maximum_rows =
      params.non_negative_int
        ~name:"maximum_rows"
        ~get:(fun (_, _, _, _, _, _, _, _, maximum_rows, _) -> maximum_rows)
    in
    let start_at =
      params.non_negative_int
        ~name:"start_at"
        ~get:(fun (_, _, _, _, _, _, _, _, _, start_at) -> start_at)
    in
    build_query
      ~name
      ~min_id
      ~max_id
      ~email
      ~min_age
      ~max_age
      ~city
      ~active
      ~maximum_rows
      ~start_at)
;;

type record_input =
  { name : string
  ; min_id : int64
  ; max_id : int64
  ; email : string
  ; min_age : int
  ; max_age : int
  ; city : string
  ; active : bool
  ; maximum_rows : int
  ; start_at : int
  }

let record_statement =
  Statement.Portable.query_many_exn (fun params ->
    let name = params.column Person.name_column ~get:(fun input -> input.name) in
    let min_id = params.column Person.id_column ~get:(fun input -> input.min_id) in
    let max_id = params.column Person.id_column ~get:(fun input -> input.max_id) in
    let email = params.column Person.email_column ~get:(fun input -> input.email) in
    let min_age = params.column Person.age_column ~get:(fun input -> input.min_age) in
    let max_age = params.column Person.age_column ~get:(fun input -> input.max_age) in
    let city = params.column Person.city_column ~get:(fun input -> input.city) in
    let active = params.column Person.active_column ~get:(fun input -> input.active) in
    let maximum_rows =
      params.non_negative_int ~name:"maximum_rows" ~get:(fun input -> input.maximum_rows)
    in
    let start_at =
      params.non_negative_int ~name:"start_at" ~get:(fun input -> input.start_at)
    in
    build_query
      ~name
      ~min_id
      ~max_id
      ~email
      ~min_age
      ~max_age
      ~city
      ~active
      ~maximum_rows
      ~start_at)
;;

module Find_people = struct
  module Input = struct
    type t =
      { name : string
      ; min_id : int64
      ; max_id : int64
      ; email : string
      ; min_age : int
      ; max_age : int
      ; city : string
      ; active : bool
      ; maximum_rows : int
      ; start_at : int
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.Portable.query_many_exn (fun params ->
      let name = params.column Person.name_column ~get:Input.name in
      let min_id = params.column Person.id_column ~get:Input.min_id in
      let max_id = params.column Person.id_column ~get:Input.max_id in
      let email = params.column Person.email_column ~get:Input.email in
      let min_age = params.column Person.age_column ~get:Input.min_age in
      let max_age = params.column Person.age_column ~get:Input.max_age in
      let city = params.column Person.city_column ~get:Input.city in
      let active = params.column Person.active_column ~get:Input.active in
      let maximum_rows =
        params.non_negative_int ~name:"maximum_rows" ~get:Input.maximum_rows
      in
      let start_at = params.non_negative_int ~name:"start_at" ~get:Input.start_at in
      build_query
        ~name
        ~min_id
        ~max_id
        ~email
        ~min_age
        ~max_age
        ~city
        ~active
        ~maximum_rows
        ~start_at)
  ;;
end

let tuple_input = "Ada", 1L, 100L, "ada@example.test", 18, 120, "London", true, 50, 0

let record_input =
  { name = "Ada"
  ; min_id = 1L
  ; max_id = 100L
  ; email = "ada@example.test"
  ; min_age = 18
  ; max_age = 120
  ; city = "London"
  ; active = true
  ; maximum_rows = 50
  ; start_at = 0
  }
;;

let ppx_record_input : Find_people.Input.t =
  { name = "Ada"
  ; min_id = 1L
  ; max_id = 100L
  ; email = "ada@example.test"
  ; min_age = 18
  ; max_age = 120
  ; city = "London"
  ; active = true
  ; maximum_rows = 50
  ; start_at = 0
  }
;;

let%test_unit "tuple, manual record, and PPX record describe the same statement" =
  let sql statement input =
    Statement.sql_exn ~dialect:Dialect.Postgresql ~input statement
  in
  let tuple_sql = sql tuple_statement tuple_input in
  let record_sql = sql record_statement record_input in
  let ppx_record_sql = sql Find_people.statement ppx_record_input in
  assert (String.equal tuple_sql record_sql);
  assert (String.equal record_sql ppx_record_sql)
;;

let%test_module "choosing among ten static sort variants" =
  (module struct
    type sort =
      | Id_asc
      | Id_desc
      | Name_asc
      | Name_desc
      | Email_asc
      | Email_desc
      | Age_asc
      | Age_desc
      | City_asc
      | City_desc

    let same_sort left right =
      match left, right with
      | Id_asc, Id_asc
      | Id_desc, Id_desc
      | Name_asc, Name_asc
      | Name_desc, Name_desc
      | Email_asc, Email_asc
      | Email_desc, Email_desc
      | Age_asc, Age_asc
      | Age_desc, Age_desc
      | City_asc, City_asc
      | City_desc, City_desc -> true
      | _ -> false
    ;;

    let ordered_statement expression direction =
      Statement.Portable.query_many_exn
        (fun (_ : (sort, Dialect.portable) Statement.parameters) ->
           Query.(
             from Person.table
             |> order_by expression direction
             |> select Person.projection))
    ;;

    let variants =
      [ Id_asc, ordered_statement Person.id `Asc
      ; Id_desc, ordered_statement Person.id `Desc
      ; Name_asc, ordered_statement Person.name `Asc
      ; Name_desc, ordered_statement Person.name `Desc
      ; Email_asc, ordered_statement Person.email `Asc
      ; Email_desc, ordered_statement Person.email `Desc
      ; Age_asc, ordered_statement Person.age `Asc
      ; Age_desc, ordered_statement Person.age `Desc
      ; City_asc, ordered_statement Person.city `Asc
      ; City_desc, ordered_statement Person.city `Desc
      ]
    ;;

    let rec choose_variants = function
      | [] -> failwith "expected at least one sort variant"
      | [ (_, statement) ] -> statement
      | (sort, statement) :: rest ->
        Statement.choose
          ~when_:(fun input -> same_sort sort input)
          ~if_true:statement
          ~if_false:(choose_variants rest)
    ;;

    let statement = choose_variants variants
    let sql input = Statement.sql_exn ~dialect:Dialect.Postgresql ~input statement

    let%test "selects ascending id order" =
      String.is_substring (sql Id_asc) ~substring:"ORDER BY\n  t0.\"id\" ASC"
    ;;

    let%test "selects descending id order" =
      String.is_substring (sql Id_desc) ~substring:"ORDER BY\n  t0.\"id\" DESC"
    ;;

    let%test "selects ascending name order" =
      String.is_substring (sql Name_asc) ~substring:"ORDER BY\n  t0.\"name\" ASC"
    ;;

    let%test "selects descending name order" =
      String.is_substring (sql Name_desc) ~substring:"ORDER BY\n  t0.\"name\" DESC"
    ;;

    let%test "selects ascending email order" =
      String.is_substring (sql Email_asc) ~substring:"ORDER BY\n  t0.\"email\" ASC"
    ;;

    let%test "selects descending email order" =
      String.is_substring (sql Email_desc) ~substring:"ORDER BY\n  t0.\"email\" DESC"
    ;;

    let%test "selects ascending age order" =
      String.is_substring (sql Age_asc) ~substring:"ORDER BY\n  t0.\"age\" ASC"
    ;;

    let%test "selects descending age order" =
      String.is_substring (sql Age_desc) ~substring:"ORDER BY\n  t0.\"age\" DESC"
    ;;

    let%test "selects ascending city order" =
      String.is_substring (sql City_asc) ~substring:"ORDER BY\n  t0.\"city\" ASC"
    ;;

    let%test "selects descending city order" =
      String.is_substring (sql City_desc) ~substring:"ORDER BY\n  t0.\"city\" DESC"
    ;;
  end)
;;

let%test_module "page and total statements share runtime filters" =
  (module struct
    type input =
      { min_age : int
      ; city : string
      ; maximum_rows : int
      ; start_at : int
      }

    let filtered_people ~min_age ~city =
      Query.(
        from Person.table
        |> where (fun person ->
          Person.age person >=. min_age &&. (Person.city person =. city)))
    ;;

    let page_statement =
      Statement.Portable.query_many_exn (fun params ->
        let min_age = params.column Person.age_column ~get:(fun input -> input.min_age) in
        let city = params.column Person.city_column ~get:(fun input -> input.city) in
        let maximum_rows =
          params.non_negative_int ~name:"maximum_rows" ~get:(fun input ->
            input.maximum_rows)
        in
        let start_at =
          params.non_negative_int ~name:"start_at" ~get:(fun input -> input.start_at)
        in
        Query.(
          filtered_people ~min_age ~city
          |> order_by Person.id `Asc
          |> limit_param maximum_rows
          |> offset_param start_at
          |> select Person.projection))
    ;;

    let total_statement =
      Statement.Portable.query_one_exn (fun params ->
        let min_age = params.column Person.age_column ~get:(fun input -> input.min_age) in
        let city = params.column Person.city_column ~get:(fun input -> input.city) in
        Query.(
          filtered_people ~min_age ~city
          |> select_exactly_one (fun _ -> Projection.expr Expr.count_all)))
    ;;

    let input = { min_age = 18; city = "London"; maximum_rows = 20; start_at = 40 }
    let sql dialect statement = Statement.sql_exn ~dialect ~input statement

    let%expect_test "PostgreSQL page statement applies shared filters and pagination" =
      sql Dialect.Postgresql page_statement |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."name"
        FROM "people" AS t0
        WHERE
          (
            (t0."age" >= $1)
            AND (t0."city" = $2)
          )
        ORDER BY
          t0."id" ASC
        LIMIT $3
        OFFSET $4
        |}]
    ;;

    let%expect_test "PostgreSQL total statement counts the same filtered rows" =
      sql Dialect.Postgresql total_statement |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          COUNT(*)
        FROM "people" AS t0
        WHERE
          (
            (t0."age" >= $1)
            AND (t0."city" = $2)
          )
        |}]
    ;;

    let%expect_test "SQLite page statement applies shared filters and pagination" =
      sql Dialect.Sqlite page_statement |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."name"
        FROM "people" AS t0
        WHERE
          (
            (t0."age" >= ?1)
            AND (t0."city" = ?2)
          )
        ORDER BY
          t0."id" ASC
        LIMIT ?3
        OFFSET ?4
        |}]
    ;;

    let%expect_test "SQLite total statement counts the same filtered rows" =
      sql Dialect.Sqlite total_statement |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          COUNT(*)
        FROM "people" AS t0
        WHERE
          (
            (t0."age" >= ?1)
            AND (t0."city" = ?2)
          )
        |}]
    ;;
  end)
;;

let%test "a slot from another statement returns an explicit binding error" =
  let captured = ref None in
  let _first =
    Statement.Portable.query_many_exn (fun params ->
      let expression = params.expr Db_type.int64 ~get:Fn.id in
      captured := Some expression;
      Query.(from Person.table |> select (fun _ -> Projection.expr expression)))
  in
  let expression = Option.value_exn !captured in
  let second =
    Statement.Portable.query_many_exn (fun _ ->
      Query.(from Person.table |> select (fun _ -> Projection.expr expression)))
  in
  match Statement.sql ~dialect:Dialect.Postgresql ~input:7L second with
  | Error
      (Statement.Invalid_parameter { name = None; message = "unknown parameter slot" }) ->
    true
  | Ok _ | Error _ -> false
;;
