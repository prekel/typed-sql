open! Base
open Typed_sql
open Infix
module PGOCaml = Typed_sql_pgocaml_lwt.Pgocaml
module Adapter = Typed_sql_pgocaml_lwt.Make (PGOCaml)

let ( let* ) = Lwt.bind

let or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

module Item = struct
  type row

  type t =
    { id : int64
    ; name : string
    ; note : string option
    }

  let table : row Table.t = Table.v_exn "ppx_mixed_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let note_column = Column.nullable_v_exn table "note" Db_type.text
  let id row = Expr.column row id_column

  let projection row =
    let%map.Projection id = Projection.expr (id row)
    and name = Projection.expr (Expr.column row name_column)
    and note = Projection.expr (Expr.column row note_column) in
    { id; name; note }
  ;;

  let of_pgocaml row = { id = row#id; name = row#name; note = row#note }

  let equal left right =
    Int64.(left.id = right.id)
    && String.equal left.name right.name
    && Option.equal String.equal left.note right.note
  ;;
end

let select_statement =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Item.table |> order_by Item.id `Asc |> select Item.projection)
;;

let select_dsl ~conn =
  let* result = Adapter.run ~conn select_statement () in
  or_fail result
;;

let insert_dsl ~conn (item : Item.t) =
  let statement =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(
        into Item.table
        |> set Item.id_column item.id
        |> set Item.name_column item.name
        |> set Item.note_column item.note
        |> command)
  in
  let* result = Adapter.run ~conn statement () in
  let* _ = or_fail result in
  Lwt.return_unit
;;

let update_dsl ~conn (item : Item.t) =
  let statement =
    Statement.command
      ~dialect:Dialect.postgresql
      Update.(
        table Item.table
        |> set Item.name_column item.name
        |> set Item.note_column item.note
        |> where (fun row -> Item.id row =$ item.id)
        |> command)
  in
  let* result = Adapter.run ~conn statement () in
  let* _ = or_fail result in
  Lwt.return_unit
;;

let select_ppx ~conn =
  let* rows =
    [%pgsql.object conn "SELECT id, name, note FROM ppx_mixed_items ORDER BY id"]
  in
  Lwt.return (List.map rows ~f:Item.of_pgocaml)
;;

let insert_ppx ~conn ({ id; name; note } : Item.t) =
  [%pgsql conn "INSERT INTO ppx_mixed_items (id, name, note) VALUES ($id, $name, $?note)"]
;;

let update_ppx ~conn ({ id; name; note } : Item.t) =
  [%pgsql conn "UPDATE ppx_mixed_items SET name = $name, note = $?note WHERE id = $id"]
;;

let first : Item.t = { id = 1L; name = "O'Reilly"; note = None }
let second : Item.t = { id = 2L; name = "Grace"; note = Some "from PPX" }
let updated_first = { first with name = "Ada"; note = Some "updated by PPX" }
let updated_second = { second with name = "Grace Hopper"; note = None }
let expected = [ updated_first; updated_second ]
let check_rows actual expected = assert (List.equal Item.equal actual expected)

let mixed_writes ~conn ~observer =
  let* () = insert_dsl ~conn first in
  let* from_ppx = select_ppx ~conn in
  check_rows from_ppx [ first ];
  let* () = update_ppx ~conn updated_first in
  let* from_dsl = select_dsl ~conn in
  check_rows from_dsl [ updated_first ];
  let* () = insert_ppx ~conn second in
  let* () = update_dsl ~conn updated_second in
  let* from_ppx = select_ppx ~conn in
  check_rows from_ppx expected;
  let* outside = select_dsl ~conn:observer in
  check_rows outside [];
  Lwt.return_unit
;;

let test_commit ~conn ~observer =
  let* result =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* () = mixed_writes ~conn ~observer in
      Lwt.return (Ok ()))
  in
  let* () = or_fail result in
  let* outside = select_dsl ~conn:observer in
  check_rows outside expected;
  Lwt.return_unit
;;

let test_explicit_rollback ~conn ~observer =
  let* result =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* () = mixed_writes ~conn ~observer in
      Lwt.return (Error (Adapter.Encode "requested rollback")))
  in
  (match result with
   | Error (Adapter.Encode "requested rollback") -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "mixed transaction unexpectedly committed");
  let* outside = select_dsl ~conn:observer in
  check_rows outside [];
  Lwt.return_unit
;;

let test_ppx_exception_rollback ~conn ~observer =
  let* result =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* () = mixed_writes ~conn ~observer in
      let* () = insert_ppx ~conn first in
      Lwt.return (Ok ()))
  in
  (match result with
   | Error error ->
     assert (
       Adapter.Error.is_constraint_violation
         ~kind:Unique
         ~constraint_name:"ppx_mixed_items_pkey"
         ~table_name:"ppx_mixed_items"
         error)
   | Ok () -> failwith "duplicate PPX insert unexpectedly committed");
  let* outside = select_dsl ~conn:observer in
  check_rows outside [];
  let* inside = select_ppx ~conn in
  check_rows inside [];
  Lwt.return_unit
;;

let exec conn query =
  let* () = PGOCaml.prepare conn ~query () in
  let* _ = PGOCaml.execute conn ~params:[] () in
  Lwt.return_unit
;;

let with_connection f =
  let* conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Lwt.finalize (fun () -> f conn) (fun () -> PGOCaml.close conn)
;;

let main () =
  with_connection (fun conn ->
    with_connection (fun observer ->
      let* () =
        exec
          conn
          "CREATE TABLE public.ppx_mixed_items (id bigint PRIMARY KEY, name text NOT NULL, note text)"
      in
      Lwt.finalize
        (fun () ->
           let* () = test_commit ~conn ~observer in
           let* () = exec conn "TRUNCATE public.ppx_mixed_items" in
           let* () = test_explicit_rollback ~conn ~observer in
           let* () = test_ppx_exception_rollback ~conn ~observer in
           Lwt.return_unit)
        (fun () -> exec conn "DROP TABLE public.ppx_mixed_items")))
;;

let () = Lwt_main.run (main ())
