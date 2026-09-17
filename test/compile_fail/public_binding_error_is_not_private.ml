open! Base
open Typed_sql

let expose (error : Statement.binding_error) : Typed_sql_private.Statement.binding_error =
  error
;;
