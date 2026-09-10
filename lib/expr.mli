open! Base

(** A typed scalar SQL expression. *)
type 'a t

val column : 'row Table_ref.t -> ('row, 'base, 'value) Column.t -> 'value t

(** A column selected through the nullable side of a LEFT JOIN. Existing
    schema nullability is flattened, so the result contains one [option]. *)
val nullable_column
  :  'row Nullable_table_ref.t
  -> ('row, 'base, 'value) Column.t
  -> 'base option t

val to_nullable : 'a t -> 'a option t
val param : 'a Db_type.t -> 'a -> 'a t
val is_null : 'a option t -> Condition.t
val is_not_null : 'a option t -> Condition.t
val db_type : 'a t -> 'a Db_type.t

(** Operators are the primary API for constructing comparisons. Operators with
    a dot compare expressions; operators ending with [$] bind an OCaml value
    using the type carried by the left expression. *)
module Infix : sig
  val ( =. ) : 'a t -> 'a t -> Condition.t
  val ( <>. ) : 'a t -> 'a t -> Condition.t
  val ( <. ) : 'a t -> 'a t -> Condition.t
  val ( <=. ) : 'a t -> 'a t -> Condition.t
  val ( >. ) : 'a t -> 'a t -> Condition.t
  val ( >=. ) : 'a t -> 'a t -> Condition.t
  val ( =$ ) : 'a t -> 'a -> Condition.t
  val ( <>$ ) : 'a t -> 'a -> Condition.t
  val ( <$ ) : 'a t -> 'a -> Condition.t
  val ( <=$ ) : 'a t -> 'a -> Condition.t
  val ( >$ ) : 'a t -> 'a -> Condition.t
  val ( >=$ ) : 'a t -> 'a -> Condition.t
  val ( =~. ) : string t -> string t -> Condition.t
  val ( =~$ ) : string t -> string -> Condition.t
end

module Private : sig
  val node : 'a t -> Ast.expr
  val create : Ast.expr -> 'a Db_type.t -> 'a t
end
