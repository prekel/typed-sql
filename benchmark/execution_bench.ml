open! Base
open Typed_sql
open Infix
module T = Caqti.Template

let ( let* ) = Lwt.bind

let caqti_or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "benchmark_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let projection row = Projection.pair (id row) (name row)
end

let statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    Parameters.map (params.column Item.id_column ~get:Fn.id) ~f:(fun id ->
      params.expect_one
        Query.(
          from Item.table
          |> where (fun item -> Item.id item =. id)
          |> select Item.projection)))
;;

let direct sql =
  let request_type = T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit) in
  T.Request.create T.Request.Direct request_type (fun _ -> T.Query.parse sql)
;;

let adapter_or_fail = function
  | Ok value -> value
  | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
;;

let rec repeat iterations f =
  if iterations = 0 then
    Lwt.return_unit
  else
    let* result = f () in
    let (_ : int64 * string) = adapter_or_fail result in
    repeat (iterations - 1) f
;;

let measure ~name ~iterations f =
  Stdlib.Gc.full_major ();
  let started = Unix.gettimeofday () in
  let* () = repeat iterations f in
  let elapsed = Unix.gettimeofday () -. started in
  Stdlib.Printf.printf
    "%-24s %7d iterations in %.3fs (%9.0f/s)\n"
    name
    iterations
    elapsed
    (Float.of_int iterations /. elapsed);
  Lwt.return_unit
;;

let main () =
  let* conn =
    Caqti_lwt_unix.connect (Uri.of_string "sqlite3::memory:") |> caqti_or_fail
  in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* () =
         Connection.exec
           (direct
              "CREATE TABLE benchmark_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
           ()
         |> caqti_or_fail
       in
       let* () =
         Connection.exec
           (direct "INSERT INTO benchmark_items (id, name) VALUES (1, 'one')")
           ()
         |> caqti_or_fail
       in
       let iterations = 10_000 in
       let* () =
         measure ~name:"statement" ~iterations (fun () ->
           Typed_sql_caqti_lwt.run ~conn statement 1L)
       in
       measure ~name:"observer enabled" ~iterations (fun () ->
         Typed_sql_caqti_lwt.run ~observer:ignore ~conn statement 1L))
    (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
