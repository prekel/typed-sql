(* Runtime generation is adapted from PG'OCaml 4.4.0 ppx_pgsql.ml.
   Copyright (C) 2005-2016 Richard Jones and other authors.
   Distributed under the GNU Library General Public License, version 2 or later.
   See COPYING and ORIGIN.md. *)
open! Base
open Ppxlib

let error ~loc message = Location.raise_errorf ~loc "typed-sql-pgocaml-ppx: %s" message

let check_environment ~loc =
  match Stdlib.Sys.getenv_opt "PGCUSTOM_CONVERTERS_CONFIG" with
  | Some config when not (String.is_empty config) ->
    error ~loc "custom converter config is not supported yet"
  | _ -> ()
;;

let payload ~loc = function
  | PStr [ { pstr_desc = Pstr_eval (expression, []); _ } ] ->
    let dbh, arguments =
      match expression.pexp_desc with
      | Pexp_apply (dbh, arguments) -> dbh, arguments
      | _ -> error ~loc "expected a connection, optional flags and a SQL literal"
    in
    let arguments =
      List.map arguments ~f:(function
        (* PR #80: accept both ordinary and delimited OCaml string constants. *)
        | ( Nolabel
          , { pexp_desc = Pexp_constant (Pconst_string (value, _, _)); pexp_loc; _ } ) ->
          value, pexp_loc
        | _, expression ->
          error ~loc:expression.pexp_loc "expected an unlabelled string literal")
    in
    (match List.rev arguments with
     | (sql, sql_loc) :: flags ->
       let flags = List.rev_map flags ~f:fst in
       List.iter flags ~f:(fun flag ->
         if not (String.equal flag "nullable-results") then
           error ~loc ("unsupported flag: " ^ flag));
       dbh, flags, sql, sql_loc
     | [] -> error ~loc "missing SQL literal")
  | _ -> error ~loc "expected a PG'OCaml expression quotation"
;;
