open! Base

(** Encode built-in type modifiers using PostgreSQL's catalog representation.
    No modifier is [-1]; absence of snapshot metadata remains separate. *)
val of_type_name : Sql_query.type_name -> (int, Sql_query.error) Result.t
