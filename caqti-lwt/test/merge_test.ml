open! Base
module Adapter = Typed_sql_caqti_lwt
module Suite = Typed_sql_merge_integration
module T = Caqti.Template

let ( let* ) = Lwt.bind

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let normalize_error error =
  match error with
  | Adapter.Constraint_violation { kind = Check; _ } -> Suite.Check_violation
  | Adapter.Caqti _ -> Suite.Database_error (Adapter.error_to_string error)
  | _ -> Suite.Unexpected_error (Adapter.error_to_string error)
;;

let main () =
  let* connection = Caqti_lwt_unix.connect (Uri.of_string "postgresql://") in
  let* conn = Caqti_lwt.or_fail connection in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let runner : Suite.runner =
    { exec_sql =
        (fun sql ->
          let* result = Connection.exec (direct sql) () in
          Caqti_lwt.or_fail result)
    ; run =
        (fun statement ->
          let* result = Adapter.run ~conn statement () in
          Lwt.return (Result.map_error result ~f:normalize_error))
    }
  in
  Lwt.finalize (fun () -> Suite.run runner) (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
