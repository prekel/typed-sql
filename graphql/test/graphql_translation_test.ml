open! Base
open Typed_sql
module Demo = Typed_sql_graphql_test_support.Demo
open Demo

let%test "parser accepts schema-independent root and field names" =
  match
    Gql.Request.parse
      ~query:"query Report($min: Int!) { items: reports(min: $min) { label: name } }"
      ~variables:[ "min", `Int 3 ]
  with
  | Error _ -> false
  | Ok request ->
    let root = request.root in
    String.equal root.name "reports"
    && String.equal root.response_name "items"
    && (match root.arguments with
        | [ ("min", `Int 3) ] -> true
        | _ -> false)
    &&
      (match root.selections with
      | [ field ] ->
        String.equal field.name "name" && String.equal field.response_name "label"
      | _ -> false)
;;

let%test_module "GraphQL SQL rendering" =
  (module struct
    let simple = "{ posts { id title } }"

    let related_objects =
      {|
      query Posts($author: String!, $first: Int!) {
        results: posts(authorName: $author, minId: 2, first: $first, orderBy: ID_DESC) {
          id
          headline: title
          writer: author { name }
          category { id name }
        }
      }
      |}
    ;;

    let category_filter = {|{ posts(categoryName: "News", first: 1) { title } }|}
    let author_filter = {|{ posts(authorName: "Ada") { title } }|}

    let%expect_test "simple projection in PostgreSQL" =
      sql_exn Postgresql ~query:simple ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."title"
        FROM "posts" AS t0
        ORDER BY
          t0."id" ASC
        LIMIT $1
        |}]
    ;;

    let%expect_test "simple projection in SQLite" =
      sql_exn Sqlite ~query:simple ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."title"
        FROM "posts" AS t0
        ORDER BY
          t0."id" ASC NULLS LAST
        LIMIT ?1
        |}]
    ;;

    let%expect_test "related objects, variables and aliases in PostgreSQL" =
      sql_exn
        Postgresql
        ~query:related_objects
        ~variables:[ "author", `String "Ada"; "first", `Int 2 ]
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."title",
          (
            SELECT
              t1."name"
            FROM "authors" AS t1
            WHERE
              (t1."id" = t0."author_id")
            LIMIT $1
          ),
          (
            SELECT
              t1."id"
            FROM "categories" AS t1
            WHERE
              (t1."id" = t0."category_id")
            LIMIT $2
          ),
          (
            SELECT
              t1."name"
            FROM "categories" AS t1
            WHERE
              (t1."id" = t0."category_id")
            LIMIT $3
          )
        FROM "posts" AS t0
        WHERE
          (
            (t0."id" >= $4)
            AND (EXISTS (
              SELECT
                1
              FROM "authors" AS t1
              WHERE
                (
                  (t1."id" = t0."author_id")
                  AND (t1."name" = $5)
                )
            ))
          )
        ORDER BY
          t0."id" DESC
        LIMIT $6
        |}]
    ;;

    let%expect_test "related objects, variables and aliases in SQLite" =
      sql_exn
        Sqlite
        ~query:related_objects
        ~variables:[ "author", `String "Ada"; "first", `Int 2 ]
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."title",
          (
            SELECT
              t1."name"
            FROM "authors" AS t1
            WHERE
              (t1."id" = t0."author_id")
            LIMIT ?1
          ),
          (
            SELECT
              t1."id"
            FROM "categories" AS t1
            WHERE
              (t1."id" = t0."category_id")
            LIMIT ?2
          ),
          (
            SELECT
              t1."name"
            FROM "categories" AS t1
            WHERE
              (t1."id" = t0."category_id")
            LIMIT ?3
          )
        FROM "posts" AS t0
        WHERE
          (
            (t0."id" >= ?4)
            AND (EXISTS (
              SELECT
                1
              FROM "authors" AS t1
              WHERE
                (
                  (t1."id" = t0."author_id")
                  AND (t1."name" = ?5)
                )
            ))
          )
        ORDER BY
          t0."id" DESC NULLS FIRST
        LIMIT ?6
        |}]
    ;;

    let%expect_test "author filter uses EXISTS in PostgreSQL" =
      sql_exn Postgresql ~query:author_filter ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."title"
        FROM "posts" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "authors" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."name" = $1)
              )
          ))
        ORDER BY
          t0."id" ASC
        LIMIT $2
        |}]
    ;;

    let%expect_test "author filter uses EXISTS in SQLite" =
      sql_exn Sqlite ~query:author_filter ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."title"
        FROM "posts" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "authors" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."name" = ?1)
              )
          ))
        ORDER BY
          t0."id" ASC NULLS LAST
        LIMIT ?2
        |}]
    ;;

    let%expect_test "category filter uses EXISTS in PostgreSQL" =
      sql_exn Postgresql ~query:category_filter ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."title"
        FROM "posts" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "categories" AS t1
            WHERE
              (
                (t1."id" = t0."category_id")
                AND (t1."name" = $1)
              )
          ))
        ORDER BY
          t0."id" ASC
        LIMIT $2
        |}]
    ;;

    let%expect_test "category filter uses EXISTS in SQLite" =
      sql_exn Sqlite ~query:category_filter ~variables:[] |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."title"
        FROM "posts" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "categories" AS t1
            WHERE
              (
                (t1."id" = t0."category_id")
                AND (t1."name" = ?1)
              )
          ))
        ORDER BY
          t0."id" ASC NULLS LAST
        LIMIT ?2
        |}]
    ;;
  end)
