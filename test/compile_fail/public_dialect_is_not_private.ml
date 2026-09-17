open! Base
open Typed_sql

let expose (dialect : Dialect.t) : Typed_sql_private.Dialect.t = dialect
