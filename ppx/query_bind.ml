open! Base
module Shared = Typed_sql_ppx_cache.Query_bind

type t =
  { sql : string
  ; parameters : Sql.parameter list
  }

let scan source =
  match Shared.scan source with
  | Error error -> Error { Sql.offset = error.offset; message = error.message }
  | Ok query ->
    Ok
      { sql = query.sql
      ; parameters =
          List.map query.parameters ~f:(fun p ->
            { Sql.expression = p.expression
            ; optional = p.optional
            ; start = p.start
            ; stop = p.stop
            })
      }
;;
