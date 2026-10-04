open! Base
module Adapter = Typed_sql_pgocaml_lwt
module Pgocaml = Adapter.Pgocaml
module Suite = Typed_sql_merge_integration

let ( let* ) = Lwt.bind

let normalize_error error =
  match error with
  | Adapter.Constraint_violation { kind = Check; _ } -> Suite.Check_violation
  | Adapter.Pgocaml _ -> Suite.Database_error (Adapter.error_to_string error)
  | _ -> Suite.Unexpected_error (Adapter.error_to_string error)
;;

let main () =
  let* conn = Pgocaml.connect () in
  let runner : Suite.runner =
    { exec_sql =
        (fun sql ->
          let* () = Pgocaml.prepare conn ~query:sql () in
          let* _ = Pgocaml.execute conn ~params:[] () in
          Lwt.return_unit)
    ; run =
        (fun statement ->
          let* result = Adapter.run ~conn statement () in
          Lwt.return (Result.map_error result ~f:normalize_error))
    }
  in
  Lwt.finalize (fun () -> Suite.run runner) (fun () -> Pgocaml.close conn)
;;

let () = Lwt_main.run (main ())
