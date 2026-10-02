open! Base
open Typed_sql_schema
module Pgocaml = Typed_sql_pgocaml_lwt.Pgocaml

module Thread = struct
  type 'a t = 'a Lwt.t

  include Monad.Make (struct
      type nonrec 'a t = 'a t

      let return = Lwt.return
      let bind value ~f = Lwt.bind value f
      let map = `Custom (fun value ~f -> Lwt.map f value)
    end)

  let fail = Lwt.fail
  let catch = Lwt.catch

  type in_channel = Lwt_io.input_channel
  type out_channel = Lwt_io.output_channel

  let open_connection address = Lwt_io.open_connection address
  let output_char = Lwt_io.write_char
  let output_binary_int = Lwt_io.BE.write_int
  let output_string = Lwt_io.write
  let flush = Lwt_io.flush
  let input_char = Lwt_io.read_char
  let input_binary_int = Lwt_io.BE.read_int
  let really_input = Lwt_io.read_into_exactly
  let close_in (channel : in_channel) = Lwt_io.close channel
end

module Custom_pgocaml = PGOCaml_generic.Make (Thread)
module Custom_schema = Typed_sql_schema_pgocaml_lwt.Make (Custom_pgocaml)

let ( let* ) = Lwt.bind

let check_schema schema =
  if
    not
      (List.exists (Schema_ir.tables schema) ~f:(fun table ->
         String.equal
           (Typed_sql.Identifier.to_string (Schema_ir.table_name table))
           "advanced"))
  then
    failwith "PG'OCaml introspector did not find the fixture table"
;;

let test_default () =
  let* conn = Pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let* result = Typed_sql_schema_pgocaml_lwt.introspect ~conn in
       (match result with
        | Ok schema -> check_schema schema
        | Error error -> failwith (Typed_sql_schema_pgocaml_lwt.error_to_string error));
       Lwt.return_unit)
    (fun () -> Pgocaml.close conn)
;;

let test_custom () =
  let* conn = Custom_pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let* result = Custom_schema.introspect ~conn in
       (match result with
        | Ok schema -> check_schema schema
        | Error error -> failwith (Custom_schema.error_to_string error));
       Lwt.return_unit)
    (fun () -> Custom_pgocaml.close conn)
;;

let () =
  Lwt_main.run
    (let* () = test_default () in
     test_custom ())
;;
