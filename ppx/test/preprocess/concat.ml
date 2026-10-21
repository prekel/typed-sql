open! Base
open Ppxlib

(* A test-only preprocessor with the registration contract of ppx_concat.
   It deliberately implements only the fragment forms used by the fixtures. *)
let preprocess_impl structure =
  let fragments = ref (Map.empty (module String)) in
  let rec text expression =
    match expression.pexp_desc with
    | Pexp_constant (Pconst_string (value, _, _)) -> value
    | Pexp_ident { txt = Lident name; _ } ->
      (match Map.find !fragments name with
       | Some value -> value
       | None ->
         Location.raise_errorf ~loc:expression.pexp_loc "unknown fragment: %s" name)
    | Pexp_apply (first, rest) ->
      let arguments =
        List.map rest ~f:(function
          | Nolabel, argument -> text argument
          | _, argument ->
            Location.raise_errorf ~loc:argument.pexp_loc "expected an unlabelled fragment")
      in
      String.concat ~sep:" " (text first :: arguments)
    | _ -> Location.raise_errorf ~loc:expression.pexp_loc "expected a SQL fragment"
  in
  let mapper =
    object
      inherit Ast_traverse.map as super

      method! structure items =
        List.filter_map items ~f:(fun item ->
          match item.pstr_desc with
          | Pstr_extension
              ( ( { txt = "concat"; _ }
                , PStr
                    [ { pstr_desc =
                          Pstr_value
                            ( Nonrecursive
                            , [ { pvb_pat = { ppat_desc = Ppat_var name; _ }
                                ; pvb_expr
                                ; _
                                }
                              ] )
                      ; _
                      }
                    ] )
              , _ ) ->
            fragments := Map.set !fragments ~key:name.txt ~data:(text pvb_expr);
            None
          | _ -> Some (super#structure_item item))

      method! expression expression =
        match expression.pexp_desc with
        | Pexp_extension
            ({ txt = "concat"; _ }, PStr [ { pstr_desc = Pstr_eval (body, []); _ } ]) ->
          Ast_builder.Default.estring ~loc:expression.pexp_loc (text body)
        | _ -> super#expression expression
    end
  in
  mapper#structure structure
;;

let () =
  Driver.register_transformation "query_cache_test_concat" ~preprocess_impl ~rules:[]
;;
