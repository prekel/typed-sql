open! Base

(** Values accepted by the GraphQL parser. Applications check argument types
    against their own schema before building typed-sql expressions. *)
module Value : sig
  type t = Graphql_parser.const_value

  val optional_int : t -> (int option, string) Result.t
  val optional_string : t -> (string option, string) Result.t
  val enum : t -> (string, string) Result.t
end

(** A field after aliases and variable references have been resolved. *)
module Field : sig
  type t =
    { name : string
    ; response_name : string
    ; arguments : (string * Value.t) list
    ; selections : t list
    }
end

(** Parsing is deliberately independent of database descriptors. The caller
    validates field and argument names against its schema and constructs the
    typed-sql query. Fragment and directive expansion is not supported. *)
module Request : sig
  type t = { root : Field.t }

  (** Accept one query operation with one root field. Variables may have Int
      or String types; defaults, fragments, directives, mutations and
      subscriptions are rejected. Duplicate argument and response names are
      rejected at each level. *)
  val parse : query:string -> variables:(string * Value.t) list -> (t, string) Result.t
end

(** Reusable JSON decoding for dynamically selected typed-sql expressions. *)
module Json_projection : sig
  val field
    :  key:string
    -> ('a, 'requirements) Typed_sql.Expr.t
    -> encode:('a -> Yojson.Safe.t)
    -> (string * Yojson.Safe.t, 'requirements) Typed_sql.Projection.t

  (** The list must contain at least one SQL expression: typed-sql rejects a
      SELECT projection containing only returned constants. *)
  val object_
    :  (string * Yojson.Safe.t, 'requirements) Typed_sql.Projection.t list
    -> (Yojson.Safe.t, 'requirements) Typed_sql.Projection.t
end
