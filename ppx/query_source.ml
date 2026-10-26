open! Base
open Ppxlib

type t =
  { query : Query_bind.t
  ; loc : Location.t
  }

let collect_exn structure =
  let queries = ref [] in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! expression expression =
        (match expression.pexp_desc with
         | Pexp_extension ({ txt = "pgsql" | "pgsql.object"; loc }, payload) ->
           let _, _, sql, loc = Quotation.payload ~loc payload in
           Quotation.check_environment ~loc;
           (match Query_bind.scan sql with
            | Ok query -> queries := { query; loc } :: !queries
            | Error error ->
              Location.raise_errorf ~loc "%s" (Query_bind.error_to_string error))
         | _ -> ());
        super#expression expression
    end
  in
  visitor#structure structure;
  List.rev !queries
;;
