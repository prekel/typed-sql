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

let no_params_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(from Person.table |> select Person.projection)
;;

let%test "a statement without runtime parameters has unit input" =
  String.equal
    (Statement.sql_exn ~dialect:Postgresql no_params_statement)
    (Statement.sql_exn ~dialect:Postgresql ~input:() no_params_statement)
;;

let applicative_pagination_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map page_size = params.non_negative_int ~name:"page_size" ~get:fst
    and page_offset = params.non_negative_int ~name:"page_offset" ~get:snd in
    params.query_many
      Query.(
        from Person.table
        |> order_by Person.id `Asc
        |> limit_param page_size
        |> offset_param page_offset
        |> select Person.projection))
;;

let%expect_test "applicative parameter declarations compile before the query" =
  Statement.sql_exn ~dialect:Postgresql ~input:(10, 20) applicative_pagination_statement
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "people" AS t0
    ORDER BY
      t0."id" ASC
    LIMIT $1
    OFFSET $2
    |}]
;;

let let_plus_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let+ expected_name = params.expr Db_type.text ~get:Fn.id in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person -> Person.name person =. expected_name)
        |> select Person.projection))
;;

let%test "Parameters.Let_syntax supports let+" =
  String.is_substring
    (Statement.sql_exn ~dialect:Postgresql ~input:"Ada" let_plus_statement)
    ~substring:"= $1"
;;

let nested_let_plus_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax.Let_syntax in
    let+ expected_name = params.expr Db_type.text ~get:Fn.id in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person -> Person.name person =. expected_name)
        |> select Person.projection))
;;

let%test "Parameters.Let_syntax.Let_syntax supports let+" =
  String.is_substring
    (Statement.sql_exn ~dialect:Postgresql ~input:"Ada" nested_let_plus_statement)
    ~substring:"= $1"
;;

let%test "shared parameter compilation raises definition errors" =
  match
    Statement.query_many
      ~dialect:Dialect.portable
      Query.(from Person.table |> limit (-1) |> select Person.projection)
  with
  | exception
      Statement.Definition_error
        { dialect = Dialect.Postgresql; error = Compile_error.Negative_limit -1 } -> true
  | _ -> false
;;

type tuple_input = string * int64 * int64 * string * int * int * string * bool * int * int

let tuple_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map name =
      params.column Person.name_column ~get:(fun (name, _, _, _, _, _, _, _, _, _) ->
        name)
    and min_id =
      params.column Person.id_column ~get:(fun (_, min_id, _, _, _, _, _, _, _, _) ->
        min_id)
    and max_id =
      params.column Person.id_column ~get:(fun (_, _, max_id, _, _, _, _, _, _, _) ->
        max_id)
    and email =
      params.column Person.email_column ~get:(fun (_, _, _, email, _, _, _, _, _, _) ->
        email)
    and min_age =
      params.column Person.age_column ~get:(fun (_, _, _, _, min_age, _, _, _, _, _) ->
        min_age)
    and max_age =
      params.column Person.age_column ~get:(fun (_, _, _, _, _, max_age, _, _, _, _) ->
        max_age)
    and city =
      params.column Person.city_column ~get:(fun (_, _, _, _, _, _, city, _, _, _) ->
        city)
    and active =
      params.column Person.active_column ~get:(fun (_, _, _, _, _, _, _, active, _, _) ->
        active)
    and maximum_rows =
      params.non_negative_int
        ~name:"maximum_rows"
        ~get:(fun (_, _, _, _, _, _, _, _, maximum_rows, _) -> maximum_rows)
    and start_at =
      params.non_negative_int
        ~name:"start_at"
        ~get:(fun (_, _, _, _, _, _, _, _, _, start_at) -> start_at)
    in
    params.query_many
      (build_query
         ~name
         ~min_id
         ~max_id
         ~email
         ~min_age
         ~max_age
         ~city
         ~active
         ~maximum_rows
         ~start_at))
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
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map name = params.column Person.name_column ~get:(fun input -> input.name)
    and min_id = params.column Person.id_column ~get:(fun input -> input.min_id)
    and max_id = params.column Person.id_column ~get:(fun input -> input.max_id)
    and email = params.column Person.email_column ~get:(fun input -> input.email)
    and min_age = params.column Person.age_column ~get:(fun input -> input.min_age)
    and max_age = params.column Person.age_column ~get:(fun input -> input.max_age)
    and city = params.column Person.city_column ~get:(fun input -> input.city)
    and active = params.column Person.active_column ~get:(fun input -> input.active)
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows" ~get:(fun input -> input.maximum_rows)
    and start_at =
      params.non_negative_int ~name:"start_at" ~get:(fun input -> input.start_at)
    in
    params.query_many
      (build_query
         ~name
         ~min_id
         ~max_id
         ~email
         ~min_age
         ~max_age
         ~city
         ~active
         ~maximum_rows
         ~start_at))
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
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map name = params.column Person.name_column ~get:Input.name
      and min_id = params.column Person.id_column ~get:Input.min_id
      and max_id = params.column Person.id_column ~get:Input.max_id
      and email = params.column Person.email_column ~get:Input.email
      and min_age = params.column Person.age_column ~get:Input.min_age
      and max_age = params.column Person.age_column ~get:Input.max_age
      and city = params.column Person.city_column ~get:Input.city
      and active = params.column Person.active_column ~get:Input.active
      and maximum_rows =
        params.non_negative_int ~name:"maximum_rows" ~get:Input.maximum_rows
      and start_at = params.non_negative_int ~name:"start_at" ~get:Input.start_at in
      params.query_many
        (build_query
           ~name
           ~min_id
           ~max_id
           ~email
           ~min_age
           ~max_age
           ~city
           ~active
           ~maximum_rows
           ~start_at))
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
  let sql statement input = Statement.sql_exn ~dialect:Postgresql ~input statement in
  let tuple_sql = sql tuple_statement tuple_input in
  let record_sql = sql record_statement record_input in
  let ppx_record_sql = sql Find_people.statement ppx_record_input in
  assert (String.equal tuple_sql record_sql);
  assert (String.equal record_sql ppx_record_sql)
;;

let fetch_with_ties_statement =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map page_size = params.non_negative_int ~name:"page_size" ~get:snd
    and start_at = params.non_negative_int ~name:"start_at" ~get:fst in
    params.query_many
      Query.(
        from Person.table
        |> order_by Person.age `Asc
        |> offset_param start_at
        |> Postgresql.Query.fetch_with_ties_param page_size
        |> select Person.projection))
