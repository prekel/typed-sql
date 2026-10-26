(* Quotation payload handling is adapted from PG'OCaml 4.4.0 ppx_pgsql.ml.
   Copyright (C) 2005-2016 Richard Jones and other authors.
   Distributed under the GNU Library General Public License, version 2 or later.
   See ../COPYING and ../ORIGIN.md. *)
open! Base
open Ppxlib

type t =
  { query : Query_bind.t
  ; loc : Location.t
  }

let literal_arguments_exn ~loc expression =
  let arguments =
    match expression.pexp_desc with
    | Pexp_constant (Pconst_string _) -> [ Nolabel, expression ]
    | Pexp_apply (_, arguments) -> arguments
    | _ -> Location.raise_errorf ~loc "expected SQL literal and optional flags"
  in
  List.map arguments ~f:(fun (label, expression) ->
    (match label with
     | Nolabel -> ()
     | _ ->
       Location.raise_errorf
         ~loc:expression.pexp_loc
         "labelled SQL arguments are not supported");
    match expression.pexp_desc with
    | Pexp_constant (Pconst_string (value, _, _)) -> value, expression.pexp_loc
    | _ -> Location.raise_errorf ~loc:expression.pexp_loc "expected SQL literal")
;;

let payload_exn ~loc ~with_connection = function
  | PStr [ { pstr_desc = Pstr_eval (expression, []); _ } ] ->
    let arguments =
      if with_connection then
        literal_arguments_exn ~loc expression
      else (
        match
          expression.pexp_desc
        with
        | Pexp_constant (Pconst_string _) -> literal_arguments_exn ~loc expression
        | Pexp_apply (first, rest) ->
          literal_arguments_exn ~loc first
          @ List.concat_map rest ~f:(fun (label, e) ->
            (match label with
             | Nolabel -> ()
             | _ ->
               Location.raise_errorf
                 ~loc:e.pexp_loc
                 "labelled SQL arguments are not supported");
            literal_arguments_exn ~loc e)
        | _ -> Location.raise_errorf ~loc "expected SQL literal")
    in
    (match List.rev arguments with
     | (sql, sql_loc) :: flags ->
       List.iter flags ~f:(fun (flag, flag_loc) ->
         if not (String.equal flag "nullable-results") then
           Location.raise_errorf ~loc:flag_loc "unsupported flag: %s" flag);
       List.rev_map flags ~f:fst, sql, sql_loc
     | [] -> Location.raise_errorf ~loc "missing SQL literal")
  | _ -> Location.raise_errorf ~loc "expected SQL quotation"
;;

let statement_payload_exn ~loc payload =
  match payload with
  | PStr
      [ { pstr_desc =
            Pstr_eval ({ pexp_desc = Pexp_fun (Nolabel, None, input, body); _ }, [])
        ; _
        }
      ] ->
    let flags, sql, sql_loc =
      payload_exn
        ~loc
        ~with_connection:false
        (PStr [ Ast_builder.Default.pstr_eval ~loc body [] ])
    in
    Some input, flags, sql, sql_loc
  | _ ->
    let flags, sql, sql_loc = payload_exn ~loc ~with_connection:false payload in
    None, flags, sql, sql_loc
;;

let collect_exn structure =
  let collected = ref [] in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! expression expression =
        (match expression.pexp_desc with
         | Pexp_extension
             ( { txt =
                   ( "pgsql"
                   | "pgsql.object"
                   | "pgsql.query"
                   | "pgsql.query.object"
                   | "pgsql.command"
                   | "pgsql.statement"
                   | "pgsql.statement.object" ) as name
               ; loc
               }
             , payload ) ->
           let _, sql, loc =
             if
               String.equal name "pgsql.statement"
               || String.equal name "pgsql.statement.object"
             then (
               let _, flags, sql, sql_loc = statement_payload_exn ~loc payload in
               flags, sql, sql_loc)
             else
               payload_exn
                 ~loc
                 ~with_connection:
                   (String.equal name "pgsql" || String.equal name "pgsql.object")
                 payload
           in
           (match Query_bind.scan sql with
            | Ok query -> collected := { query; loc } :: !collected
            | Error error ->
              Location.raise_errorf ~loc "SQL byte %d: %s" error.offset error.message)
         | _ -> ());
        super#expression expression
    end
  in
  visitor#structure structure;
  List.rev !collected
;;
