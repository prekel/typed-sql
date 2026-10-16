open! Base
open Typed_sql
module Q = Sqlx_survey.Queries
module D = Sqlx_survey.Dynamic

let inspect statement input = Statement.inspect_exn ~dialect:Postgresql ~input statement
let sql statement input = Statement.sql_exn ~dialect:Postgresql ~input statement
let get = Result.ok_or_failwith

let parameter_values inspection =
  List.map inspection.Statement.parameters ~f:(fun parameter ->
    match parameter.Statement.value with
    | Some (Encoded value) -> Some value
    | Some Null -> None
    | None -> failwith "expected a bound parameter")
;;

let equal_values actual expected = List.equal (Option.equal String.equal) actual expected

let%test_module "static cached SQL and types" =
  (module struct
    let count : (unit, (int * int64 option) list, [ `Postgresql ]) Statement.t = Q.sx08
    let rank : (unit, (int * int64 option) list, [ `Postgresql ]) Statement.t = Q.sx19
    let sum : (unit, (int * int64 option) list, [ `Postgresql ]) Statement.t = Q.sx20

    let left_join : (unit, (int option * int option) list, [ `Postgresql ]) Statement.t =
      Q.sx05
    ;;

    let lateral : (unit, (int option * string option) list, [ `Postgresql ]) Statement.t =
      Q.sx22
    ;;

    let output_types statement =
      match (snd (inspect statement ())).output with
      | Query_output { columns; _ } ->
        List.map columns ~f:(fun column -> column.Statement.db_type)
      | Command_output -> failwith "expected query output"
    ;;

    let%test "COUNT is optional int64 according to Describe" =
      List.equal String.equal (output_types count) [ "int"; "option(int64)" ]
    ;;

    let%test "ROW_NUMBER is optional int64 according to Describe" =
      List.equal String.equal (output_types rank) [ "int"; "option(int64)" ]
    ;;

    let%test "SUM integer widens to optional int64" =
      List.equal String.equal (output_types sum) [ "int"; "option(int64)" ]
    ;;

    let%test "nullable-results applies to both LEFT JOIN fields" =
      List.equal String.equal (output_types left_join) [ "option(int)"; "option(int)" ]
    ;;

    let%test "nullable-results applies to both LATERAL fields" =
      List.equal String.equal (output_types lateral) [ "option(int)"; "option(text)" ]
    ;;

    let%test "nullable input binds SQL NULL" =
      equal_values (parameter_values (snd (inspect Q.sx06 None))) [ None ]
    ;;

    let%test "present nullable input binds its value" =
      equal_values (parameter_values (snd (inspect Q.sx06 (Some 18)))) [ Some "18" ]
    ;;

    let%test_unit "repeated named hole binds the same input twice" =
      let _, inspection = inspect Q.sx14 3 in
      assert (equal_values (parameter_values inspection) [ Some "3"; Some "3" ]);
      assert (
        List.equal
          String.equal
          (List.map inspection.parameters ~f:(fun parameter -> parameter.placeholder))
          [ "$1"; "$2" ])
    ;;

    let%test_unit "static statement reads fresh inputs without changing SQL" =
      let first, first_inspection = inspect Q.sx02 (1, "A%") in
      let second, second_inspection = inspect Q.sx02 (2, "B%") in
      assert (String.equal first second);
      assert (equal_values (parameter_values first_inspection) [ Some "1"; Some "A%" ]);
      assert (equal_values (parameter_values second_inspection) [ Some "2"; Some "B%" ])
    ;;

    let%test "DELETE produces command metadata" =
      let _, inspection = inspect Q.sx28 0 in
      match inspection.output with
      | Command_output -> true
      | Query_output _ -> false
    ;;

    let%test_unit "PostgreSQL array input has one typed slot" =
      let input =
        Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 1 ] ~elements:[ Some 1; Some 3 ]
        |> get
      in
      let _, inspection = inspect Q.sx23 input in
      assert (equal_values (parameter_values inspection) [ Some "{\"1\",\"3\"}" ]);
      match inspection.parameters with
      | [ parameter ] -> assert (String.equal parameter.db_type "array(int)")
      | _ -> failwith "expected one array parameter"
    ;;

    let%test "empty array preserves static SQL" =
      let empty =
        Pg_array.create ~dimensions:[ 0 ] ~lower_bounds:[ 1 ] ~elements:[] |> get
      in
      equal_values (parameter_values (snd (inspect Q.sx23 empty))) [ Some "{}" ]
    ;;
  end)
;;

let%test_module "dynamic predicates and ordering" =
  (module struct
    let%expect_test "optional WHERE can be omitted" =
      Stdlib.print_endline (sql D.sx31 None);
      [%expect {| SELECT id, name FROM users ORDER BY id |}]
    ;;

    let%test_unit "SQL metacharacters remain a bound value" =
      let input = "Ada'; DROP TABLE users; --" in
      let rendered, inspection = inspect D.sx31 (Some input) in
      assert (
        String.equal rendered "SELECT id, name FROM users WHERE name = $1 ORDER BY id");
      assert (equal_values (parameter_values inspection) [ Some input ])
    ;;

    let%expect_test "empty condition group omits WHERE" =
      Stdlib.print_endline (sql D.sx32 []);
      [%expect {| SELECT id, name FROM users ORDER BY id |}]
    ;;

    let%test_unit "grouped conditions bind in SQL order" =
      let _, inspection = inspect D.sx32 [ D.Name_like "A%"; D.Min_id 5 ] in
      assert (equal_values (parameter_values inspection) [ Some "A%"; Some "5" ]);
      assert (
        List.equal
          String.equal
          (List.map inspection.parameters ~f:(fun parameter -> parameter.db_type))
          [ "text"; "int" ])
    ;;

    let%expect_test "empty IN is FALSE" =
      Stdlib.print_endline (sql D.sx33 []);
      [%expect {| SELECT id, name FROM users WHERE FALSE ORDER BY id |}]
    ;;

    let%expect_test "singleton IN has one placeholder" =
      Stdlib.print_endline (sql D.sx33 [ 3 ]);
      [%expect {| SELECT id, name FROM users WHERE id IN ($1) ORDER BY id |}]
    ;;

    let%test_unit "IN length changes placeholders and preserves values" =
      let rendered, inspection = inspect D.sx33 [ 3; 1; 7 ] in
      assert (
        String.equal
          rendered
          "SELECT id, name FROM users WHERE id IN ($1, $2, $3) ORDER BY id");
      assert (equal_values (parameter_values inspection) [ Some "3"; Some "1"; Some "7" ])
    ;;

    let%expect_test "empty tuple IN is FALSE" =
      Stdlib.print_endline (sql D.sx34 []);
      [%expect {| SELECT id, name FROM users WHERE FALSE ORDER BY id |}]
    ;;

    let%test_unit "tuple IN preserves mixed descriptors and row order" =
      let _, inspection = inspect D.sx34 [ 1, "Ada"; 2, "Bob" ] in
      assert (
        equal_values
          (parameter_values inspection)
          [ Some "1"; Some "Ada"; Some "2"; Some "Bob" ]);
      assert (
        List.equal
          Int.equal
          (List.map inspection.parameters ~f:(fun parameter -> parameter.position))
          [ 1; 2; 3; 4 ])
    ;;

    let%expect_test "ascending sort uses the closed variant" =
      Stdlib.print_endline (sql D.sx35 D.Name_asc);
      [%expect {| SELECT id, name FROM users ORDER BY name ASC, id |}]
    ;;

    let%expect_test "descending sort uses the closed variant" =
      Stdlib.print_endline (sql D.sx35 D.Name_desc);
      [%expect {| SELECT id, name FROM users ORDER BY name DESC, id |}]
    ;;

    let%expect_test "conditional JOIN can be omitted" =
      Stdlib.print_endline (sql D.sx36 false);
      [%expect {| SELECT DISTINCT u.id, u.name FROM users u ORDER BY u.id |}]
    ;;

    let%expect_test "empty UNION branches form an empty SELECT" =
      Stdlib.print_endline (sql D.sx37 []);
      [%expect {| SELECT id FROM users WHERE FALSE ORDER BY id |}]
    ;;

    let%expect_test "singleton UNION has no union operator" =
      Stdlib.print_endline (sql D.sx37 [ "Ada" ]);
      [%expect {| SELECT id FROM users WHERE name = $1 ORDER BY id |}]
    ;;
  end)
;;

let%test_module "dynamic mutations" =
  (module struct
    let%test "empty INSERT batch is rejected" =
      match D.sx38 [] with
      | Error message -> String.equal message "rows must not be empty"
      | Ok _ -> false
    ;;

    let%expect_test "singleton INSERT batch" =
      Stdlib.print_endline (sql (get (D.sx38 [ 4, "Dan" ])) ());
      [%expect {| INSERT INTO users (id, name) VALUES ($1, $2) |}]
    ;;

    let%test_unit "INSERT batch binds rows in order" =
      let _, inspection = inspect (get (D.sx38 [ 4, "Dan"; 5, "Eve" ])) () in
      assert (
        equal_values
          (parameter_values inspection)
          [ Some "4"; Some "Dan"; Some "5"; Some "Eve" ])
    ;;

    let%test "empty SET is rejected" =
      match D.sx39 ~id:1 ~name:None ~age:None with
      | Error message -> String.equal message "at least one SET field is required"
      | Ok _ -> false
    ;;

    let%expect_test "name-only UPDATE omits age" =
      Stdlib.print_endline (sql (get (D.sx39 ~id:1 ~name:(Some "Ada") ~age:None)) ());
      [%expect {| UPDATE users SET name = $1 WHERE id = $2 RETURNING id, name |}]
    ;;

    let%test_unit "explicit NULL differs from omitted age" =
      let rendered, inspection =
        inspect (get (D.sx39 ~id:1 ~name:None ~age:(Some None))) ()
      in
      assert (
        String.equal rendered "UPDATE users SET age = $1 WHERE id = $2 RETURNING id, name");
      assert (equal_values (parameter_values inspection) [ None; Some "1" ])
    ;;

    let%test_unit "present age is bound before the WHERE key" =
      let _, inspection =
        inspect (get (D.sx39 ~id:1 ~name:None ~age:(Some (Some 25)))) ()
      in
      assert (equal_values (parameter_values inspection) [ Some "25"; Some "1" ])
    ;;

    let%test "empty UPDATE batch is rejected" =
      match D.sx40 [] with
      | Error message -> String.equal message "rows must not be empty"
      | Ok _ -> false
    ;;

    let%expect_test "singleton UPDATE FROM batch retains casts" =
      Stdlib.print_endline (sql (get (D.sx40 [ 1, "Ada" ])) ());
      [%expect
        {| UPDATE users u SET name = v.name FROM (VALUES ($1::int4, $2::text)) AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name |}]
    ;;

    let%test_unit "UPDATE FROM batch binds all rows" =
      let _, inspection = inspect (get (D.sx40 [ 1, "Ada"; 2, "Bob" ])) () in
      assert (
        equal_values
          (parameter_values inspection)
          [ Some "1"; Some "Ada"; Some "2"; Some "Bob" ])
    ;;
  end)
;;