;;

let%expect_test "FETCH parameters follow OFFSET then FETCH SQL order" =
  Statement.sql_exn ~dialect:Postgresql ~input:(3, 5) fetch_with_ties_statement
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "people" AS t0
    ORDER BY
      t0."age" ASC
    OFFSET $1
    FETCH FIRST $2 ROWS WITH TIES
    |}]
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
      Statement.with_parameters
        ~dialect:Dialect.portable
        (fun ~(params : (sort, Dialect.portable, Dialect.both) Statement.parameters) ->
           Statement.Parameters.return
             (params.query_many
                Query.(
                  from Person.table
                  |> order_by expression direction
                  |> select Person.projection)))
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
    let sql input = Statement.sql_exn ~dialect:Postgresql ~input statement

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

    let page_statement, total_statement =
      Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
        let%map.Statement.Parameters min_age =
          params.column Person.age_column ~get:(fun input -> input.min_age)
        and city = params.column Person.city_column ~get:(fun input -> input.city)
        and maximum_rows =
          params.non_negative_int ~name:"maximum_rows" ~get:(fun input ->
            input.maximum_rows)
        and start_at =
          params.non_negative_int ~name:"start_at" ~get:(fun input -> input.start_at)
        in
        let filtered = filtered_people ~min_age ~city in
        let page =
          params.query_many
            Query.(
              filtered
              |> order_by Person.id `Asc
              |> limit_param maximum_rows
              |> offset_param start_at
              |> select Person.projection)
        in
        let total =
          params.query_one
            Query.(
              filtered |> select_exactly_one (fun _ -> Projection.expr Expr.count_all))
        in
        page, total)
    ;;

    let input = { min_age = 18; city = "London"; maximum_rows = 20; start_at = 40 }
    let sql dialect statement = Statement.sql_exn ~dialect ~input statement

    let%expect_test "PostgreSQL page statement applies shared filters and pagination" =
      sql Postgresql page_statement |> Stdlib.print_endline;
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
      sql Postgresql total_statement |> Stdlib.print_endline;
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
      sql Sqlite page_statement |> Stdlib.print_endline;
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
      sql Sqlite total_statement |> Stdlib.print_endline;
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

let%test_module "PostgreSQL pagination shares input and binds NULL" =
  (module struct
    type filters =
      { min_age : int
      ; city : string
      }

    type 'a paged =
      { inner : 'a
      ; limit : int option
      ; offset : int
      }

    type input = filters paged

    let filtered_people ~min_age ~city =
      Query.(
        from Person.table
        |> where (fun person ->
          Person.age person >=. min_age &&. (Person.city person =. city)))
    ;;

    let page_statement, total_statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map min_age =
          params.column Person.age_column ~get:(fun input -> input.inner.min_age)
        and city = params.column Person.city_column ~get:(fun input -> input.inner.city)
        and maximum_rows =
          params.non_negative_int_opt ~name:"limit" ~get:(fun input -> input.limit)
        and start_at =
          params.non_negative_int ~name:"offset" ~get:(fun input -> input.offset)
        in
        let filtered = filtered_people ~min_age ~city in
        let total =
          params.query_one
            Query.(
              filtered |> select_exactly_one (fun _ -> Projection.expr Expr.count_all))
        in
        let page =
          params.query_many
            Query.(
              filtered
              |> order_by Person.id `Asc
              |> Postgresql.Query.limit_param_opt maximum_rows
              |> offset_param start_at
              |> select Person.projection)
        in
        page, total)
    ;;

    let filters = { min_age = 18; city = "London" }
    let input : input = { inner = filters; limit = None; offset = 20 }

    let%expect_test "NULL limit leaves offset in the SQL" =
      Statement.sql_exn ~dialect:Postgresql ~input page_statement |> Stdlib.print_endline;
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

    let%test "Some and None limits share one SQL template" =
      let sql input = Statement.sql_exn ~dialect:Postgresql ~input page_statement in
      String.equal (sql input) (sql { input with limit = Some 10 })
    ;;

    let%test "negative optional limit is rejected before execution" =
      match
        Statement.sql
          ~dialect:Postgresql
          ~input:{ input with limit = Some (-1) }
          page_statement
      with
      | Error
          (Statement.Invalid_parameter
             { name = Some "limit"; message = Statement.Negative_pagination_value -1 }) ->
        true
      | Ok _ | Error _ -> false
    ;;

    let%expect_test "total uses the same filter declarations directly" =
      Statement.sql_exn ~dialect:Postgresql ~input total_statement |> Stdlib.print_endline;
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

    let optional_offset_statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map start_at = params.non_negative_int_opt ~name:"offset" ~get:Fn.id in
        params.query_many
          Query.(
            from Person.table
            |> order_by Person.id `Asc
            |> limit 10
            |> Postgresql.Query.offset_param_opt start_at
            |> select Person.projection))
    ;;

    let%expect_test "NULL offset remains a bound parameter" =
      Statement.sql_exn ~dialect:Postgresql ~input:None optional_offset_statement
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."name"
        FROM "people" AS t0
        ORDER BY
          t0."id" ASC
        LIMIT 10
        OFFSET $1
        |}]
    ;;

    let%test "negative optional offset is rejected before execution" =
      match
        Statement.sql ~dialect:Postgresql ~input:(Some (-1)) optional_offset_statement
      with
      | Error
          (Statement.Invalid_parameter
             { name = Some "offset"; message = Statement.Negative_pagination_value -1 })
        -> true
      | Ok _ | Error _ -> false
    ;;
  end)
;;

let%test_module "nested input fields bind directly through parameters" =
  (module struct
    type inner =
      { minimum_age : int
      ; name : string
      ; city : string option
      ; limit : int option
      ; offset : int
      }

    type input = { inner : inner }

    let statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map minimum_age =
          params.expr Db_type.int ~get:(fun input -> input.inner.minimum_age)
        and name = params.column Person.name_column ~get:(fun input -> input.inner.name)
        and city = params.optional_expr Db_type.text ~get:(fun input -> input.inner.city)
        and maximum_rows =
          params.non_negative_int_opt ~name:"limit" ~get:(fun input -> input.inner.limit)
        and start_at =
          params.non_negative_int ~name:"offset" ~get:(fun input -> input.inner.offset)
        in
        params.query_many
          Query.(
            from Person.table
            |> where (fun person ->
              Person.age person >=. minimum_age &&. (Person.name person =. name))
            |> where_optional_param city ~f:(fun person city ->
              Person.city person =. city)
            |> Postgresql.Query.limit_param_opt maximum_rows
            |> offset_param start_at
            |> select Person.projection))
    ;;

    let input =
      { inner = { minimum_age = 18; name = "Ada"; city = None; limit = None; offset = 20 }
      }
    ;;

    let%test "mapped descriptors keep one SQL shape" =
      let sql input = Statement.sql_exn ~dialect:Postgresql ~input statement in
      String.equal
        (sql input)
        (sql
           { inner =
               { minimum_age = 21
               ; name = "Grace"
               ; city = Some "London"
               ; limit = Some 10
               ; offset = 0
               }
           })
    ;;

    let%test "mapped nullable limit still validates" =
      match
        Statement.sql
          ~dialect:Postgresql
          ~input:{ inner = { input.inner with limit = Some (-1) } }
          statement
      with
      | Error (Statement.Invalid_parameter { name = Some "limit"; _ }) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "nested offset still validates" =
      match
        Statement.sql
          ~dialect:Postgresql
          ~input:{ inner = { input.inner with offset = -1 } }
          statement
      with
      | Error (Statement.Invalid_parameter { name = Some "offset"; _ }) -> true
      | Ok _ | Error _ -> false
    ;;
  end)
;;

let%test "a slot from another statement returns an explicit binding error" =
  let captured = ref None in
  let _first =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map expression = params.expr Db_type.int64 ~get:Fn.id in
      captured := Some expression;
      params.query_many
        Query.(from Person.table |> select (fun _ -> Projection.expr expression)))
  in
  let expression = Option.value_exn !captured in
  let second =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      Statement.Parameters.return
        (params.query_many
           Query.(from Person.table |> select (fun _ -> Projection.expr expression))))
  in
  match Statement.sql ~dialect:Postgresql ~input:7L second with
  | Error
      (Statement.Invalid_parameter
         ({ name = None; message = Statement.Unknown_parameter_slot } as error)) ->
    let sexp = Statement.sexp_of_binding_error error in
    let serialized_correctly =
      match sexp with
      | Sexp.List
          [ Sexp.List [ Sexp.Atom "name"; Sexp.List [] ]
          ; Sexp.List [ Sexp.Atom "message"; Sexp.Atom "Unknown_parameter_slot" ]
          ] -> true
      | _ -> false
    in
    serialized_correctly
    && String.equal
         (Stdlib.Printexc.to_string
            (Statement.Sql_error (Statement.Invalid_parameter error)))
         "Statement.Sql_error (parameter: unknown parameter slot)"
  | Ok _ | Error _ -> false
;;

let%test_module "PostgreSQL array lookup uses one stable bind slot" =
  (module struct
    let statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map ids =
          params.expr (Db_type.Postgresql.array_list Db_type.int64) ~get:Fn.id
        in
        params.query_many
          Query.(
            from Person.table
            |> where (fun person ->
              Postgresql.Expr.equals_any_list (Person.id person) ids)
            |> select (fun person -> Projection.expr (Person.id person))))
    ;;

    let%expect_test "SQL contains one typed array parameter" =
      Statement.sql_exn ~dialect:Postgresql ~input:[ 1L; 2L ] statement
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id"
        FROM "people" AS t0
        WHERE
          (t0."id" = ANY(CAST($1 AS bigint[])))
        |}]
    ;;

    let%test "SQL is unchanged for empty and longer lists" =
      let sql input = Statement.sql_exn ~dialect:Postgresql ~input statement in
      String.equal (sql []) (sql [ 1L; 2L; 3L ])
    ;;
  end)
;;

let%test_module "optional PostgreSQL array lookup keeps one bind slot" =
  (module struct
    type input = { ids : int64 list option }

    let statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map ids =
          params.optional_expr
            (Db_type.Postgresql.array_list Db_type.int64)
            ~get:(fun input -> input.ids)
        in
        params.query_many
          Query.(
            from Person.table
            |> where_optional_param ids ~f:(fun person ids ->
              Postgresql.Expr.equals_any_list (Person.id person) ids)
            |> select (fun person -> Projection.expr (Person.id person))))
    ;;

    let%expect_test "SQL guards one typed array parameter" =
      Statement.sql_exn ~dialect:Postgresql ~input:{ ids = None } statement
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id"
        FROM "people" AS t0
        WHERE
          (
            (CAST(CAST($1 AS bigint[]) AS bigint[]) IS NULL)
            OR (t0."id" = ANY(CAST($1 AS bigint[])))
          )
        |}]
    ;;

    let%test "SQL is unchanged for absent, empty, and nonempty lists" =
      let sql input = Statement.sql_exn ~dialect:Postgresql ~input statement in
      String.equal (sql { ids = None }) (sql { ids = Some [] })
      && String.equal (sql { ids = None }) (sql { ids = Some [ 1L; 2L ] })
    ;;
  end)
;;
