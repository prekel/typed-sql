open! Base
module Pgocaml = Typed_sql_pgocaml_lwt.Pgocaml
module Adapter = Typed_sql_pgocaml_lwt

let ( let* ) = Lwt.bind

let rec repeat remaining f =
  if remaining <= 0 then
    Lwt.return_unit
  else
    let* () = f () in
    repeat (remaining - 1) f
;;

let measure ~label ~iterations f =
  let started = Unix.gettimeofday () in
  let* () = repeat iterations f in
  let elapsed = Unix.gettimeofday () -. started in
  Stdlib.Printf.printf
    "%s: %d calls in %.3fs (%.0f/s)\n%!"
    label
    iterations
    elapsed
    (Float.of_int iterations /. elapsed);
  Lwt.return elapsed
;;

let main () =
  let* conn = Pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let query = "SELECT $1::bigint" in
       let params = [ Some "42" ] in
       let types = [ Int32.of_int_exn 20 ] in
       let uncached () =
         let* () = Pgocaml.prepare conn ~query ~types () in
         let* _ = Pgocaml.execute conn ~params () in
         Lwt.return_unit
       in
       let* () = Pgocaml.prepare conn ~name:"typed_sql_bench" ~query ~types () in
       let cached () =
         let* _ = Pgocaml.execute conn ~name:"typed_sql_bench" ~params () in
         Lwt.return_unit
       in
       let* () = repeat 100 uncached in
       let* () = repeat 100 cached in
       let* uncached_seconds =
         measure ~label:"prepare + execute" ~iterations:2_000 uncached
       in
       let* cached_seconds = measure ~label:"execute cached" ~iterations:2_000 cached in
       Stdlib.Printf.printf
         "cached speedup: %.2fx\n%!"
         (uncached_seconds /. cached_seconds);
       let* () = Pgocaml.close_statement conn ~name:"typed_sql_bench" () in
       let open Typed_sql in
       let statement =
         Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
           Statement.Parameters.map
             (params.expr ~name:"value" Db_type.int64 ~get:Fn.id)
             ~f:(fun value -> params.query_one (Query.select_one value)))
       in
       let cache =
         Adapter.Prepared_cache.create ~conn ()
         |> Result.map_error ~f:Adapter.error_to_string
         |> Result.ok_or_failwith
       in
       let adapter_call () =
         let* result = Adapter.run ~conn statement 42L in
         match result with
         | Ok 42L -> Lwt.return_unit
         | Ok _ -> Lwt.fail_with "unexpected adapter result"
         | Error error -> Lwt.fail_with (Adapter.error_to_string error)
       in
       let cached_adapter_call () =
         let* result = Adapter.Prepared_cache.run cache statement 42L in
         match result with
         | Ok 42L -> Lwt.return_unit
         | Ok _ -> Lwt.fail_with "unexpected cached adapter result"
         | Error error -> Lwt.fail_with (Adapter.error_to_string error)
       in
       let* () = repeat 100 adapter_call in
       let* () = repeat 100 cached_adapter_call in
       let* adapter_seconds =
         measure ~label:"adapter default" ~iterations:2_000 adapter_call
       in
       let* cached_adapter_seconds =
         measure ~label:"adapter cached" ~iterations:2_000 cached_adapter_call
       in
       Stdlib.Printf.printf
         "adapter cached speedup: %.2fx\n%!"
         (adapter_seconds /. cached_adapter_seconds);
       let* closed = Adapter.Prepared_cache.close cache in
       match closed with
       | Ok () -> Lwt.return_unit
       | Error error -> Lwt.fail_with (Adapter.error_to_string error))
    (fun () -> Pgocaml.close conn)
;;

let () = Lwt_main.run (main ())
