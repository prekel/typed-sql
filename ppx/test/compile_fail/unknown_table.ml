(* expected: unknown table: public.missing *)
open! Base

let query conn = [%pgsql conn {|SELECT id FROM missing|}]