;;

let%test "filter value stays in a bind parameter" =
  let supplied = "Ada' OR 1=1" in
  let request =
    parse_request_exn ~query:{|{ posts(authorName: "Ada' OR 1=1") { id } }|} ~variables:[]
  in
  let sql, inspection = Statement.inspect_exn ~dialect:Sqlite ~input:request statement in
  (not (String.is_substring sql ~substring:supplied))
  && List.exists inspection.parameters ~f:(fun parameter ->
    match parameter.value with
    | Some (Statement.Encoded value) -> String.equal value supplied
    | _ -> false)
;;

let%test_module "GraphQL request validation" =
  (module struct
    let rejected ~query ~variables ~message =
      match parse_request ~query ~variables with
      | Ok _ -> false
      | Error error -> String.is_substring error ~substring:message
    ;;

    let%test "unknown post field is rejected" =
      rejected ~query:"{ posts { missing } }" ~variables:[] ~message:"unknown post field"
    ;;

    let%test "unknown argument is rejected" =
      rejected
        ~query:"{ posts(limit: 2) { id } }"
        ~variables:[]
        ~message:"unknown posts argument"
    ;;

    let%test "duplicate response keys are rejected" =
      rejected ~query:"{ posts { id id } }" ~variables:[] ~message:"duplicate name"
    ;;

    let%test "undeclared variable is rejected" =
      rejected
        ~query:"{ posts(authorName: $name) { id } }"
        ~variables:[ "name", `String "Ada" ]
        ~message:"undeclared variable"
    ;;

    let%test "variable with wrong value type is rejected" =
      rejected
        ~query:"query Posts($name: String!) { posts(authorName: $name) { id } }"
        ~variables:[ "name", `Int 2 ]
        ~message:"expected String"
    ;;

    let%test "missing variable is rejected" =
      rejected
        ~query:"query Posts($name: String!) { posts(authorName: $name) { id } }"
        ~variables:[]
        ~message:"missing variable"
    ;;

    let%test "missing required variable is rejected even when unused" =
      rejected
        ~query:"query Posts($name: String!) { posts { id } }"
        ~variables:[]
        ~message:"missing variable"
    ;;

    let%test "wrong type is rejected even when the variable is unused" =
      rejected
        ~query:"query Posts($name: String!) { posts { id } }"
        ~variables:[ "name", `Int 2 ]
        ~message:"expected String"
    ;;

    let%test "missing nullable variable leaves the optional application argument absent" =
      match
        parse_request
          ~query:"query Posts($name: String) { posts(authorName: $name) { id } }"
          ~variables:[]
      with
      | Ok request -> Option.is_none request.author_name
      | Error _ -> false
    ;;

    let%test "null non-null variable is rejected" =
      rejected
        ~query:"query Posts($name: String!) { posts(authorName: $name) { id } }"
        ~variables:[ "name", `Null ]
        ~message:"non-null variable is null"
    ;;

    let%test "invalid first is rejected" =
      rejected
        ~query:"{ posts(first: 101) { id } }"
        ~variables:[]
        ~message:"first must be an Int between 0 and 100"
    ;;

    let%test "fragment is rejected" =
      rejected
        ~query:"{ posts { ...Fields } } fragment Fields on Post { id }"
        ~variables:[]
        ~message:"exactly one query operation"
    ;;

    let%test "directive is rejected" =
      rejected
        ~query:"{ posts { id @skip(if: true) } }"
        ~variables:[]
        ~message:"directives are not supported"
    ;;

    let%test "mutation is rejected" =
      rejected
        ~query:"mutation { posts { id } }"
        ~variables:[]
        ~message:"only query operations are supported"
    ;;
  end)
