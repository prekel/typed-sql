open! Base
open Typed_sql

let replace_parameters (query : int Compiled_query.t) = { query with parameters = [] }
