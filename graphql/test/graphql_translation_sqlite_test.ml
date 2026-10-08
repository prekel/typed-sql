open! Base
module Demo = Typed_sql_graphql_test_support.Demo
module T = Caqti.Template

let ( let* ) = Lwt.bind
let ( >>= ) = Lwt.bind

let caqti_or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let fail_on_adapter_error = function
  | Ok rows -> Lwt.return rows
  | Error error -> Lwt.fail_with (Typed_sql_caqti_lwt.error_to_string error)
;;

let assert_json expected actual =
  if not (Yojson.Safe.equal expected actual) then
    failwith
      ("unexpected GraphQL response: "
       ^ Yojson.Safe.to_string actual
       ^ " (expected "
       ^ Yojson.Safe.to_string expected
       ^ ")")
;;

let seed conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let exec sql = Connection.exec (direct sql) () |> caqti_or_fail in
  let* () = exec "CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL)" in
  let* () = exec "CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL)" in
  let* () =
    exec
      "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, author_id INTEGER NOT NULL, category_id INTEGER)"
  in
  let* () = exec "INSERT INTO authors (id, name) VALUES (1, 'Ada'), (2, 'Bob')" in
  let* () = exec "INSERT INTO categories (id, name) VALUES (10, 'News')" in
  exec
    "INSERT INTO posts (id, title, author_id, category_id) VALUES (1, 'First', 1, 10), (2, 'Second', 1, NULL), (3, 'Third', 2, 10)"
;;

let run conn ~query ~variables =
  let request = Demo.parse_request_exn ~query ~variables in
  let* rows =
    Typed_sql_caqti_lwt.run ~conn Demo.statement request >>= fail_on_adapter_error
  in
  Lwt.return (Demo.response request rows)
;;

let check_nested_related_objects_and_null conn =
  let query =
    {|
    query Posts($author: String!, $first: Int!) {
      results: posts(authorName: $author, first: $first, orderBy: ID_DESC) {
        headline: title
        writer: author { name }
        category { name }
      }
    }
    |}
  in
  let* actual = run conn ~query ~variables:[ "author", `String "Ada"; "first", `Int 2 ] in
  let expected =
    `Assoc
      [ ( "data"
        , `Assoc
            [ ( "results"
              , `List
                  [ `Assoc
                      [ "headline", `String "Second"
                      ; "writer", `Assoc [ "name", `String "Ada" ]
                      ; "category", `Null
                      ]
                  ; `Assoc
                      [ "headline", `String "First"
                      ; "writer", `Assoc [ "name", `String "Ada" ]
                      ; "category", `Assoc [ "name", `String "News" ]
                      ]
                  ] )
            ] )
      ]
  in
  assert_json expected actual;
  Lwt.return_unit
;;

let check_relation_filter conn =
  let query = {|{ posts(categoryName: "News") { id title } }|} in
  let* actual = run conn ~query ~variables:[] in
  let expected =
    `Assoc
      [ ( "data"
        , `Assoc
            [ ( "posts"
              , `List
                  [ `Assoc [ "id", `Int 1; "title", `String "First" ]
                  ; `Assoc [ "id", `Int 3; "title", `String "Third" ]
                  ] )
            ] )
      ]
  in
  assert_json expected actual;
  Lwt.return_unit
;;

let check_zero_limit conn =
  let* actual = run conn ~query:"{ posts(first: 0) { id } }" ~variables:[] in
  assert_json (`Assoc [ "data", `Assoc [ "posts", `List [] ] ]) actual;
  Lwt.return_unit
;;

let main () =
  let* conn =
    Caqti_lwt_unix.connect (Uri.of_string "sqlite3::memory:") |> caqti_or_fail
  in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* () = seed conn in
       let* () = check_nested_related_objects_and_null conn in
       let* () = check_relation_filter conn in
       check_zero_limit conn)
    (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