;;

let%test_module "GraphQL Int range" =
  (module struct
    let parse value =
      Gql.Request.parse
        ~query:"query Q($value: Int!) { items(value: $value) { id } }"
        ~variables:[ "value", `Int value ]
    ;;

    let%test "accepts signed 32-bit boundaries" =
      List.for_all [ -2_147_483_648; 2_147_483_647 ] ~f:(fun value ->
        Result.is_ok (parse value))
    ;;

    let%test "rejects values above the maximum" = Result.is_error (parse 2_147_483_648)
    let%test "rejects values below the minimum" = Result.is_error (parse (-2_147_483_649))

    let%test "rejects out-of-range literals" =
      Result.is_error
        (Gql.Request.parse ~query:"{ items(value: 2147483648) { id } }" ~variables:[])
    ;;
  end)
;;

let%test_module "nullable variable presence" =
  (module struct
    let parse query variables =
      Gql.Request.parse ~query ~variables |> Result.ok_or_failwith
    ;;

    let query = "query Q($value: String) { items(filter: $value) { id } }"

    let%test "omitted nullable variable omits its argument" =
      List.is_empty (parse query []).root.arguments
    ;;

    let%test "explicit variable null keeps its argument" =
      match (parse query [ "value", `Null ]).root.arguments with
      | [ ("filter", `Null) ] -> true
      | _ -> false
    ;;

    let%test "literal null keeps its argument" =
      match (parse "{ items(filter: null) { id } }" []).root.arguments with
      | [ ("filter", `Null) ] -> true
      | _ -> false
    ;;

    let%test "omitted nullable variable omits a nested input field" =
      let query =
        "query Q($value: String) { items(filter: {outer: {value: $value, keep: 1}}) { id } }"
      in
      match (parse query []).root.arguments with
      | [ ("filter", `Assoc [ ("outer", `Assoc [ ("keep", `Int 1) ]) ]) ] -> true
      | _ -> false
    ;;

    let%test "explicit null keeps a nested input field" =
      let query = "query Q($value: String) { items(filter: {value: $value}) { id } }" in
      match (parse query [ "value", `Null ]).root.arguments with
      | [ ("filter", `Assoc [ ("value", `Null) ]) ] -> true
      | _ -> false
    ;;

    let%test "omission preserves list positions" =
      let query =
        "query Q($value: String) { items(filter: [\"before\", $value, {value: $value}, \"after\"]) { id } }"
      in
      match (parse query []).root.arguments with
      | [ ("filter", `List [ `String "before"; `Null; `Assoc []; `String "after" ]) ] ->
        true
      | _ -> false
    ;;

    let%test "omission applies to selected child fields" =
      let request =
        parse "query Q($value: Int) { items { child(filter: $value) { id } } }" []
      in
      match request.root.selections with
      | [ child ] -> List.is_empty child.arguments
      | _ -> false
    ;;

    let%test "missing required variable remains an error" =
      Result.is_error
        (Gql.Request.parse
           ~query:"query Q($value: String!) { items(filter: $value) { id } }"
           ~variables:[])
    ;;
  end)
;;
